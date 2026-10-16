#include "../../src/projection/BNEProjection.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>

static const double identity[16] = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
};

int main(void) {
    BNEProjectedRect rectangle;
    const double position[3] = {0, 0, 0};
    const double dimensions[3] = {1, 1, 1};
    assert(bne_project_aabb(identity, position, dimensions, -1, 1,
                            0, 0, 1000, 500, &rectangle));
    assert(fabs(rectangle.x - 250) < 1e-9);
    assert(fabs(rectangle.y) < 1e-9);
    assert(fabs(rectangle.width - 500) < 1e-9);
    assert(fabs(rectangle.height - 250) < 1e-9);
    assert(bne_project_aabb(identity, position, dimensions, -1, 1,
                            20, 30, 500, 300, &rectangle));
    assert(fabs(rectangle.x - 145) < 1e-9);
    assert(fabs(rectangle.y - 30) < 1e-9);

    const double outside[3] = {3, 0, 0};
    assert(!bne_project_aabb(identity, outside, dimensions, -1, 1,
                             0, 0, 1000, 500, &rectangle));
    double behind[16] = {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 1, 0
    };
    const double behind_position[3] = {0, 0, -2};
    assert(!bne_project_aabb(behind, behind_position, dimensions, -1, 1,
                             0, 0, 1000, 500, &rectangle));
    double invalid[16];
    for (int index = 0; index < 16; index++) invalid[index] = identity[index];
    invalid[0] = NAN;
    assert(!bne_project_aabb(invalid, position, dimensions, -1, 1,
                             0, 0, 1000, 500, &rectangle));
    puts("projection fixture tests passed (synthetic matrix only)");
    return 0;
}