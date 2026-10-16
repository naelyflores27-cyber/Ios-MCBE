#import "CameraDataSource.h"

#import <math.h>
#import <os/lock.h>
#import <string.h>

static os_unfair_lock s_camera_lock = OS_UNFAIR_LOCK_INIT;
static BNECameraSnapshot s_camera_snapshot;
static bool s_camera_available;

static bool BNECameraSnapshotIsValid(const BNECameraSnapshot *snapshot) {
    if (!snapshot || snapshot->observed_at_ms == 0 || snapshot->source[0] == '\0' ||
        !memchr(snapshot->source, '\0', sizeof(snapshot->source)) ||
        !isfinite(snapshot->clip_depth_minimum) ||
        !isfinite(snapshot->clip_depth_maximum) ||
        snapshot->clip_depth_minimum >= snapshot->clip_depth_maximum ||
        CGRectIsEmpty(snapshot->viewport) ||
        !isfinite(snapshot->viewport.origin.x) ||
        !isfinite(snapshot->viewport.origin.y) ||
        !isfinite(snapshot->viewport.size.width) ||
        !isfinite(snapshot->viewport.size.height)) return false;
    for (size_t index = 0; index < 16; index++) {
        if (!isfinite(snapshot->view_projection[index])) return false;
    }
    for (size_t index = 0; index < 3; index++) {
        if (!isfinite(snapshot->camera_position[index])) return false;
    }
    return true;
}

bool bne_camera_data_source_publish(const BNECameraSnapshot *snapshot) {
    if (!BNECameraSnapshotIsValid(snapshot)) {
        bne_camera_data_source_clear();
        return false;
    }
    os_unfair_lock_lock(&s_camera_lock);
    s_camera_snapshot = *snapshot;
    s_camera_available = true;
    os_unfair_lock_unlock(&s_camera_lock);
    return true;
}

void bne_camera_data_source_clear(void) {
    os_unfair_lock_lock(&s_camera_lock);
    memset(&s_camera_snapshot, 0, sizeof(s_camera_snapshot));
    s_camera_available = false;
    os_unfair_lock_unlock(&s_camera_lock);
}

bool bne_camera_data_source_copy(BNECameraSnapshot *snapshot) {
    if (!snapshot) return false;
    os_unfair_lock_lock(&s_camera_lock);
    bool available = s_camera_available;
    if (available) *snapshot = s_camera_snapshot;
    os_unfair_lock_unlock(&s_camera_lock);
    return available;
}