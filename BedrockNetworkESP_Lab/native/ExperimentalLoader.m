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
@property(nonatomic) NSUInteger windowLookupAttempts;
@property(nonatomic) BOOL started;
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
    if (self.started) return;
    self.started = YES;
    BNELogEvent(@"BNE_INIT", @"startup.begin", @"Experimental loader initialization started", nil);
    BNEUpdateDiagnosticStatus(@"runtime", @"state", @"initializing", @"Dylib constructor dispatched to the main queue.");
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(applicationBecameActive:)
                          name:UIApplicationDidBecomeActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(applicationEnteredBackground:)
                          name:UIApplicationDidEnterBackgroundNotification object:nil];
    [notifications addObserver:self selector:@selector(applicationWillTerminate:)
                          name:UIApplicationWillTerminateNotification object:nil];
    BNELogEvent(@"BNE_INIT", @"notifications.registered", @"Application lifecycle observers installed", nil);
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
        self.windowLookupAttempts++;
        BNEUpdateDiagnosticStatus(@"ui", @"window", @"unavailable",
            @"No foreground UIWindowScene window was found; retry is scheduled.");
        if (self.windowLookupAttempts == 1 || self.windowLookupAttempts % 10 == 0 ||
            self.windowLookupAttempts >= 120) {
            BNELogEvent(@"BNE_ERROR", @"ui.window.lookup", @"No active game window; delaying overlay attach",
                @{@"attempt": @(self.windowLookupAttempts), @"limit": @120});
        }
        if (self.windowLookupAttempts < 120) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self attachToActiveWindow]; });
        } else {
            BNEUpdateDiagnosticStatus(@"ui", @"state", @"failed", @"Window lookup retry limit reached.");
            BNEFlushDiagnosticReports(@"window-lookup-failed");
        }
        return;
    }
    self.windowLookupAttempts = 0;
    if (!self.overlay) {
        self.overlay = [[BNEESPOverlay alloc] initWithFrame:window.bounds];
        self.overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        BNELogEvent(@"BNE_ESP", @"overlay.created", @"Touch-through overlay view created",
            @{@"width": @(CGRectGetWidth(window.bounds)), @"height": @(CGRectGetHeight(window.bounds)),
              @"scale": @(window.screen.scale), @"userInteractionEnabled": @NO});
    }
    if (self.overlay.superview != window) {
        [self.overlay removeFromSuperview];
        self.overlay.frame = window.bounds;
        [window addSubview:self.overlay];
        BNELogEvent(@"BNE_ESP", @"overlay.attached", @"Overlay attached to active window", nil);
    }
    self.attachedWindow = window;
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                       selector:@selector(refreshOverlay:)];
        self.displayLink.preferredFramesPerSecond = 15;
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop
                               forMode:NSRunLoopCommonModes];
        BNELogEvent(@"BNE_ESP", @"display-link.started", @"Overlay refresh callback started",
            @{@"preferredFramesPerSecond": @15});
    }
    BNEUpdateDiagnosticStatus(@"ui", @"state", @"attached", @"Overlay is non-interactive and attached to active window.");
    BNEUpdateDiagnosticStatus(@"runtime", @"state", @"initialized", @"Loader and diagnostic overlay initialized; live providers are still unverified.");
    BNEFlushDiagnosticReports(@"startup-complete");
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    BNELogEvent(@"BNE_RUNTIME", @"application.active", @"Application became active", nil);
    [self attachToActiveWindow];
    self.displayLink.paused = NO;
}

- (void)applicationEnteredBackground:(NSNotification *)notification {
    (void)notification;
    self.displayLink.paused = YES;
    BNELogEvent(@"BNE_RUNTIME", @"application.background", @"Application entered background; display link paused", nil);
    BNEFlushDiagnosticReports(@"application-background");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    self.displayLink.paused = YES;
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self.overlay removeFromSuperview];
    self.overlay = nil;
    BNELogEvent(@"BNE_RUNTIME", @"shutdown", @"Application termination cleanup completed", nil);
    BNEFlushDiagnosticReports(@"application-termination");
}

- (void)refreshOverlay:(CADisplayLink *)displayLink {
    (void)displayLink;
    if (!self.attachedWindow || self.overlay.superview != self.attachedWindow) {
        [self attachToActiveWindow];
    }
    if (!self.overlay) return;
    BNESnapshot snapshot;
    BNECameraSnapshot camera;
    uint64_t now = bne_monotonic_time_ms();
    BOOL hasSnapshot = bne_entity_snapshot_provider_copy(now, 1000, &snapshot);
    BOOL hasCamera = bne_camera_data_source_copy(&camera);
    if (now == 0) {
        BNELogEvent(@"BNE_ERROR", @"clock.read", @"Monotonic clock unavailable; snapshot freshness cannot be checked", nil);
    }
    [self.overlay updateWithSnapshot:hasSnapshot ? &snapshot : NULL
                              camera:hasCamera ? &camera : NULL];
}

@end

__attribute__((constructor))
static void BNEExperimentalLoaderConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BNEInitializeDiagnostics();
        BNELogEvent(@"BNE_INIT", @"constructor", @"Experimental dylib constructor executed",
            @{@"sessionID": BNECurrentSessionID()});
        BNEFlushDiagnosticReports(@"constructor");
        [[BNEExperimentalLoader sharedLoader] start];
    });
}