#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/dyld.h>
#import "providers/CLCameraProvider.h"
#import "providers/CLDiagnostics.h"
#import "providers/CLEntityProvider.h"
#import "providers/CLEntityTypeRegistry.h"
#import "providers/CLESPOverlay.h"
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

// Live rendering consumes validated snapshots and camera state; the target engine adapter is not yet verified.

@class ClientMenuPanel;

@protocol ClientMenuAPI <JSExport>
JSExportAs(registerAction,
- (void)registerAction:(NSString *)title callback:(JSValue *)callback
);
JSExportAs(registerFeature,
- (void)registerFeature:(NSString *)title enabled:(BOOL)enabled callback:(JSValue *)callback
);
JSExportAs(isFeatureEnabled,
- (BOOL)isFeatureEnabled:(NSString *)title
);
- (void)notify:(NSString *)message;
JSExportAs(exportJSON,
- (NSString *)exportJSON:(NSString *)json fileName:(NSString *)fileName
);
JSExportAs(setSyntheticESPEnabled,
- (void)setSyntheticESPEnabled:(BOOL)enabled
);
JSExportAs(setLiveESPEnabled,
- (void)setLiveESPEnabled:(BOOL)enabled
);
JSExportAs(exportDiagnostics,
- (NSString *)exportDiagnostics:(NSString *)fileName
);
@end

@interface ClientMenuBridge : NSObject <ClientMenuAPI>
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *actions;
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *features;
@property(nonatomic, weak) JSContext *context;
@property(nonatomic, weak) UIWindow *window;
- (void)setFeature:(NSString *)title enabled:(BOOL)enabled;
@end

@interface ClientLoaderTarget : NSObject
- (void)runCustomAction:(UIButton *)sender;
- (void)updateLiveESP:(CADisplayLink *)displayLink;
@end

@interface ClientDraggableButton : UIButton
@property(nonatomic) CGPoint touchStart;
@property(nonatomic) CGPoint initialCenter;
@property(nonatomic) BOOL didMove;
@end

@interface ClientMenuPanel : UIView
- (instancetype)initWithWindow:(UIWindow *)window bridge:(ClientMenuBridge *)bridge;
- (void)reloadContent;
@end

@interface ClientESPSyntheticOverlay : UIView
@end

static NSString *const kClientLoaderHapticsKey = @"ClientLoader.haptics";
static NSString *const kClientLoaderButtonsVisibleKey = @"ClientLoader.customButtonsVisible";
static NSString *const kClientLoaderButtonTitlesKey = @"ClientLoader.customButtonTitles";
static NSString *const kClientLoaderButtonXKey = @"ClientLoader.buttonCenterX";
static NSString *const kClientLoaderButtonYKey = @"ClientLoader.buttonCenterY";
static NSString *const kClientLoaderFeaturePrefix = @"ClientLoader.feature.";
static NSString *const kClientLoaderDiagnosticSessionKey = @"ClientLoader.diagnostics.sessionID";
static NSString *const kClientLoaderDiagnosticStartKey = @"ClientLoader.diagnostics.startedAt";
static NSString *const kClientLoaderAccent = @"#A879FF";

static ClientMenuBridge *sBridge;
static JSContext *sContext;
static UIButton *sMenuButton;
static UIStackView *sCustomButtonStack;
static ClientLoaderTarget *sTarget;
static ClientMenuPanel *sMenuPanel;
static ClientESPSyntheticOverlay *sESPSyntheticOverlay;
static BOOL sESPSyntheticOverlayEnabled;
static CLESPOverlay *sLiveESPLayer;
static CADisplayLink *sLiveESPDisplayLink;
static BOOL sLiveESPEnabled;
static BOOL sScriptsLoaded;
static NSUInteger sWindowLookupAttempts;
static NSObject *sLogLock;
static NSUncaughtExceptionHandler *sPreviousUncaughtExceptionHandler;
static NSString *sClientLoaderSessionID;
static NSUInteger sScriptEvaluationCount;
static NSUInteger sScriptEvaluationFailureCount;

#ifndef CL_BUILD_REVISION
#define CL_BUILD_REVISION "unknown"
#endif
#ifndef CL_BUILD_TIMESTAMP
#define CL_BUILD_TIMESTAMP "unknown"
#endif
#ifndef CL_EXPECTED_ESP_TEST_JS_SHA256
#define CL_EXPECTED_ESP_TEST_JS_SHA256 "unknown"
#endif

static void ClientMenuOpen(void);
static void ClientMenuRefresh(void);
static void ClientLoaderRenderCustomButtons(void);
static void ClientLoaderSaveMenuButtonPosition(void);
static void ClientLoaderClampButton(UIButton *button, UIWindow *window);
static void ClientLoaderSetESPSyntheticOverlayEnabled(BOOL enabled);
static void ClientLoaderSetLiveESPEnabled(BOOL enabled);

static void ClientLoaderRotateLogIfNeeded(NSURL *logURL) {
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:logURL.path error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue] < 512 * 1024) return;
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager removeItemAtURL:[logURL URLByAppendingPathExtension:@"3"] error:nil];
    for (NSInteger index = 2; index >= 1; index--) {
        NSURL *source = [logURL URLByAppendingPathExtension:[NSString stringWithFormat:@"%ld", (long)index]];
        NSURL *destination = [logURL URLByAppendingPathExtension:[NSString stringWithFormat:@"%ld", (long)index + 1]];
        if ([manager fileExistsAtPath:source.path]) [manager moveItemAtURL:source toURL:destination error:nil];
    }
    if ([manager fileExistsAtPath:logURL.path]) {
        [manager moveItemAtURL:logURL toURL:[logURL URLByAppendingPathExtension:@"1"] error:nil];
    }
}

static void ClientLoaderLog(NSString *message) {
    NSString *safeMessage = message ?: @"(empty diagnostic message)";
    NSString *structuredMessage = [safeMessage hasPrefix:@"[CL_"]
        ? safeMessage
        : [NSString stringWithFormat:@"[CL_RUNTIME] session=%@ stage=legacy %@",
            sClientLoaderSessionID ?: @"startup", safeMessage];
    NSLog(@"[ClientLoader] %@", structuredMessage);
    BOOL important = [safeMessage containsString:@"ERROR:"] ||
        [safeMessage containsString:@"FATAL:"] || [safeMessage containsString:@"[CL_ERROR]"];
    if (important) {
        [CLDiagnostics recordError:structuredMessage];
    }

    @synchronized (sLogLock) {
        NSURL *documentsURL = [[[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory
                   inDomains:NSUserDomainMask] firstObject];
        if (!documentsURL) {
            NSLog(@"[ClientLoader] Could not locate Documents directory for log file");
            return;
        }

        NSURL *directoryURL = [documentsURL URLByAppendingPathComponent:@"ClientLoader"
                                                            isDirectory:YES];
        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&directoryError]) {
            NSLog(@"[ClientLoader] Could not create log directory: %@", directoryError);
            return;
        }

        NSURL *logURL = [directoryURL URLByAppendingPathComponent:@"ClientLoader.log"];
        ClientLoaderRotateLogIfNeeded(logURL);
        int descriptor = open(logURL.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (descriptor < 0) {
            NSLog(@"[ClientLoader] Could not open log file: %s", strerror(errno));
            return;
        }

        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                          [formatter stringFromDate:[NSDate date]], structuredMessage];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *bytes = data.bytes;
        size_t remaining = data.length;
        while (remaining > 0) {
            ssize_t written = write(descriptor, bytes, remaining);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) {
                int writeError = errno;
                close(descriptor);
                NSLog(@"[ClientLoader] Could not write log file: %s", strerror(writeError));
                return;
            }
            bytes += written;
            remaining -= (size_t)written;
        }
        if (important) fsync(descriptor);
        close(descriptor);
    }
}

static void ClientLoaderLogStage(NSString *category, NSString *stage, NSString *message) {
    NSString *event = [NSString stringWithFormat:@"[%@] session=%@ stage=%@ %@",
        category ?: @"CL_RUNTIME", sClientLoaderSessionID ?: @"startup",
        stage ?: @"unspecified", message ?: @""];
    [CLDiagnostics recordEvent:category ?: @"CL_RUNTIME"
                         stage:stage ?: @"unspecified"
                       message:message ?: @""
                        fields:nil];
    ClientLoaderLog(event);
}

static void ClientLoaderLogLoadedImageState(NSString *stage) {
    BOOL clientLoaderPresent = NO;
    BOOL experimentalPresent = NO;
    BOOL javaScriptCorePresent = NO;
    NSMutableArray<NSString *> *relatedImages = [NSMutableArray array];
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) continue;
        NSString *baseName = [[NSString stringWithUTF8String:imageName] lastPathComponent];
        NSString *lower = baseName.lowercaseString;
        if ([lower containsString:@"clientloader"]) {
            clientLoaderPresent = YES;
            [relatedImages addObject:baseName];
        } else if ([lower containsString:@"bedrocknetworkesp_lab"]) {
            experimentalPresent = YES;
            [relatedImages addObject:baseName];
        } else if ([lower containsString:@"javascriptcore"]) {
            javaScriptCorePresent = YES;
            [relatedImages addObject:baseName];
        }
    }
    ClientLoaderLogStage(experimentalPresent ? @"CL_RUNTIME" : @"CL_ERROR", stage,
        [NSString stringWithFormat:@"loadedImages=%@ clientLoader=%d experimentalLab=%d JavaScriptCore=%d",
            relatedImages, clientLoaderPresent, experimentalPresent, javaScriptCorePresent]);
}

static void ClientLoaderWriteDiagnosticReport(NSString *fileName, NSString *stage) {
    NSError *error = nil;
    NSString *path = [CLDiagnostics writeRuntimeReportToDocumentsFile:fileName error:&error];
    if (!path) {
        ClientLoaderLogStage(@"CL_ERROR", stage,
            [NSString stringWithFormat:@"Report %@ write failed: %@", fileName,
                error.localizedDescription ?: @"unknown error"]);
        return;
    }
    ClientLoaderLogStage(@"CL_EXPORT", stage,
        [NSString stringWithFormat:@"Report %@ written and size-verified at %@", fileName, path]);
}

static NSString *ClientLoaderSHA256(NSData *data) {
    if (!data) return @"unavailable";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

static BOOL ClientLoaderInvokeJSCallback(JSValue *callback,
                                         NSArray *arguments,
                                         NSString *stage) {
    if (!callback || callback.isUndefined || callback.isNull || !callback.isObject) {
        ClientLoaderLogStage(@"CL_BRIDGE", @"callback.rejected",
            [NSString stringWithFormat:@"%@ callback missing or is not an object", stage]);
        return NO;
    }
    CFTimeInterval started = CACurrentMediaTime();
    ClientLoaderLogStage(@"CL_BRIDGE", @"callback.begin", stage);
    @try {
        sContext.exception = nil;
        [callback callWithArguments:arguments ?: @[]];
        JSValue *exception = sContext.exception;
        if (exception && !exception.isUndefined && !exception.isNull) {
            NSString *stack = exception[@"stack"].toString ?: @"";
            ClientLoaderLogStage(@"CL_ERROR", @"callback.exception",
                [NSString stringWithFormat:@"%@ error=%@ stack=%@", stage,
                    exception.toString ?: @"unknown JavaScript exception", stack]);
            sContext.exception = nil;
            return NO;
        }
        ClientLoaderLogStage(@"CL_BRIDGE", @"callback.end",
            [NSString stringWithFormat:@"%@ durationMs=%.3f status=success", stage,
                (CACurrentMediaTime() - started) * 1000.0]);
        return YES;
    } @catch (NSException *exception) {
        ClientLoaderLogStage(@"CL_ERROR", @"callback.native-exception",
            [NSString stringWithFormat:@"%@ exception=%@ reason=%@", stage,
                exception.name, exception.reason ?: @"unknown"]);
        return NO;
    }
}

static void ClientLoaderInstallConsoleBridge(void) {
    JSValue *existingConsole = sContext[@"console"];
    if (existingConsole && !existingConsole.isUndefined && !existingConsole.isNull) {
        ClientLoaderLogStage(@"CL_BRIDGE", @"js.console.existing", @"A console object already exists");
        return;
    }
    sContext[@"__clientLoaderConsoleLog"] = ^(NSString *level, NSString *message) {
        NSString *bounded = message ?: @"";
        if (bounded.length > 1024) {
            bounded = [[bounded substringToIndex:1024] stringByAppendingString:@"...[truncated]"];
        }
        NSString *category = [level.lowercaseString isEqualToString:@"error"]
            ? @"CL_ERROR" : @"CL_BRIDGE";
        ClientLoaderLogStage(category,
            [NSString stringWithFormat:@"js.console.%@", level ?: @"log"], bounded);
    };
    NSString *source = @"({log:function(){__clientLoaderConsoleLog('info',Array.prototype.map.call(arguments,function(v){try{return typeof v==='string'?v:JSON.stringify(v)}catch(e){return String(v)}}).join(' '))},warn:function(){__clientLoaderConsoleLog('warn',Array.prototype.map.call(arguments,function(v){try{return typeof v==='string'?v:JSON.stringify(v)}catch(e){return String(v)}}).join(' '))},error:function(){__clientLoaderConsoleLog('error',Array.prototype.map.call(arguments,function(v){try{return typeof v==='string'?v:JSON.stringify(v)}catch(e){return String(v)}}).join(' '))}})";
    sContext[@"console"] = [sContext evaluateScript:source];
    JSValue *consoleValue = sContext[@"console"];
    BOOL installed = consoleValue && consoleValue.isObject &&
        consoleValue[@"log"].isObject && consoleValue[@"warn"].isObject &&
        consoleValue[@"error"].isObject;
    ClientLoaderLogStage(installed ? @"CL_BRIDGE" : @"CL_ERROR",
        @"js.console.install", [NSString stringWithFormat:@"console log/warn/error available=%d", installed]);
}

static void ClientLoaderHandleUncaughtException(NSException *exception) {
    NSString *stack = [exception.callStackSymbols componentsJoinedByString:@"\n"];
    NSString *message = [NSString stringWithFormat:
        @"FATAL: uncaught Objective-C exception %@: %@\nCall stack:\n%@",
        exception.name, exception.reason ?: @"(no reason)", stack];
    ClientLoaderLogStage(@"CL_ERROR", @"objc.uncaught-exception", message);
    if (sPreviousUncaughtExceptionHandler &&
        sPreviousUncaughtExceptionHandler != ClientLoaderHandleUncaughtException) {
        sPreviousUncaughtExceptionHandler(exception);
    }
}

static BOOL ClientLoaderHapticsEnabled(void) {
    id savedValue = [NSUserDefaults.standardUserDefaults objectForKey:kClientLoaderHapticsKey];
    return savedValue ? [savedValue boolValue] : YES;
}

static UIColor *ClientColor(NSString *hex, CGFloat alpha) {
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:
        [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString]];
    [scanner scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

@implementation ClientMenuBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _actions = [NSMutableArray array];
        _features = [NSMutableArray array];
    }
    return self;
}

- (void)registerAction:(NSString *)title callback:(JSValue *)callback {
    ClientLoaderLogStage(@"CL_BRIDGE", @"registerAction.begin",
        [NSString stringWithFormat:@"title=%@ callbackObject=%@",
            [title isKindOfClass:NSString.class] ? [title substringToIndex:MIN(title.length, 120)] : @"invalid",
            @([callback isKindOfClass:JSValue.class] && callback.isObject)]);
    if (title.length == 0 || !callback || !callback.isObject) {
        ClientLoaderLogStage(@"CL_ERROR", @"registerAction.rejected", @"Invalid title or callback");
        return;
    }
    NSIndexSet *existing = [self.actions indexesOfObjectsPassingTest:^BOOL(
        NSDictionary *item, __unused NSUInteger idx, __unused BOOL *stop) {
        return [item[@"title"] isEqualToString:title];
    }];
    if (existing.count) [self.actions removeObjectsAtIndexes:existing];
    [self.actions addObject:@{@"title": title, @"callback": callback}];
    ClientLoaderLogStage(@"CL_BRIDGE", @"registerAction.success",
        [NSString stringWithFormat:@"actionCount=%lu", (unsigned long)self.actions.count]);
    ClientMenuRefresh();
}

- (void)registerFeature:(NSString *)title enabled:(BOOL)enabled callback:(JSValue *)callback {
    ClientLoaderLogStage(@"CL_BRIDGE", @"registerFeature.begin",
        [NSString stringWithFormat:@"title=%@ requestedDefault=%d callbackObject=%@",
            [title isKindOfClass:NSString.class] ? [title substringToIndex:MIN(title.length, 120)] : @"invalid",
            enabled, @([callback isKindOfClass:JSValue.class] && callback.isObject)]);
    if (title.length == 0 || !callback || !callback.isObject) {
        ClientLoaderLogStage(@"CL_ERROR", @"registerFeature.rejected", @"Invalid title or callback");
        return;
    }
    NSIndexSet *existing = [self.features indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, __unused NSUInteger idx, __unused BOOL *stop) {
        return [item[@"title"] isEqualToString:title];
    }];
    if (existing.count) [self.features removeObjectsAtIndexes:existing];

    NSString *key = [kClientLoaderFeaturePrefix stringByAppendingString:title];
    id savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    BOOL currentValue = savedValue ? [savedValue boolValue] : enabled;
    NSMutableDictionary *record = [@{
        @"title": title,
        @"enabled": @(currentValue),
        @"callback": callback
    } mutableCopy];
    [self.features addObject:record];
    [callback callWithArguments:@[@(currentValue)]];
    NSMutableDictionary *record = [@{
        @"title": title,
        @"enabled": @(currentValue),
        @"callback": callback
    } mutableCopy];
    [self.features addObject:record];
    ClientLoaderLogStage(@"CL_BRIDGE", @"registerFeature.success",
        [NSString stringWithFormat:@"featureCount=%lu restoredValue=%d",
            (unsigned long)self.features.count, currentValue]);
    ClientLoaderInvokeJSCallback(callback, @[@(currentValue)],
        [NSString stringWithFormat:@"registerFeature.initial title=%@", [title substringToIndex:MIN(title.length, 120)]]);
    ClientMenuRefresh();
}

- (BOOL)isFeatureEnabled:(NSString *)title {
    for (NSDictionary *feature in self.features) {
        if ([feature[@"title"] isEqualToString:title]) {
            return [feature[@"enabled"] boolValue];
        }
    }
    return NO;
}

- (void)setFeature:(NSString *)title enabled:(BOOL)enabled {
    ClientLoaderLogStage(@"CL_BRIDGE", @"feature.toggle.request",
        [NSString stringWithFormat:@"title=%@ enabled=%d",
            [title isKindOfClass:NSString.class] ? [title substringToIndex:MIN(title.length, 120)] : @"invalid",
            enabled]);
    for (NSMutableDictionary *feature in self.features) {
        if (![feature[@"title"] isEqualToString:title]) continue;
        feature[@"enabled"] = @(enabled);
        NSString *key = [kClientLoaderFeaturePrefix stringByAppendingString:title];
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:key];
        JSValue *callback = feature[@"callback"];
        BOOL callbackSucceeded = ClientLoaderInvokeJSCallback(callback, @[@(enabled)],
            [NSString stringWithFormat:@"feature.toggle title=%@ enabled=%d",
                [title substringToIndex:MIN(title.length, 120)], enabled]);
        ClientLoaderLogStage(@"CL_BRIDGE", @"feature.toggle.complete",
            [NSString stringWithFormat:@"callbackSucceeded=%d", callbackSucceeded]);
        return;
    }
    ClientLoaderLogStage(@"CL_ERROR", @"feature.toggle.missing",
        [NSString stringWithFormat:@"No registered feature title=%@", [title substringToIndex:MIN(title.length, 120)]]);
}

- (void)notify:(NSString *)message {
    if (message.length == 0) return;
    ClientLoaderLogStage(@"CL_BRIDGE", @"notify.request",
        [NSString stringWithFormat:@"messageLength=%lu", (unsigned long)message.length]);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Client Loader"
                             message:message
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        UIViewController *presenter = self.window.rootViewController;
        while (presenter.presentedViewController) {
            presenter = presenter.presentedViewController;
        }
        if (presenter) {
            [presenter presentViewController:alert animated:YES completion:nil];
            ClientLoaderLogStage(@"CL_BRIDGE", @"notify.presented", @"Alert controller presented");
        } else {
            ClientLoaderLogStage(@"CL_ERROR", @"notify.failed", @"No root view controller was available");
        }
    });
}

- (NSString *)exportJSON:(NSString *)json fileName:(NSString *)fileName {
    ClientLoaderLogStage(@"CL_EXPORT", @"exportJSON.begin",
        [NSString stringWithFormat:@"jsonType=%@ filename=%@",
            [json isKindOfClass:NSString.class] ? @"string" : @"invalid",
            [fileName isKindOfClass:NSString.class] ? [fileName substringToIndex:MIN(fileName.length, 80)] : @"invalid"]);
    if (![json isKindOfClass:NSString.class] ||
        ![fileName isKindOfClass:NSString.class] ||
        json.length == 0 || fileName.length == 0) {
        ClientLoaderLog(@"ERROR: rejected diagnostic export with missing input");
        return nil;
    }
    NSRegularExpression *fileNamePattern = [NSRegularExpression
        regularExpressionWithPattern:@"^[A-Za-z0-9_-]{1,64}\\.json$"
                             options:0
                               error:nil];
    NSTextCheckingResult *match = [fileNamePattern firstMatchInString:fileName
                                                              options:0
                                                                range:NSMakeRange(0, fileName.length)];
    if (!match || match.range.length != fileName.length) {
        ClientLoaderLog(@"ERROR: rejected diagnostic export with an invalid file name");
        return nil;
    }

    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0 || data.length > 1024 * 1024) {
        ClientLoaderLog(@"ERROR: rejected diagnostic export with an invalid size");
        return nil;
    }
    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!object || jsonError) {
        ClientLoaderLog([NSString stringWithFormat:
            @"ERROR: rejected invalid diagnostic JSON: %@", jsonError]);
        return nil;
    }
    id schemaValue = [object isKindOfClass:NSDictionary.class] ? object[@"schemaVersion"] : nil;
    NSString *schemaVersion = [schemaValue isKindOfClass:NSNumber.class]
        ? [schemaValue stringValue] : @"unknown";

    NSURL *documentsURL = [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory
               inDomains:NSUserDomainMask] firstObject];
    if (!documentsURL) {
        ClientLoaderLog(@"ERROR: could not locate Documents directory for diagnostic export");
        return nil;
    }
    NSURL *directoryURL = [[documentsURL URLByAppendingPathComponent:@"ClientLoader"
                                                        isDirectory:YES]
        URLByAppendingPathComponent:@"exports" isDirectory:YES];
    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&directoryError]) {
        ClientLoaderLog([NSString stringWithFormat:
            @"ERROR: could not create diagnostic export directory: %@", directoryError]);
        return nil;
    }

    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
    NSError *writeError = nil;
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&writeError]) {
        ClientLoaderLog([NSString stringWithFormat:
            @"ERROR: could not write diagnostic export: %@", writeError]);
        return nil;
    }
    ClientLoaderLog([NSString stringWithFormat:
        @"Exported caller-supplied JSON via ClientMenu.exportJSON (schemaVersion=%@, %lu bytes) to %@",
        schemaVersion, (unsigned long)data.length, fileURL.path]);
    return fileURL.path;
}

- (void)setSyntheticESPEnabled:(BOOL)enabled {
    ClientLoaderLogStage(@"CL_ESP", @"synthetic.toggle.request",
        [NSString stringWithFormat:@"enabled=%d", enabled]);
    dispatch_async(dispatch_get_main_queue(), ^{
        ClientLoaderSetESPSyntheticOverlayEnabled(enabled);
    });
}

- (void)setLiveESPEnabled:(BOOL)enabled {
    ClientLoaderLogStage(@"CL_ESP", @"live.toggle.request",
        [NSString stringWithFormat:@"enabled=%d", enabled]);
    dispatch_async(dispatch_get_main_queue(), ^{
        ClientLoaderSetLiveESPEnabled(enabled);
    });
}

- (NSString *)exportDiagnostics:(NSString *)fileName {
    ClientLoaderLogStage(@"CL_EXPORT", @"exportDiagnostics.begin",
        [NSString stringWithFormat:@"filename=%@",
            [fileName isKindOfClass:NSString.class] ? [fileName substringToIndex:MIN(fileName.length, 80)] : @"invalid"]);
    NSError *error = nil;
    NSString *path = [CLDiagnostics writeRuntimeReportToDocumentsFile:fileName error:&error];
    if (!path) {
        ClientLoaderLog([NSString stringWithFormat:
            @"ERROR: live ESP diagnostic export failed: %@", error]);
        return nil;
    }
    ClientLoaderLog([NSString stringWithFormat:
        @"Exported native CLDiagnostics runtime report (schemaVersion=2) to %@", path]);
    return path;
}

@end

@implementation ClientMenuPanel {
    __weak UIWindow *_hostWindow;
    __weak ClientMenuBridge *_bridge;
    UIView *_card;
    UISegmentedControl *_tabs;
    UIStackView *_rows;
}

- (instancetype)initWithWindow:(UIWindow *)window bridge:(ClientMenuBridge *)bridge {
    self = [super initWithFrame:window.bounds];
    if (!self) return nil;
    _hostWindow = window;
    _bridge = bridge;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.58];

    UIControl *dismissBackdrop = [[UIControl alloc] initWithFrame:self.bounds];
    dismissBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [dismissBackdrop addTarget:self action:@selector(closePanel)
              forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:dismissBackdrop];

    _card = [UIView new];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = ClientColor(@"#17151F", 0.98);
    _card.layer.cornerRadius = 22;
    _card.layer.borderWidth = 1;
    _card.layer.borderColor = ClientColor(kClientLoaderAccent, 0.52).CGColor;
    _card.layer.shadowColor = UIColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.38;
    _card.layer.shadowRadius = 22;
    _card.layer.shadowOffset = CGSizeMake(0, 10);
    [self addSubview:_card];

    UILabel *title = [UILabel new];
    title.text = @"CLIENT";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightHeavy];
    UILabel *subtitle = [UILabel new];
    subtitle.text = @"BEDROCK  •  LOCAL TOOLS";
    subtitle.textColor = ClientColor(@"#AAA5B8", 1);
    subtitle.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    subtitle.numberOfLines = 1;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightRegular];
    close.backgroundColor = ClientColor(@"#302B3B", 1);
    close.layer.cornerRadius = 17;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [close.widthAnchor constraintEqualToConstant:34],
        [close.heightAnchor constraintEqualToConstant:34]
    ]];

    UIStackView *headingText = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    headingText.axis = UILayoutConstraintAxisVertical;
    headingText.spacing = 1;
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[headingText, close]];
    heading.axis = UILayoutConstraintAxisHorizontal;
    heading.alignment = UIStackViewAlignmentCenter;
    heading.distribution = UIStackViewDistributionEqualSpacing;
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:heading];

    _tabs = [[UISegmentedControl alloc] initWithItems:@[@"Features", @"Buttons"]];
    _tabs.selectedSegmentIndex = 0;
    _tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [_tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}
                         forState:UIControlStateSelected];
    [_tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: ClientColor(@"#C7C2D2", 1)}
                         forState:UIControlStateNormal];
    _tabs.selectedSegmentTintColor = ClientColor(kClientLoaderAccent, 1);
    _tabs.backgroundColor = ClientColor(@"#292532", 1);
    [_tabs addTarget:self action:@selector(tabChanged)
    forControlEvents:UIControlEventValueChanged];
    [_card addSubview:_tabs];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [_card addSubview:scroll];
    _rows = [UIStackView new];
    _rows.axis = UILayoutConstraintAxisVertical;
    _rows.spacing = 10;
    _rows.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_rows];

    UILabel *footer = [UILabel new];
    footer.text = @"PERSONAL UI  •  NO WORLD EXPERIMENTS";
    footer.textColor = ClientColor(@"#8E899A", 1);
    footer.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:footer];

    UILayoutGuide *safe = self.safeAreaLayoutGuide;
    NSLayoutConstraint *cardWidth =
        [_card.widthAnchor constraintEqualToAnchor:safe.widthAnchor multiplier:0.91];
    cardWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_card.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        cardWidth,
        [_card.widthAnchor constraintLessThanOrEqualToConstant:460],
        [_card.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:0.78],
        [heading.topAnchor constraintEqualToAnchor:_card.topAnchor constant:18],
        [heading.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:19],
        [heading.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-17],
        [_tabs.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:14],
        [_tabs.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:18],
        [_tabs.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-18],
        [_tabs.heightAnchor constraintEqualToConstant:36],
        [scroll.topAnchor constraintEqualToAnchor:_tabs.bottomAnchor constant:13],
        [scroll.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:17],
        [scroll.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-17],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-9],
        [footer.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
        [footer.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        [footer.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-12],
        [_rows.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [_rows.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [_rows.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [_rows.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [_rows.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    [self reloadContent];
    return self;
}

- (void)closePanel {
    [UIView animateWithDuration:0.16 animations:^{ self.alpha = 0; }
                     completion:^(__unused BOOL finished) { [self removeFromSuperview]; }];
}

- (void)tabChanged {
    [self reloadContent];
}

- (UIView *)sectionLabel:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text.uppercaseString;
    label.textColor = ClientColor(kClientLoaderAccent, 1);
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    return label;
}

- (UIView *)noteLabel:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = ClientColor(@"#B8B3C2", 1);
    label.font = [UIFont systemFontOfSize:12];
    label.numberOfLines = 0;
    return label;
}

- (UIView *)rowWithTitle:(NSString *)title detail:(NSString *)detail accessory:(UIView *)accessory {
    UIView *container = [UIView new];
    container.backgroundColor = ClientColor(@"#24212E", 1);
    container.layer.cornerRadius = 13;
    container.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *name = [UILabel new];
    name.text = title;
    name.textColor = UIColor.whiteColor;
    name.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UILabel *description = [UILabel new];
    description.text = detail;
    description.textColor = ClientColor(@"#AAA5B8", 1);
    description.font = [UIFont systemFontOfSize:11];
    description.numberOfLines = 0;
    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[name, description]];
    labels.axis = UILayoutConstraintAxisVertical;
    labels.spacing = 3;
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[labels, accessory]];
    line.axis = UILayoutConstraintAxisHorizontal;
    line.alignment = UIStackViewAlignmentCenter;
    line.spacing = 8;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:line];
    [accessory setContentHuggingPriority:UILayoutPriorityRequired
                                forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [line.topAnchor constraintEqualToAnchor:container.topAnchor constant:11],
        [line.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-11],
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [container.heightAnchor constraintGreaterThanOrEqualToConstant:56]
    ]];
    return container;
}

- (UISwitch *)switchWithIdentifier:(NSString *)identifier isOn:(BOOL)isOn {
    UISwitch *toggle = [UISwitch new];
    toggle.on = isOn;
    toggle.onTintColor = ClientColor(kClientLoaderAccent, 1);
    toggle.accessibilityIdentifier = identifier;
    [toggle addTarget:self action:@selector(toggleChanged:)
     forControlEvents:UIControlEventValueChanged];
    return toggle;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *identifier = sender.accessibilityIdentifier;
    ClientLoaderLogStage(@"CL_ESP", @"ui.toggle.changed",
        [NSString stringWithFormat:@"identifier=%@ enabled=%d", identifier ?: @"unknown", sender.isOn]);
    if ([identifier isEqualToString:@"__haptics"]) {
        [defaults setBool:sender.isOn forKey:kClientLoaderHapticsKey];
    } else if ([identifier isEqualToString:@"__customButtons"]) {
        [defaults setBool:sender.isOn forKey:kClientLoaderButtonsVisibleKey];
        ClientLoaderRenderCustomButtons();
    } else {
        [_bridge setFeature:identifier enabled:sender.isOn];
    }
    if (ClientLoaderHapticsEnabled()) {
        UIImpactFeedbackGenerator *feedback =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
}

- (UIButton *)actionButton:(NSString *)title action:(SEL)selector identifier:(NSString *)identifier {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    button.backgroundColor = ClientColor(kClientLoaderAccent, 0.78);
    button.layer.cornerRadius = 9;
    button.contentEdgeInsets = UIEdgeInsetsMake(7, 11, 7, 11);
    button.accessibilityIdentifier = identifier;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)addCustomButtonTapped:(UIButton *)sender {
    NSString *title = sender.accessibilityIdentifier;
    if (title.length == 0) return;
    NSMutableArray<NSString *> *titles = [[NSUserDefaults.standardUserDefaults
        arrayForKey:kClientLoaderButtonTitlesKey] mutableCopy] ?: [NSMutableArray array];
    if (![titles containsObject:title]) [titles addObject:title];
    [NSUserDefaults.standardUserDefaults setObject:titles forKey:kClientLoaderButtonTitlesKey];
    ClientLoaderRenderCustomButtons();
    [self reloadContent];
}

- (void)removeCustomButtonTapped:(UIButton *)sender {
    NSString *title = sender.accessibilityIdentifier;
    NSMutableArray<NSString *> *titles = [[NSUserDefaults.standardUserDefaults
        arrayForKey:kClientLoaderButtonTitlesKey] mutableCopy] ?: [NSMutableArray array];
    [titles removeObject:title];
    [NSUserDefaults.standardUserDefaults setObject:titles forKey:kClientLoaderButtonTitlesKey];
    ClientLoaderRenderCustomButtons();
    [self reloadContent];
}

- (void)reloadContent {
    for (UIView *view in _rows.arrangedSubviews) {
        [_rows removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (_tabs.selectedSegmentIndex == 0) {
        [_rows addArrangedSubview:[self sectionLabel:@"Overlay"]];
        BOOL buttonsVisible = [NSUserDefaults.standardUserDefaults
            objectForKey:kClientLoaderButtonsVisibleKey]
            ? [NSUserDefaults.standardUserDefaults boolForKey:kClientLoaderButtonsVisibleKey]
            : YES;
        [_rows addArrangedSubview:[self rowWithTitle:@"Custom action buttons"
                                              detail:@"Show your added script actions over the game."
                                           accessory:[self switchWithIdentifier:@"__customButtons"
                                                                          isOn:buttonsVisible]]];
        BOOL haptics = [NSUserDefaults.standardUserDefaults
            objectForKey:kClientLoaderHapticsKey]
            ? [NSUserDefaults.standardUserDefaults boolForKey:kClientLoaderHapticsKey]
            : YES;
        [_rows addArrangedSubview:[self rowWithTitle:@"Haptic feedback"
                                              detail:@"Light vibration when changing a setting."
                                           accessory:[self switchWithIdentifier:@"__haptics"
                                                                          isOn:haptics]]];

        [_rows addArrangedSubview:[self sectionLabel:@"Script features"]];
        if (_bridge.features.count == 0) {
            [_rows addArrangedSubview:[self noteLabel:
                @"No script features registered. Add a feature in a local .js file to expose its toggle here."]];
        }
        for (NSDictionary *feature in _bridge.features) {
            NSString *title = feature[@"title"];
            [_rows addArrangedSubview:[self rowWithTitle:title
                                                  detail:@"Runs the local script callback when changed."
                                               accessory:[self switchWithIdentifier:title
                                                                              isOn:[feature[@"enabled"] boolValue]]]];
        }
    } else {
        [_rows addArrangedSubview:[self sectionLabel:@"Available actions"]];
        [_rows addArrangedSubview:[self noteLabel:
            @"Add an action as a floating on-screen button. Actions come from trusted local scripts."]];
        NSArray<NSString *> *added = [NSUserDefaults.standardUserDefaults
            arrayForKey:kClientLoaderButtonTitlesKey] ?: @[];
        if (_bridge.actions.count == 0) {
            [_rows addArrangedSubview:[self noteLabel:
                @"No script actions registered. Put .js files in Documents/ClientLoader/scripts/."]];
        }
        for (NSDictionary *action in _bridge.actions) {
            NSString *title = action[@"title"];
            BOOL isAdded = [added containsObject:title];
            UIButton *add = [self actionButton:(isAdded ? @"Added" : @"Add")
                                         action:@selector(addCustomButtonTapped:)
                                     identifier:title];
            add.enabled = !isAdded;
            if (isAdded) add.backgroundColor = ClientColor(@"#514B5B", 1);
            [_rows addArrangedSubview:[self rowWithTitle:title
                                                  detail:@"Creates a quick button for this script action."
                                               accessory:add]];
        }

        [_rows addArrangedSubview:[self sectionLabel:@"Your buttons"]];
        if (added.count == 0) {
            [_rows addArrangedSubview:[self noteLabel:@"No custom buttons yet."]];
        }
        for (NSString *title in added) {
            UIButton *remove = [self actionButton:@"Remove"
                                           action:@selector(removeCustomButtonTapped:)
                                       identifier:title];
            remove.backgroundColor = ClientColor(@"#8A435E", 1);
            [_rows addArrangedSubview:[self rowWithTitle:title
                                                  detail:@"Pinned to the game overlay."
                                               accessory:remove]];
        }
    }
    ClientLoaderLogStage(@"CL_BRIDGE", @"ui.controls.created",
        [NSString stringWithFormat:@"tab=%@ rows=%lu registeredFeatures=%lu registeredActions=%lu",
            _tabs.selectedSegmentIndex == 0 ? @"features" : @"buttons",
            (unsigned long)_rows.arrangedSubviews.count,
            (unsigned long)_bridge.features.count,
            (unsigned long)_bridge.actions.count]);
}

@end

@implementation ClientESPSyntheticOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.accessibilityLabel = @"Synthetic ESP test boxes, not live entities";
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    static NSUInteger syntheticFrameCount = 0;
    syntheticFrameCount++;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    if (width < 160 || height < 240) {
        if (syntheticFrameCount == 1) {
            ClientLoaderLogStage(@"CL_ESP", @"synthetic.draw.rejected",
                [NSString stringWithFormat:@"viewport too small width=%.1f height=%.1f", width, height]);
        }
        return;
    }

    NSArray<NSDictionary *> *samples = @[
        @{
            @"label": @"TEST COW  •  NOT LIVE",
            @"x": @(width * 0.16),
            @"y": @(height * 0.31),
            @"w": @(width * 0.25),
            @"h": @(height * 0.23),
            @"color": ClientColor(@"#64D98B", 0.96)
        },
        @{
            @"label": @"TEST PLAYER  •  NOT LIVE",
            @"x": @(width * 0.58),
            @"y": @(height * 0.39),
            @"w": @(width * 0.25),
            @"h": @(height * 0.34),
            @"color": ClientColor(@"#67B7FF", 0.96)
        }
    ];
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.whiteColor
    };
    for (NSDictionary *sample in samples) {
        CGRect box = CGRectMake([sample[@"x"] doubleValue],
                                [sample[@"y"] doubleValue],
                                [sample[@"w"] doubleValue],
                                [sample[@"h"] doubleValue]);
        UIColor *color = sample[@"color"];
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:box];
        path.lineWidth = 2.0;
        [color setStroke];
        [path stroke];

        CGRect labelRect = CGRectMake(box.origin.x,
                                      MAX(8, box.origin.y - 18),
                                      MIN(box.size.width + 100, width - box.origin.x),
                                      16);
        NSString *label = sample[@"label"];
        [label drawInRect:labelRect withAttributes:attributes];
    }
    if (syntheticFrameCount == 1 || syntheticFrameCount % 300 == 0) {
        ClientLoaderLogStage(@"CL_ESP", @"synthetic.draw",
            [NSString stringWithFormat:@"frame=%lu rectangles=%lu source=synthetic_not_live",
                (unsigned long)syntheticFrameCount, (unsigned long)samples.count]);
    }
}

@end

static UIWindow *ClientLoaderFindWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

static void ClientMenuOpen(void) {
    if (!sBridge.window) {
        ClientLoaderLog(@"ERROR: menu open requested before an active window was available");
        return;
    }
    if (sMenuPanel.superview) {
        ClientLoaderLog(@"Closing client panel");
        [sMenuPanel removeFromSuperview];
        sMenuPanel = nil;
        return;
    }
    ClientLoaderLog(@"Opening client panel");
    @try {
        ClientMenuPanel *panel = [[ClientMenuPanel alloc]
            initWithWindow:sBridge.window bridge:sBridge];
        panel.alpha = 0;
        [sBridge.window addSubview:panel];
        [sBridge.window bringSubviewToFront:panel];
        sMenuPanel = panel;
        ClientLoaderLog(@"Opened client panel");
        [UIView animateWithDuration:0.18 animations:^{ panel.alpha = 1; }];
    } @catch (NSException *exception) {
        sMenuPanel = nil;
        ClientLoaderLog([NSString stringWithFormat:
            @"ERROR: could not open client panel (%@): %@\nCall stack:\n%@",
            exception.name, exception.reason ?: @"(no reason)",
            [exception.callStackSymbols componentsJoinedByString:@"\n"]]);
    }
}

static void ClientMenuRefresh(void) {
    ClientLoaderLogStage(@"CL_BRIDGE", @"ui.refresh",
        [NSString stringWithFormat:@"featureCount=%lu actionCount=%lu panelPresent=%d",
            (unsigned long)sBridge.features.count, (unsigned long)sBridge.actions.count,
            sMenuPanel.superview != nil]);
    if (sMenuPanel.superview) [sMenuPanel reloadContent];
    ClientLoaderRenderCustomButtons();
}

static void ClientLoaderSetESPSyntheticOverlayEnabled(BOOL enabled) {
    sESPSyntheticOverlayEnabled = enabled;
    UIWindow *window = sBridge.window ?: ClientLoaderFindWindow();
    if (!window) {
        ClientLoaderLogStage(@"CL_ERROR", @"synthetic.window.missing", @"Cannot update synthetic overlay without an active window");
        return;
    }
    if (!enabled) {
        [sESPSyntheticOverlay removeFromSuperview];
        sESPSyntheticOverlay = nil;
        ClientLoaderLogStage(@"CL_ESP", @"synthetic.disabled", @"Synthetic test overlay removed; not live data");
        return;
    }
    if (sESPSyntheticOverlay.superview != window) {
        [sESPSyntheticOverlay removeFromSuperview];
        sESPSyntheticOverlay = [[ClientESPSyntheticOverlay alloc] initWithFrame:window.bounds];
        sESPSyntheticOverlay.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [window addSubview:sESPSyntheticOverlay];
    }
    [window bringSubviewToFront:sESPSyntheticOverlay];
    if (sMenuButton.superview == window) [window bringSubviewToFront:sMenuButton];
    ClientLoaderLogStage(@"CL_ESP", @"synthetic.enabled", @"Synthetic rectangles drawn; this is not live entity evidence");
}

static void ClientLoaderSetLiveESPEnabled(BOOL enabled) {
    sLiveESPEnabled = enabled;
    ClientLoaderLogStage(@"CL_ESP", @"live.setter", [NSString stringWithFormat:@"native setter received enabled=%d", enabled]);
    if (!enabled) {
        [sLiveESPDisplayLink invalidate];
        sLiveESPDisplayLink = nil;
        [sLiveESPLayer removeFromSuperview];
        sLiveESPLayer = nil;
        ClientLoaderLogStage(@"CL_ESP", @"live.disabled", @"Live overlay and display link removed");
        return;
    }

    UIWindow *window = sBridge.window ?: ClientLoaderFindWindow();
    if (!window) {
        ClientLoaderLogStage(@"CL_ERROR", @"live.window.missing", @"Cannot enable live overlay without an active window");
        return;
    }
    if (!sTarget) sTarget = [ClientLoaderTarget new];
    if (sLiveESPLayer.superview != window) {
        [sLiveESPLayer removeFromSuperview];
        sLiveESPLayer = [[CLESPOverlay alloc] initWithFrame:window.bounds];
        sLiveESPLayer.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [window addSubview:sLiveESPLayer];
    }
    sLiveESPLayer.enabled = YES;
    [window bringSubviewToFront:sLiveESPLayer];
    if (sMenuButton.superview == window) [window bringSubviewToFront:sMenuButton];
    if (!sLiveESPDisplayLink) {
        sLiveESPDisplayLink = [CADisplayLink displayLinkWithTarget:sTarget
                                                          selector:@selector(updateLiveESP:)];
        sLiveESPDisplayLink.preferredFramesPerSecond = 15;
        [sLiveESPDisplayLink addToRunLoop:NSRunLoop.mainRunLoop
                                  forMode:NSRunLoopCommonModes];
    }
    ClientLoaderLogStage(@"CL_ESP", @"live.enabled",
        [NSString stringWithFormat:@"display link active; entity provider=%@; camera provider=%@",
            [CLEntityProvider statusDescription], [CLCameraProvider statusDescription]]);
}

static void ClientLoaderSaveMenuButtonPosition(void) {
    UIWindow *window = sBridge.window;
    if (!window || CGRectGetWidth(window.bounds) <= 0 || CGRectGetHeight(window.bounds) <= 0) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:sMenuButton.center.x / CGRectGetWidth(window.bounds)
                 forKey:kClientLoaderButtonXKey];
    [defaults setDouble:sMenuButton.center.y / CGRectGetHeight(window.bounds)
                 forKey:kClientLoaderButtonYKey];
}

static void ClientLoaderClampButton(UIButton *button, UIWindow *window) {
    CGFloat radius = CGRectGetWidth(button.bounds) / 2.0;
    CGFloat minX = radius + 4;
    CGFloat maxX = MAX(minX, CGRectGetWidth(window.bounds) - radius - 4);
    CGFloat minY = radius + window.safeAreaInsets.top + 4;
    CGFloat maxY = MAX(minY, CGRectGetHeight(window.bounds) - radius - window.safeAreaInsets.bottom - 4);
    button.center = CGPointMake(MIN(MAX(button.center.x, minX), maxX),
                                MIN(MAX(button.center.y, minY), maxY));
}

static void ClientLoaderRenderCustomButtons(void) {
    UIWindow *window = sBridge.window;
    if (!window) {
        ClientLoaderLogStage(@"CL_ERROR", @"custom-buttons.window.missing", @"Cannot create action controls without an active window");
        return;
    }
    [sCustomButtonStack removeFromSuperview];
    sCustomButtonStack = nil;
    BOOL visible = [NSUserDefaults.standardUserDefaults
        objectForKey:kClientLoaderButtonsVisibleKey]
        ? [NSUserDefaults.standardUserDefaults boolForKey:kClientLoaderButtonsVisibleKey]
        : YES;
    if (!visible) {
        ClientLoaderLogStage(@"CL_BRIDGE", @"custom-buttons.hidden", @"Custom action controls disabled by user setting");
        return;
    }

    NSArray<NSString *> *titles = [NSUserDefaults.standardUserDefaults
        arrayForKey:kClientLoaderButtonTitlesKey] ?: @[];
    if (titles.count == 0) {
        ClientLoaderLogStage(@"CL_BRIDGE", @"custom-buttons.empty", @"No custom actions are pinned");
        return;
    }

    sCustomButtonStack = [UIStackView new];
    sCustomButtonStack.axis = UILayoutConstraintAxisVertical;
    sCustomButtonStack.alignment = UIStackViewAlignmentLeading;
    sCustomButtonStack.spacing = 8;
    sCustomButtonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [window addSubview:sCustomButtonStack];
    [NSLayoutConstraint activateConstraints:@[
        [sCustomButtonStack.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:12],
        [sCustomButtonStack.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-92],
        [sCustomButtonStack.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor multiplier:0.58]
    ]];

    for (NSString *title in titles) {
        NSDictionary *action = nil;
        for (NSDictionary *candidate in sBridge.actions) {
            if ([candidate[@"title"] isEqualToString:title]) {
                action = candidate;
                break;
            }
        }
        if (!action) continue;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        button.backgroundColor = ClientColor(@"#24212E", 0.94);
        button.layer.cornerRadius = 15;
        button.layer.borderWidth = 1;
        button.layer.borderColor = ClientColor(kClientLoaderAccent, 0.84).CGColor;
        button.contentEdgeInsets = UIEdgeInsetsMake(9, 13, 9, 13);
        button.accessibilityIdentifier = title;
        [button addTarget:sTarget action:@selector(runCustomAction:)
         forControlEvents:UIControlEventTouchUpInside];
        [sCustomButtonStack addArrangedSubview:button];
    }
    ClientLoaderLogStage(@"CL_BRIDGE", @"custom-buttons.created",
        [NSString stringWithFormat:@"requested=%lu created=%lu",
            (unsigned long)titles.count, (unsigned long)sCustomButtonStack.arrangedSubviews.count]);
}

@implementation ClientDraggableButton

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    UITouch *touch = touches.anyObject;
    UIWindow *window = self.window;
    if (!touch || !window) return;
    self.touchStart = [touch locationInView:window];
    self.initialCenter = self.center;
    self.didMove = NO;
    self.alpha = 0.82;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    UITouch *touch = touches.anyObject;
    UIWindow *window = self.window;
    if (!touch || !window) return;
    CGPoint location = [touch locationInView:window];
    CGFloat dx = location.x - self.touchStart.x;
    CGFloat dy = location.y - self.touchStart.y;
    if (!self.didMove && hypot(dx, dy) < 8.0) return;
    self.didMove = YES;
    self.center = CGPointMake(self.initialCenter.x + dx, self.initialCenter.y + dy);
    ClientLoaderClampButton(self, window);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    self.alpha = 1.0;
    if (self.didMove) {
        ClientLoaderSaveMenuButtonPosition();
    } else {
        ClientMenuOpen();
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    self.alpha = 1.0;
    if (self.didMove) ClientLoaderSaveMenuButtonPosition();
}

@end

static void ClientLoaderInstallButton(UIWindow *window) {
    sBridge.window = window;
    if (sMenuButton && sMenuButton.superview == window) {
        ClientLoaderClampButton(sMenuButton, window);
        ClientLoaderRenderCustomButtons();
        if (sESPSyntheticOverlayEnabled) ClientLoaderSetESPSyntheticOverlayEnabled(YES);
        if (sLiveESPEnabled) ClientLoaderSetLiveESPEnabled(YES);
        return;
    }
    [sMenuButton removeFromSuperview];
    CGFloat side = 54.0;
    sMenuButton = [ClientDraggableButton buttonWithType:UIButtonTypeSystem];
    sMenuButton.bounds = CGRectMake(0, 0, side, side);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    double savedX = [defaults doubleForKey:kClientLoaderButtonXKey];
    double savedY = [defaults doubleForKey:kClientLoaderButtonYKey];
    CGFloat x = savedX > 0 ? savedX * CGRectGetWidth(window.bounds) : CGRectGetWidth(window.bounds) - side / 2.0 - 16.0;
    CGFloat y = savedY > 0 ? savedY * CGRectGetHeight(window.bounds) : CGRectGetHeight(window.bounds) * 0.70;
    sMenuButton.center = CGPointMake(x, y);
    sMenuButton.backgroundColor = ClientColor(kClientLoaderAccent, 0.96);
    sMenuButton.layer.cornerRadius = side / 2.0;
    sMenuButton.layer.borderWidth = 1.5;
    sMenuButton.layer.borderColor = UIColor.whiteColor.CGColor;
    sMenuButton.layer.shadowColor = UIColor.blackColor.CGColor;
    sMenuButton.layer.shadowOpacity = 0.35;
    sMenuButton.layer.shadowRadius = 7;
    sMenuButton.layer.shadowOffset = CGSizeMake(0, 3);
    [sMenuButton setTitle:@"C" forState:UIControlStateNormal];
    [sMenuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    sMenuButton.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    sMenuButton.userInteractionEnabled = YES;
    sMenuButton.multipleTouchEnabled = NO;
    sMenuButton.exclusiveTouch = YES;
    sMenuButton.accessibilityLabel = @"Drag or open Client Menu";
    sMenuButton.accessibilityHint = @"Drag to move; tap to open the client panel";
    if (!sTarget) sTarget = [ClientLoaderTarget new];
    [window addSubview:sMenuButton];
    ClientLoaderClampButton(sMenuButton, window);
    ClientLoaderRenderCustomButtons();
    if (sESPSyntheticOverlayEnabled) ClientLoaderSetESPSyntheticOverlayEnabled(YES);
    if (sLiveESPEnabled) ClientLoaderSetLiveESPEnabled(YES);
    ClientLoaderLogStage(@"CL_INIT", @"menu-button.attached",
        [NSString stringWithFormat:@"center=%@ window=%.1fx%.1f safeArea=%.1f,%.1f,%.1f,%.1f",
            NSStringFromCGPoint(sMenuButton.center), CGRectGetWidth(window.bounds),
            CGRectGetHeight(window.bounds), window.safeAreaInsets.top, window.safeAreaInsets.left,
            window.safeAreaInsets.bottom, window.safeAreaInsets.right]);
}

@implementation ClientLoaderTarget

- (void)updateLiveESP:(CADisplayLink *)displayLink {
    (void)displayLink;
    if (!sLiveESPEnabled || !sLiveESPLayer) return;
    static NSUInteger updateCount = 0;
    updateCount++;
    if (updateCount == 1 || updateCount % 300 == 0) {
        ClientLoaderLogStage(@"CL_ESP", @"live.update",
            [NSString stringWithFormat:@"frame=%lu snapshotCount=%lu entityStatus=%@ cameraStatus=%@",
                (unsigned long)updateCount, (unsigned long)CLEntityProvider.latestSnapshots.count,
                [CLEntityProvider statusDescription], [CLCameraProvider statusDescription]]);
    }
    [sLiveESPLayer updateWithSnapshots:[CLEntityProvider latestSnapshots]];
}

- (void)runCustomAction:(UIButton *)sender {
    NSString *title = sender.accessibilityIdentifier;
    ClientLoaderLogStage(@"CL_BRIDGE", @"action.button.tapped",
        [NSString stringWithFormat:@"title=%@", [title substringToIndex:MIN(title.length, 120)]]);
    for (NSDictionary *action in sBridge.actions) {
        if (![action[@"title"] isEqualToString:title]) continue;
        JSValue *callback = action[@"callback"];
        ClientLoaderInvokeJSCallback(callback, @[],
            [NSString stringWithFormat:@"registerAction title=%@", [title substringToIndex:MIN(title.length, 120)]]);
        if (ClientLoaderHapticsEnabled()) {
            UIImpactFeedbackGenerator *feedback =
                [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [feedback impactOccurred];
        }
        return;
    }
    ClientLoaderLogStage(@"CL_ERROR", @"action.button.callback.missing",
        [NSString stringWithFormat:@"No registered callback for title=%@", [title substringToIndex:MIN(title.length, 120)]]);
}

@end

static void ClientLoaderLoadScripts(void) {
    if (sScriptsLoaded) {
        ClientLoaderLogStage(@"CL_BRIDGE", @"scripts.skip", @"Script initialization already completed");
        return;
    }
    NSURL *documents = [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory
               inDomains:NSUserDomainMask] firstObject];
    if (!documents) {
        ClientLoaderLogStage(@"CL_ERROR", @"scripts.documents.missing", @"Documents directory unavailable");
        return;
    }
    NSURL *scriptDirectory = [[documents URLByAppendingPathComponent:@"ClientLoader" isDirectory:YES]
        URLByAppendingPathComponent:@"scripts" isDirectory:YES];
    ClientLoaderLogStage(@"CL_INIT", @"scripts.directory", @"Creating/discovering local JavaScript directory");
    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:scriptDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&directoryError]) {
        ClientLoaderLog([NSString stringWithFormat:
            @"ERROR: could not create script directory: %@", directoryError]);
        return;
    }
    sBridge = [ClientMenuBridge new];
    if (!sBridge) {
        ClientLoaderLogStage(@"CL_ERROR", @"bridge.create.failed", @"Could not instantiate ClientMenu bridge");
        return;
    }
    sContext = [JSContext new];
    if (!sContext) {
        ClientLoaderLogStage(@"CL_ERROR", @"jscontext.create.failed", @"JavaScriptCore returned a nil context");
        sBridge = nil;
        return;
    }
    sBridge.context = sContext;
    sContext[@"ClientMenu"] = sBridge;
    JSValue *registeredBridge = sContext[@"ClientMenu"];
    ClientLoaderLogStage(@"CL_BRIDGE", @"bridge.exposed",
        [NSString stringWithFormat:@"ClientMenu objectPresent=%d documentedMethods=registerAction,registerFeature,isFeatureEnabled,notify,exportJSON,setSyntheticESPEnabled,setLiveESPEnabled,exportDiagnostics",
            registeredBridge && registeredBridge.isObject]);
    sContext.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        (void)context;
        sScriptEvaluationFailureCount++;
        NSString *stack = exception[@"stack"].toString ?: @"";
        if (scriptDirectory.path.length > 0) {
            stack = [stack stringByReplacingOccurrencesOfString:scriptDirectory.path withString:@"<Documents/ClientLoader/scripts>"];
        }
        ClientLoaderLogStage(@"CL_ERROR", @"javascript.exception",
            [NSString stringWithFormat:@"exception=%@ stack=%@",
                exception.toString ?: @"unknown JavaScript exception", stack]);
    };
    ClientLoaderInstallConsoleBridge();

    NSError *listingError = nil;
    NSArray<NSURL *> *items = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:scriptDirectory
       includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                          options:NSDirectoryEnumerationSkipsHiddenFiles
                            error:&listingError];
    if (!items) {
        ClientLoaderLogStage(@"CL_ERROR", @"scripts.list.failed",
            [NSString stringWithFormat:@"Could not list scripts: %@", listingError.localizedDescription ?: @"unknown error"]);
        return;
    }

    NSArray<NSURL *> *scripts = [[items filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSURL *url, __unused NSDictionary *bindings) {
            NSNumber *isRegularFile = nil;
            [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
            return isRegularFile.boolValue && [url.pathExtension.lowercaseString isEqualToString:@"js"];
        }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
        }];
        NSMutableArray<NSString *> *scriptNames = [NSMutableArray arrayWithCapacity:scripts.count];
        for (NSURL *scriptURL in scripts) [scriptNames addObject:scriptURL.lastPathComponent];
        ClientLoaderLogStage(@"CL_INIT", @"scripts.discovered",
            [NSString stringWithFormat:@"count=%lu names=%@", (unsigned long)scripts.count, scriptNames]);
        sScriptsLoaded = YES;
        NSUInteger successfulEvaluations = 0;
    for (NSURL *scriptURL in scripts) {
        NSError *readError = nil;
        NSString *source = [NSString stringWithContentsOfURL:scriptURL
                                                   encoding:NSUTF8StringEncoding
                                                      error:&readError];
        if (!source) {
            ClientLoaderLogStage(@"CL_ERROR", @"script.read.failed",
                [NSString stringWithFormat:@"file=%@ error=%@", scriptURL.lastPathComponent,
                    readError.localizedDescription ?: @"unknown error"]);
            continue;
        }
        NSData *sourceData = [source dataUsingEncoding:NSUTF8StringEncoding];
        NSString *sourceHash = ClientLoaderSHA256(sourceData);
        NSString *expectedHash = [scriptURL.lastPathComponent isEqualToString:@"esp_test.js"]
            ? @CL_EXPECTED_ESP_TEST_JS_SHA256 : @"not-defined-for-this-script";
        NSUInteger featuresBefore = sBridge.features.count;
        NSUInteger actionsBefore = sBridge.actions.count;
        NSUInteger failuresBefore = sScriptEvaluationFailureCount;
        CFTimeInterval evaluationStart = CACurrentMediaTime();
        ClientLoaderLogStage(@"CL_BRIDGE", @"script.evaluate.begin",
            [NSString stringWithFormat:@"Evaluating script %@ bytes=%lu sha256=%@ expectedSHA256=%@",
                scriptURL.lastPathComponent, (unsigned long)sourceData.length, sourceHash, expectedHash]);
        sContext.exception = nil;
        JSValue *result = [sContext evaluateScript:source withSourceURL:scriptURL];
        JSValue *evaluationException = sContext.exception;
        BOOL succeeded = result != nil && (!evaluationException || evaluationException.isUndefined || evaluationException.isNull) &&
            sScriptEvaluationFailureCount == failuresBefore;
        if (succeeded) successfulEvaluations++;
        NSUInteger featuresAdded = sBridge.features.count - MIN(featuresBefore, sBridge.features.count);
        NSUInteger actionsAdded = sBridge.actions.count - MIN(actionsBefore, sBridge.actions.count);
        NSMutableDictionary *expectedControls = [NSMutableDictionary dictionary];
        if ([scriptURL.lastPathComponent isEqualToString:@"esp_test.js"]) {
            for (NSString *expectedTitle in @[@"Synthetic ESP test boxes", @"Live mob ESP"]) {
                expectedControls[expectedTitle] = @([sBridge.features indexOfObjectPassingTest:^BOOL(NSDictionary *feature, NSUInteger idx, BOOL *stop) {
                    (void)idx; (void)stop;
                    return [feature[@"title"] isEqualToString:expectedTitle];
                }] != NSNotFound);
            }
            expectedControls[@"Export chunk data diagnostic"] = @([sBridge.actions indexOfObjectPassingTest:^BOOL(NSDictionary *action, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                return [action[@"title"] isEqualToString:@"Export chunk data diagnostic"];
            }] != NSNotFound);
        }
        ClientLoaderLogStage(succeeded ? @"CL_BRIDGE" : @"CL_ERROR", @"script.evaluate.end",
            [NSString stringWithFormat:@"file=%@ status=%@ durationMs=%.3f featuresAdded=%lu actionsAdded=%lu controls=%@",
                scriptURL.lastPathComponent, succeeded ? @"success" : @"failed",
                (CACurrentMediaTime() - evaluationStart) * 1000.0,
                (unsigned long)featuresAdded, (unsigned long)actionsAdded, expectedControls]);
        sContext.exception = nil;
    }
    ClientLoaderLogStage(@"CL_BRIDGE", @"scripts.complete",
        [NSString stringWithFormat:@"discovered=%lu evaluatedSuccessfully=%lu failed=%lu featureCount=%lu actionCount=%lu",
            (unsigned long)scripts.count, (unsigned long)successfulEvaluations,
            (unsigned long)sScriptEvaluationFailureCount, (unsigned long)sBridge.features.count,
            (unsigned long)sBridge.actions.count]);
    ClientLoaderWriteDiagnosticReport(@"StartupReport.json", @"startup-report.after-scripts");
}

static void ClientLoaderStart(void) {
    NSDictionary *bundleInfo = NSBundle.mainBundle.infoDictionary ?: @{};
    if (sWindowLookupAttempts == 0) {
        ClientLoaderWriteDiagnosticReport(@"StartupReport.json", @"startup-report.initial");
    }
    if (sWindowLookupAttempts == 0 || sWindowLookupAttempts % 10 == 0) {
        ClientLoaderLogStage(@"CL_INIT", @"start.begin",
            [NSString stringWithFormat:@"bundle=%@ version=%@ build=%@ attempt=%lu",
                NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
                bundleInfo[@"CFBundleShortVersionString"] ?: @"unknown",
                bundleInfo[@"CFBundleVersion"] ?: @"unknown",
                (unsigned long)sWindowLookupAttempts]);
    }
    static dispatch_once_t registryLoadOnce;
    dispatch_once(&registryLoadOnce, ^{
        ClientLoaderLogStage(@"CL_INIT", @"entity-registry.begin", @"Registry load started; definitions are not live entities");
        NSError *error = nil;
        if ([CLEntityTypeRegistry loadRegistryFromDocumentsWithError:&error]) {
            NSDictionary *report = [CLEntityTypeRegistry diagnostics];
            ClientLoaderLogStage(@"CL_INIT", @"entity-registry.complete",
                [NSString stringWithFormat:@"Loaded %lu type definitions from %@; no live instances inferred",
                (unsigned long)[report[@"loadedIdentifierCount"] unsignedIntegerValue],
                report[@"sourceDirectory"]]);
        } else {
            ClientLoaderLogStage(@"CL_ERROR", @"entity-registry.failed",
                error.localizedDescription ?: @"unknown registry error");
        }
    });
    ClientLoaderLoadScripts();
    ClientLoaderLogStage(@"CL_INIT", @"window.lookup.begin", @"Searching foreground active UIWindowScene for key window");
    UIWindow *window = ClientLoaderFindWindow();
    if (window) {
        sWindowLookupAttempts = 0;
        ClientLoaderLogLoadedImageState(@"dyld.loaded-image-probe");
        ClientLoaderInstallButton(window);
        ClientLoaderLogStage(@"CL_INIT", @"start.complete", @"Menu button initialization complete");
        return;
    }
    if (++sWindowLookupAttempts > 120) {
        ClientLoaderLogStage(@"CL_ERROR", @"window.lookup.exhausted", @"Gave up after 120 window lookup attempts");
        return;
    }
    if (sWindowLookupAttempts == 1 || sWindowLookupAttempts % 10 == 0) {
        ClientLoaderLogStage(@"CL_RUNTIME", @"window.lookup.retry",
            [NSString stringWithFormat:@"attempt=%lu", (unsigned long)sWindowLookupAttempts]);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ ClientLoaderStart(); });
}

__attribute__((constructor))
static void ClientLoaderInitialize(void) {
    @autoreleasepool {
        sLogLock = [NSObject new];
        sClientLoaderSessionID = NSUUID.UUID.UUIDString;
        [NSUserDefaults.standardUserDefaults setObject:sClientLoaderSessionID
                            forKey:kClientLoaderDiagnosticSessionKey];
        [NSUserDefaults.standardUserDefaults setObject:[NSDate date]
                            forKey:kClientLoaderDiagnosticStartKey];
        [CLDiagnostics configureWithSessionID:sClientLoaderSessionID
                               buildRevision:@CL_BUILD_REVISION
                               buildTimestamp:@CL_BUILD_TIMESTAMP];
        sPreviousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&ClientLoaderHandleUncaughtException);
        NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
        ClientLoaderLogStage(@"CL_INIT", @"constructor",
            [NSString stringWithFormat:@"native library initialized buildID=%@ buildTimestamp=%@ process=%@ bundle=%@ gameVersion=%@ gameBuild=%@ os=%@ architecture=%@ expectedGameBuild=1.26.33.01 hooks=not-installed",
                @CL_BUILD_REVISION, @CL_BUILD_TIMESTAMP, NSProcessInfo.processInfo.processName ?: @"unknown",
                NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
                info[@"CFBundleShortVersionString"] ?: @"unknown",
                info[@"CFBundleVersion"] ?: @"unknown",
                NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown",
#if defined(__arm64e__)
                @"arm64e"
#elif defined(__arm64__)
                @"arm64"
#elif defined(__x86_64__)
                @"x86_64"
#else
                @"unknown"
#endif
            ]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *notification) {
                    ClientLoaderLogStage(@"CL_RUNTIME", @"application.active", @"Application became active");
                    ClientLoaderLogLoadedImageState(@"dyld.loaded-image-probe.active");
                sWindowLookupAttempts = 0;
                ClientLoaderStart();
            }];
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *notification) {
                ClientLoaderLogStage(@"CL_RUNTIME", @"application.background", @"Writing lifecycle diagnostic snapshot");
                ClientLoaderWriteDiagnosticReport(@"StartupReport.json", @"startup-report.background");
                ClientLoaderWriteDiagnosticReport(@"ESPDiagnostic.json", @"esp-report.background");
            }];
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationWillTerminateNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *notification) {
                ClientLoaderLogStage(@"CL_RUNTIME", @"application.terminate", @"Writing final diagnostic snapshot");
                ClientLoaderWriteDiagnosticReport(@"StartupReport.json", @"startup-report.termination");
                ClientLoaderWriteDiagnosticReport(@"ESPDiagnostic.json", @"esp-report.termination");
            }];
            ClientLoaderStart();
        });
    }
}
