#ifndef BNE_CAMERA_DATA_SOURCE_H
#define BNE_CAMERA_DATA_SOURCE_H

#import <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

#define BNE_CAMERA_SOURCE_CAPACITY 96

typedef struct {
    double view_projection[16];
    double camera_position[3];
    double clip_depth_minimum;
    double clip_depth_maximum;
    CGRect viewport;
    uint64_t observed_at_ms;
    char source[BNE_CAMERA_SOURCE_CAPACITY];
} BNECameraSnapshot;

bool bne_camera_data_source_publish(const BNECameraSnapshot *snapshot);
void bne_camera_data_source_clear(void);
bool bne_camera_data_source_copy(BNECameraSnapshot *snapshot);

#endif