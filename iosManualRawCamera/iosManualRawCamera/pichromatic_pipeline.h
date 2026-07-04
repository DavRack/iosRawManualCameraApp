#ifndef pichromatic_pipeline_h
#define pichromatic_pipeline_h

#include <stdint.h>
#include <stddef.h>

typedef struct Image Image;
typedef struct PipelineConfig PipelineConfig;

#ifdef __cplusplus
extern "C" {
#endif

Image* get_raw_img(const uint8_t* file_bytes_ptr, size_t file_bytes_len);

PipelineConfig* get_pixel_pipeline_c(const uint8_t* config_ptr, size_t config_len);

Image* run_pixel_pipeline_c(Image* image, PipelineConfig* pixel_pipeline);

const uint8_t* get_image_rgb_data_c(Image* image, size_t* out_width, size_t* out_height, size_t* out_len);

void free_image_c(Image* image);
void free_pipeline_c(PipelineConfig* pipeline);
void free_rgb_buffer_c(uint8_t* ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* pichromatic_pipeline_h */
