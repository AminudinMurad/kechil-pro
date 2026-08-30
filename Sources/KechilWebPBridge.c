#include "KechilWebPBridge.h"

#include <stdlib.h>
#include <string.h>

#include "webp/encode.h"

int KechilWebPEncodeRGBA(const uint8_t* rgba,
                         int width,
                         int height,
                         int stride,
                         float quality,
                         int lossless,
                         int method,
                         uint8_t** output,
                         size_t* output_size) {
  WebPConfig config;
  WebPPicture picture;
  WebPMemoryWriter writer;
  uint8_t* copy;

  if (rgba == NULL || output == NULL || output_size == NULL || width <= 0 ||
      height <= 0 || stride < width * 4) {
    return 0;
  }
  *output = NULL;
  *output_size = 0;

  if (!WebPConfigInit(&config) || !WebPPictureInit(&picture)) return 0;
  config.quality = quality;
  config.lossless = lossless != 0;
  config.method = method < 0 ? 0 : (method > 6 ? 6 : method);
  config.alpha_quality = 100;
  config.thread_level = 1;
  if (!WebPValidateConfig(&config)) return 0;

  picture.width = width;
  picture.height = height;
  picture.use_argb = 1;
  if (!WebPPictureImportRGBA(&picture, rgba, stride)) {
    WebPPictureFree(&picture);
    return 0;
  }

  WebPMemoryWriterInit(&writer);
  picture.writer = WebPMemoryWrite;
  picture.custom_ptr = &writer;
  if (!WebPEncode(&config, &picture)) {
    WebPMemoryWriterClear(&writer);
    WebPPictureFree(&picture);
    return 0;
  }
  WebPPictureFree(&picture);

  copy = (uint8_t*)malloc(writer.size);
  if (copy == NULL) {
    WebPMemoryWriterClear(&writer);
    return 0;
  }
  memcpy(copy, writer.mem, writer.size);
  *output = copy;
  *output_size = writer.size;
  WebPMemoryWriterClear(&writer);
  return 1;
}

void KechilWebPFree(void* memory) { free(memory); }
