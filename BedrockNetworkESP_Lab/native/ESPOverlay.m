#import "ESPOverlay.h"

#import "Diagnostics.h"
#import "WorldToScreen.h"
#import "../src/common/BNEClock.h"
#import <math.h>

static const uint64_t kBNEFreshnessLimitMilliseconds = 1000;
static const double kBNEApproximateEntityBounds[3] = {0.6, 1.8, 0.6};

@implementation BNEESPOverlay {
    BNESnapshot _snapshot;
    BNECameraSnapshot _camera;
    BOOL _hasSnapshot;
    BOOL _hasCamera;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _maximumRenderDistance = 128.0;
    _showsNamesAndDistance = YES;
    _includedTypeIdentifiers = @[];
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    self.accessibilityLabel = @"Experimental entity overlay diagnostics";
    return self;
}

- (void)updateWithSnapshot:(const BNESnapshot *)snapshot
                    camera:(const BNECameraSnapshot *)camera {
    BNESnapshot snapshotCopy = {0};
    BNECameraSnapshot cameraCopy = {0};
    BOOL hasSnapshot = snapshot != NULL;
    BOOL hasCamera = camera != NULL;
    if (hasSnapshot) snapshotCopy = *snapshot;
    if (hasCamera) cameraCopy = *camera;

    void (^publish)(void) = ^{
        self->_snapshot = snapshotCopy;
        self->_camera = cameraCopy;
        self->_hasSnapshot = hasSnapshot;
        self->_hasCamera = hasCamera;
        [self setNeedsDisplay];
    };
    if (NSThread.isMainThread) publish();
    else dispatch_async(dispatch_get_main_queue(), publish);
}

- (BOOL)isFreshAtTime:(uint64_t)now observedAt:(uint64_t)observedAt {
    return observedAt > 0 && observedAt <= now &&
        now - observedAt <= kBNEFreshnessLimitMilliseconds;
}

- (void)drawStatus:(NSString *)status atY:(CGFloat)y {
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.whiteColor
    };
    [status drawAtPoint:CGPointMake(8, y) withAttributes:attributes];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    uint64_t now = bne_monotonic_time_ms();
    BOOL hasFreshEntities = _hasSnapshot && _snapshot.count > 0 &&
        [self isFreshAtTime:now observedAt:_snapshot.published_at_ms];
    BOOL hasFreshCamera = _hasCamera &&
        [self isFreshAtTime:now observedAt:_camera.observed_at_ms];
    if (!hasFreshEntities) {
        NSString *status = (!_hasSnapshot || _snapshot.diagnostics.event_count == 0)
            ? @"ENTITY DATA SOURCE UNAVAILABLE"
            : @"NO FRESH ENTITY POSITIONS";
        [self drawStatus:status atY:8];
    }
    if (!hasFreshCamera) [self drawStatus:@"CAMERA SOURCE UNAVAILABLE" atY:24];
    if (!hasFreshEntities || !hasFreshCamera) return;
    CGRect viewport = self.bounds;
    if (fabs(CGRectGetWidth(viewport) - _camera.viewport.size.width) > 1.0 ||
        fabs(CGRectGetHeight(viewport) - _camera.viewport.size.height) > 1.0 ||
        fabs(CGRectGetMinX(viewport) - _camera.viewport.origin.x) > 1.0 ||
        fabs(CGRectGetMinY(viewport) - _camera.viewport.origin.y) > 1.0) {
        [self drawStatus:@"CAMERA VIEWPORT MISMATCH" atY:24];
        return;
    }

    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    NSDictionary *labelAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: UIColor.whiteColor
    };
    CGContextSetStrokeColorWithColor(context, UIColor.cyanColor.CGColor);
    CGContextSetLineWidth(context, 1.5);

    for (size_t index = 0; index < _snapshot.count; index++) {
        const BNEEntitySnapshot *entity = &_snapshot.entities[index];
        if (entity->position_source == BNE_SOURCE_TEST_FIXTURE ||
            entity->position_source == BNE_SOURCE_SERVER_GROUND_TRUTH ||
            ![self isFreshAtTime:now observedAt:entity->position_observed_at_ms]) continue;
        NSString *typeIdentifier = [NSString stringWithUTF8String:entity->entity_type_id];
        if (!typeIdentifier || (self.includedTypeIdentifiers.count > 0 &&
            ![self.includedTypeIdentifiers containsObject:typeIdentifier])) continue;

        double dx = entity->position[0] - _camera.camera_position[0];
        double dy = entity->position[1] - _camera.camera_position[1];
        double dz = entity->position[2] - _camera.camera_position[2];
        double distance = sqrt(dx * dx + dy * dy + dz * dz);
        if (!isfinite(distance) || distance > self.maximumRenderDistance) continue;

        BNEProjectedRect projected;
        if (!bne_world_to_screen(&_camera, entity->position,
                                 kBNEApproximateEntityBounds, &projected)) continue;
        CGRect box = CGRectMake(projected.x, projected.y,
                                projected.width, projected.height);
        CGContextStrokeRect(context, box);
        if (self.showsNamesAndDistance) {
            NSString *label = [NSString stringWithFormat:@"%@  %.1fm",
                               typeIdentifier, distance];
            [label drawAtPoint:CGPointMake(box.origin.x,
                MAX(8, box.origin.y - 14)) withAttributes:labelAttributes];
        }
    }
}

@end