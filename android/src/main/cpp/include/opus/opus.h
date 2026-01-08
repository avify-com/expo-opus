/*
 * Opus encoder header - placeholder
 *
 * This file will be replaced by the real opus.h when you run:
 *   scripts/build-opus-android.sh
 *
 * The build script downloads official sources from Xiph.org and
 * copies the headers here.
 */

#ifndef OPUS_H
#define OPUS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Opus application modes */
#define OPUS_APPLICATION_VOIP                2048
#define OPUS_APPLICATION_AUDIO               2049
#define OPUS_APPLICATION_RESTRICTED_LOWDELAY 2051

/* Error codes */
#define OPUS_OK               0
#define OPUS_BAD_ARG          -1
#define OPUS_BUFFER_TOO_SMALL -2
#define OPUS_INTERNAL_ERROR   -3
#define OPUS_INVALID_PACKET   -4
#define OPUS_UNIMPLEMENTED    -5
#define OPUS_INVALID_STATE    -6
#define OPUS_ALLOC_FAIL       -7

/* CTL macros */
#define OPUS_SET_BITRATE_REQUEST         4002
#define OPUS_SET_BITRATE(x)              OPUS_SET_BITRATE_REQUEST, (opus_int32)(x)
#define OPUS_SET_COMPLEXITY_REQUEST      4010
#define OPUS_SET_COMPLEXITY(x)           OPUS_SET_COMPLEXITY_REQUEST, (opus_int32)(x)
#define OPUS_SET_VBR_REQUEST             4006
#define OPUS_SET_VBR(x)                  OPUS_SET_VBR_REQUEST, (opus_int32)(x)

/* Types */
typedef int opus_int32;
typedef short opus_int16;

/* Opaque encoder state */
typedef struct OpusEncoder OpusEncoder;

/* Function declarations */
OpusEncoder *opus_encoder_create(
    opus_int32 Fs,
    int channels,
    int application,
    int *error
);

void opus_encoder_destroy(OpusEncoder *st);

int opus_encode(
    OpusEncoder *st,
    const opus_int16 *pcm,
    int frame_size,
    unsigned char *data,
    opus_int32 max_data_bytes
);

int opus_encoder_ctl(OpusEncoder *st, int request, ...);

const char *opus_get_version_string(void);

#ifdef __cplusplus
}
#endif

#endif /* OPUS_H */
