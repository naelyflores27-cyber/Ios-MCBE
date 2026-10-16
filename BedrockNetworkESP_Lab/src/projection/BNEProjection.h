#ifndef BNE_PROJECTION_H
#define BNE_PROJECTION_H

typedef struct {
    double x;
    double y;
    double width;
    double height;
} BNEProjectedRect;

int bne_project_aabb(const double column_major_matrix[16],
                     const double position[3],
                     const double dimensions[3],
                     double clip_depth_minimum,
                     double clip_depth_maximum,
                     double viewport_x,
                     double viewport_y,
                     double viewport_width,
                     double viewport_height,
                     BNEProjectedRect *result);

#endif