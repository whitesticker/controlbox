#pragma once

#include <stdbool.h>

typedef void (*AppleTVTouchFrameCallback)(
    float x,
    float y,
    bool active,
    float size,
    int familyID,
    void *context
);

void AppleTVMultitouchStart(AppleTVTouchFrameCallback callback, void *context);
void AppleTVMultitouchStop(void);
int AppleTVMultitouchActiveFamilyID(void);
