#ifndef opus_swift_helpers_h
#define opus_swift_helpers_h

#include "opus/opus.h"
#include "opus/opus_defines.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Swift-compatible wrapper functions for opus_encoder_ctl variadic calls.
 * Swift cannot call C variadic functions directly, so these provide
 * non-variadic alternatives.
 */

/**
 * Set the bitrate of the Opus encoder.
 * @param encoder The Opus encoder state
 * @param bitrate Bitrate in bits per second (500 to 512000)
 * @return OPUS_OK on success, or an error code
 */
static inline int opus_encoder_set_bitrate(OpusEncoder *encoder, opus_int32 bitrate) {
    return opus_encoder_ctl(encoder, OPUS_SET_BITRATE_REQUEST, bitrate);
}

/**
 * Set the complexity of the Opus encoder.
 * @param encoder The Opus encoder state
 * @param complexity Complexity value 0-10 (higher = better quality, more CPU)
 * @return OPUS_OK on success, or an error code
 */
static inline int opus_encoder_set_complexity(OpusEncoder *encoder, opus_int32 complexity) {
    return opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY_REQUEST, complexity);
}

/**
 * Enable or disable VBR (Variable Bit Rate) mode.
 * @param encoder The Opus encoder state
 * @param vbr 0 = CBR (Constant Bit Rate), 1 = VBR
 * @return OPUS_OK on success, or an error code
 */
static inline int opus_encoder_set_vbr(OpusEncoder *encoder, opus_int32 vbr) {
    return opus_encoder_ctl(encoder, OPUS_SET_VBR_REQUEST, vbr);
}

#ifdef __cplusplus
}
#endif

#endif /* opus_swift_helpers_h */
