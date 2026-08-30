#ifndef KECHIL_WEBP_BRIDGE_H_
#define KECHIL_WEBP_BRIDGE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Encodes straight (not premultiplied) RGBA pixels with the vendored libwebp.
/// The caller owns `*output` and releases it with KechilWebPFree().
int KechilWebPEncodeRGBA(const uint8_t* rgba,
                         int width,
                         int height,
                         int stride,
                         float quality,
                         int lossless,
                         int method,
                         uint8_t** output,
                         size_t* output_size);

void KechilWebPFree(void* memory);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // KECHIL_WEBP_BRIDGE_H_
