#import "CLESPOverlay.h"
#import "CLCameraProvider.h"
#import "CLEntityTypeRegistry.h"
#import "CLDiagnostics.h"

@implementation CLESPOverlay {
    NSArray<CLWorldEntitySnapshot *> *_snapshots;
    NSUInteger _rejectedSnapshotCount;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _enabled = NO;
    _snapshots = @[];
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.accessibilityLabel = @"Live entity overlay";
    [CLDiagnostics recordEvent:@"CL_ESP" stage:@"overlay.initialized"
                       message:@"Live overlay view initialized"
                        fields:@{@"width": @(CGRectGetWidth(frame)), @"height": @(CGRectGetHeight(frame)),
                                 @"touchesEnabled": @NO}];
    return self;
}

- (NSArray<CLWorldEntitySnapshot *> *)snapshots {
    return _snapshots;
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) return;
    _enabled = enabled;
    [self setNeedsDisplay];
}

- (void)updateWithSnapshots:(NSArray<CLWorldEntitySnapshot *> *)snapshots {
    NSMutableArray *valid = [NSMutableArray array];
    NSUInteger rejected = 0;
    for (id snapshot in snapshots) {
        if ([snapshot isKindOfClass:CLWorldEntitySnapshot.class] && [snapshot isValid]) {
            [valid addObject:snapshot];
        } else {
            rejected++;
        }
    }
    _snapshots = [valid copy];
    _rejectedSnapshotCount = rejected;
    [CLDiagnostics recordEvent:@"CL_ESP" stage:@"snapshot.received"
                       message:@"Snapshot batch validated"
                        fields:@{@"candidates": @(snapshots.count), @"valid": @(valid.count),
                                 @"rejected": @(rejected)}];
    [self setNeedsDisplay];
}

- (void)clearSnapshots {
    _snapshots = @[];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    static NSUInteger frameCount = 0;
    frameCount++;
    NSUInteger projectionRejected = 0;
    NSUInteger boxesDrawn = 0;
    NSUInteger fixtureRejected = 0;
    if (!self.isEnabled || _snapshots.count == 0) {
        [CLDiagnostics recordESPFrame:@{@"frameCount": @(frameCount),
            @"candidateEntities": @(_snapshots.count), @"boxesDrawn": @0,
            @"rejectedAtSnapshotUpdate": @(_rejectedSnapshotCount),
            @"enabled": @(self.isEnabled), @"emptySnapshot": @(_snapshots.count == 0)}];
        return;
    }
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        [CLDiagnostics recordEvent:@"CL_ERROR" stage:@"overlay.context.missing"
                           message:@"No current graphics context"
                            fields:@{@"frame": @(frameCount)}];
        return;
    }
    CGRect viewport = self.bounds;
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.whiteColor
    };

    for (CLWorldEntitySnapshot *snapshot in _snapshots) {
        NSString *source = snapshot.source.lowercaseString;
        if ([source containsString:@"synthetic"] || [source containsString:@"fixture"] ||
            [source containsString:@"test"]) {
            fixtureRejected++;
            continue;
        }
        CGRect box;
        if (![CLCameraProvider projectBoundsAtPosition:snapshot.position
                                               bounds:snapshot.bounds
                                              viewport:viewport
                                             resultRect:&box]) {
            projectionRejected++;
            continue;
        }
        NSString *classification =
            [CLEntityTypeRegistry classificationForIdentifier:snapshot.typeIdentifier];
        UIColor *color = [classification isEqualToString:@"player"]
            ? [UIColor colorWithRed:0.35 green:0.69 blue:1 alpha:0.96]
            : ([classification isEqualToString:@"mob"]
                ? [UIColor colorWithRed:0.39 green:0.85 blue:0.55 alpha:0.96]
                : [UIColor colorWithWhite:0.9 alpha:0.96]);
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, 2);
        CGContextStrokeRect(context, box);
        boxesDrawn++;
        NSString *label = [NSString stringWithFormat:@"%@  %@", snapshot.typeIdentifier,
            snapshot.entityId];
        CGRect labelRect = CGRectMake(box.origin.x, MAX(0, box.origin.y - 16),
                                      MIN(CGRectGetWidth(box) + 160,
                                          CGRectGetMaxX(viewport) - box.origin.x), 14);
        [label drawInRect:labelRect withAttributes:attributes];
    }
    NSDictionary *metrics = @{
        @"frameCount": @(frameCount),
        @"candidateEntities": @(_snapshots.count),
        @"validSnapshots": @(_snapshots.count),
        @"rejectedAtSnapshotUpdate": @(_rejectedSnapshotCount),
        @"fixtureOrTestSourceRejected": @(fixtureRejected),
        @"projectionRejected": @(projectionRejected),
        @"boxesDrawn": @(boxesDrawn),
        @"viewportWidth": @(CGRectGetWidth(viewport)),
        @"viewportHeight": @(CGRectGetHeight(viewport)),
        @"scale": @(self.window.screen.scale)
    };
    [CLDiagnostics recordESPFrame:metrics];
    if (frameCount == 1 || frameCount % 300 == 0 || projectionRejected > 0 || fixtureRejected > 0) {
        [CLDiagnostics recordEvent:@"CL_ESP" stage:@"overlay.frame"
                           message:@"Live overlay frame summary"
                            fields:metrics];
    }
}

@end
