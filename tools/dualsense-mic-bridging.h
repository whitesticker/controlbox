#include <opus/opus.h>

static inline int ds_opus_set_bitrate(OpusEncoder *st, opus_int32 bitrate) {
    return opus_encoder_ctl(st, OPUS_SET_BITRATE(bitrate));
}

static inline int ds_opus_set_vbr(OpusEncoder *st, int enabled) {
    return opus_encoder_ctl(st, OPUS_SET_VBR(enabled));
}

static inline int ds_opus_set_frame_10ms(OpusEncoder *st) {
    return opus_encoder_ctl(st, OPUS_SET_EXPERT_FRAME_DURATION(OPUS_FRAMESIZE_10_MS));
}
