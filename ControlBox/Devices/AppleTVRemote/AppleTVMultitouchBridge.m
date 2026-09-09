#import "AppleTVMultitouchBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef CFTypeRef MTDeviceRef;
typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef);
typedef OSStatus (*MTDeviceGetFamilyIDFn)(MTDeviceRef, int *);
typedef OSStatus (*MTDeviceGetSensorSurfaceDimensionsFn)(MTDeviceRef, int *, int *);
typedef OSStatus (*MTDeviceStartFn)(MTDeviceRef, int);
typedef OSStatus (*MTDeviceStopFn)(MTDeviceRef);
typedef void (*MTRegisterContactFrameCallbackWithRefconFn)(
    MTDeviceRef,
    void (*)(MTDeviceRef, MTTouch *, size_t, double, size_t, void *),
    void *
);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef, void *);

static void *gFramework;
static MTDeviceCreateListFn gCreateList;
static MTDeviceIsBuiltInFn gIsBuiltIn;
static MTDeviceGetFamilyIDFn gGetFamilyID;
static MTDeviceGetSensorSurfaceDimensionsFn gGetSurface;
static MTDeviceStartFn gStart;
static MTDeviceStopFn gStop;
static MTRegisterContactFrameCallbackWithRefconFn gRegister;
static MTUnregisterContactFrameCallbackFn gUnregister;

static AppleTVTouchFrameCallback gCallback;
static void *gContext;
static MTDeviceRef gDevice;
static MTDeviceRef gActiveTouchDevice;
static int gFamilyID;
static const size_t kMaxDevices = 16;
static MTDeviceRef gStarted[kMaxDevices];
static size_t gStartedCount;

static void *loadSymbol(const char *name) {
    return dlsym(gFramework, name);
}

static int familyIDOf(MTDeviceRef device) {
    int family = 0;
    if (gGetFamilyID) {
        gGetFamilyID(device, &family);
    }
    return family;
}

static void touchFrame(
    MTDeviceRef device,
    MTTouch *touches,
    size_t numTouches,
    double timestamp,
    size_t frame,
    void *refcon
) {
    (void)timestamp;
    (void)frame;
    (void)refcon;
    if (!gCallback) { return; }
    int family = familyIDOf(device);
    if (numTouches == 0 || touches == NULL) {
        if (gActiveTouchDevice != NULL && gActiveTouchDevice != device) {
            return;
        }
        gActiveTouchDevice = NULL;
        gCallback(0.5f, 0.5f, false, 0, family, gContext);
        return;
    }
    MTTouch touch = touches[0];
    float x = touch.normalizedVector.position.x;
    float y = 1.0f - touch.normalizedVector.position.y;
    bool active = touch.state >= 3 && touch.state <= 5;
    if (active) {
        gActiveTouchDevice = device;
        gCallback(x, y, active, touch.zTotal, family, gContext);
        return;
    }
    if (gActiveTouchDevice != NULL && gActiveTouchDevice != device) {
        return;
    }
    gActiveTouchDevice = NULL;
    gCallback(x, y, false, touch.zTotal, family, gContext);
}

static bool shouldStartDevice(MTDeviceRef device, int *outFamily) {
    int family = 0;
    if (gGetFamilyID) {
        gGetFamilyID(device, &family);
    }
    *outFamily = family;

    if (gIsBuiltIn && gIsBuiltIn(device)) {
        return family == 145;
    }

    int width = 0;
    int height = 0;
    if (gGetSurface) {
        gGetSurface(device, &width, &height);
    }
    if (family == 145) { return true; }
    if (width > 0 && width < 6000 && height > 0 && height < 6000) { return true; }
    if (!gIsBuiltIn) { return family != 0 && family != 98; }
    return false;
}

void AppleTVMultitouchStart(AppleTVTouchFrameCallback callback, void *context) {
    AppleTVMultitouchStop();
    gCallback = callback;
    gContext = context;

    gFramework = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    );
    if (!gFramework) { return; }

    gCreateList = loadSymbol("MTDeviceCreateList");
    gIsBuiltIn = loadSymbol("MTDeviceIsBuiltIn");
    gGetFamilyID = loadSymbol("MTDeviceGetFamilyID");
    gGetSurface = loadSymbol("MTDeviceGetSensorSurfaceDimensions");
    gStart = loadSymbol("MTDeviceStart");
    gStop = loadSymbol("MTDeviceStop");
    gRegister = loadSymbol("MTRegisterContactFrameCallbackWithRefcon");
    gUnregister = loadSymbol("MTUnregisterContactFrameCallback");
    if (!gCreateList || !gStart || !gRegister) { return; }

    CFArrayRef list = gCreateList();
    if (!list) { return; }

    CFIndex count = CFArrayGetCount(list);
    bool startedExternal = false;
    for (CFIndex pass = 0; pass < 2; pass++) {
        for (CFIndex i = 0; i < count && gStartedCount < kMaxDevices; i++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
            int family = 0;
            if (!shouldStartDevice(device, &family)) { continue; }
            bool builtin = gIsBuiltIn && gIsBuiltIn(device);
            if (pass == 0 && builtin) { continue; }
            if (pass == 1 && (!builtin || startedExternal)) { continue; }
            gRegister(device, touchFrame, context);
            gStart(device, 0);
            gStarted[gStartedCount++] = device;
            if (!builtin) { startedExternal = true; }
            if (gDevice == NULL || !builtin) {
                gDevice = device;
                gFamilyID = family;
            }
        }
    }
    CFRelease(list);
}

void AppleTVMultitouchStop(void) {
    for (size_t i = 0; i < gStartedCount; i++) {
        MTDeviceRef device = gStarted[i];
        if (gUnregister) {
            gUnregister(device, (void *)touchFrame);
        }
        if (gStop) {
            gStop(device);
        }
        gStarted[i] = NULL;
    }
    gStartedCount = 0;
    gDevice = NULL;
    gActiveTouchDevice = NULL;
    gFamilyID = 0;
    gCallback = NULL;
    gContext = NULL;
}

int AppleTVMultitouchActiveFamilyID(void) {
    return gFamilyID;
}
