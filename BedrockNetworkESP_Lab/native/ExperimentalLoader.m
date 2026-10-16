#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "CameraDataSource.h"
#import "Diagnostics.h"
#import "ESPOverlay.h"
#import "EntitySnapshotProvider.h"
#import "../src/common/BNEClock.h"

@interface BNEExperimentalLoader : NSObject
@property(nonatomic, strong) BNEESPOverlay *overlay;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, weak) UIWindow *attachedWindow;
+ (instancetype)sharedLoader;
- (void)start;
@end

@implementation BNEExperimentalLoader

+ (instancetype)sharedLoader {
    static BNEExperimentalLoader *loader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ loader = [BNEExperimentalLoader new]; });
    return loader;
}

- (void)start {
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(applicationBecameActive:)
                          name:UIApplicationDidBecomeActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(applicationEnteredBackground:)
                          name:UIApplicationDidEnterBackgroundNotification object:nil];
    [self attachToActiveWindow];
}

- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        UIWindow *fallback = nil;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isHidden) continue;
            if (window.isKeyWindow) return window;
            if (!fallback) fallback = window;
        }
        if (fallback) return fallback;
    }
    return UIApplication.sharedApplication.keyWindow;
}

- (void)attachToActiveWindow {
    UIWindow *window = [self activeWindow];
    if (!window) {
        BNELogDiagnostic(@"No active game window; overlay remains detached.");
        return;
    }
    if (!self.overlay) {
        self.overlay = [[BNEESPOverlay alloc] initWithFrame:window.bounds];
        self.overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
    }
    if (self.overlay.superview != window) {
        [self.overlay removeFromSuperview];
        self.overlay.frame = window.bounds;
        [window addSubview:self.overlay];
    }
    self.attachedWindow = window;
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                       selector:@selector(refreshOverlay:)];
        self.displayLink.preferredFramesPerSecond = 15;
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop
                               forMode:NSRunLoopCommonModes];
    }
    BNELogDiagnostic(@"Touch-through overlay attached; entity and camera sources remain unverified.");
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    [self attachToActiveWindow];
    self.displayLink.paused = NO;
}

- (void)applicationEnteredBackground:(NSNotification *)notification {
    (void)notification;
    self.displayLink.paused = YES;
}

- (void)refreshOverlay:(CADisplayLink *)displayLink {
    (void)displayLink;
    if (!self.attachedWindow || self.overlay.superview != self.attachedWindow) {
        [self attachToActiveWindow];
    }
    self.displayLink.paused = NO;
    BNESnapshot snapshot;
    BNECameraSnapshot camera;
    uint64_t now = bne_monotonic_time_ms();
    BOOL hasSnapshot = bne_entity_snapshot_provider_copy(now, 1000, &snapshot);
    BOOL hasCamera = bne_camera_data_source_copy(&camera);
    [self.overlay updateWithSnapshot:hasSnapshot ? &snapshot : NULL
                              camera:hasCamera ? &camera : NULL];
}

@end

__attribute__((constructor))
static void BNEExperimentalLoaderConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BNELogDiagnostic(@"Experimental dylib loaded; no network decoder or game hook is active.");
        [[BNEExperimentalLoader sharedLoader] start];
    });
}