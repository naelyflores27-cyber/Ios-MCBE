#include "BNEProjection.h"

#include <float.h>
#include <math.h>

static double bne_transform(const double matrix[16], int row,
                            double x, double y, double z) {
    return matrix[row] * x + matrix[4 + row] * y +
        matrix[8 + row] * z + matrix[12 + row];
}

int bne_project_aabb(const double matrix[16], const double position[3],
                     const double dimensions[3], double depth_minimum,
                     double depth_maximum, double viewport_x, double viewport_y,
                     double viewport_width, double viewport_height,
                     BNEProjectedRect *result) {
    if (!matrix || !position || !dimensions || !result ||
        !isfinite(depth_minimum) || !isfinite(depth_maximum) ||
        depth_minimum >= depth_maximum || !isfinite(viewport_x) ||
        !isfinite(viewport_y) || !isfinite(viewport_width) ||
        !isfinite(viewport_height) || viewport_width <= 0 || viewport_height <= 0) {
        return 0;
    }
    for (int index = 0; index < 16; index++) if (!isfinite(matrix[index])) return 0;
    for (int index = 0; index < 3; index++) {
        if (!isfinite(position[index]) || !isfinite(dimensions[index]) ||
            dimensions[index] <= 0) return 0;
    }

    double min_x = DBL_MAX, min_y = DBL_MAX;
    double max_x = -DBL_MAX, max_y = -DBL_MAX;
    for (unsigned corner = 0; corner < 8; corner++) {
        double x = position[0] + ((corner & 1) ? dimensions[0] * 0.5 : -dimensions[0] * 0.5);
        double y = position[1] + ((corner & 2) ? dimensions[1] : 0.0);
        double z = position[2] + ((corner & 4) ? dimensions[2] * 0.5 : -dimensions[2] * 0.5);
        double clip_x = bne_transform(matrix, 0, x, y, z);
        double clip_y = bne_transform(matrix, 1, x, y, z);
        double clip_z = bne_transform(matrix, 2, x, y, z);
        double clip_w = bne_transform(matrix, 3, x, y, z);
        if (!isfinite(clip_w) || clip_w <= 1e-5) return 0;
        double ndc_x = clip_x / clip_w;
        double ndc_y = clip_y / clip_w;
        double ndc_z = clip_z / clip_w;
        if (!isfinite(ndc_x) || !isfinite(ndc_y) || !isfinite(ndc_z) ||
            ndc_z < depth_minimum || ndc_z > depth_maximum) return 0;
        if (ndc_x < min_x) min_x = ndc_x;
        if (ndc_x > max_x) max_x = ndc_x;
        if (ndc_y < min_y) min_y = ndc_y;
        if (ndc_y > max_y) max_y = ndc_y;
    }
    if (max_x < -1 || min_x > 1 || max_y < -1 || min_y > 1) return 0;

    double left = viewport_x + (fmax(min_x, -1) + 1) * 0.5 * viewport_width;
    double right = viewport_x + (fmin(max_x, 1) + 1) * 0.5 * viewport_width;
    double top = viewport_y + (1 - fmin(max_y, 1)) * 0.5 * viewport_height;
    double bottom = viewport_y + (1 - fmax(min_y, -1)) * 0.5 * viewport_height;
    if (!isfinite(left) || !isfinite(right) || !isfinite(top) || !isfinite(bottom) ||
        right <= left || bottom <= top) return 0;
    result->x = left;
    result->y = top;
    result->width = right - left;
    result->height = bottom - top;
    return 1;
}