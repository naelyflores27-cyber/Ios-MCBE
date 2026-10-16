#ifndef BNE_WORLD_TO_SCREEN_H
#define BNE_WORLD_TO_SCREEN_H

#include "CameraDataSource.h"
#include "../src/projection/BNEProjection.h"

static inline int bne_world_to_screen(const BNECameraSnapshot *camera,
                                      const double position[3],
                                      const double dimensions[3],
                                      BNEProjectedRect *result) {
    if (!camera) return 0;
    return bne_project_aabb(camera->view_projection, position, dimensions,
                            camera->clip_depth_minimum,
                            camera->clip_depth_maximum,
                            camera->viewport.origin.x,
                            camera->viewport.origin.y,
                            camera->viewport.size.width,
                            camera->viewport.size.height,
                            result);
}

#endif