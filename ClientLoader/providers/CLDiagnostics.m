#import "CLDiagnostics.h"
#import "CLEntityProvider.h"
#import "CLCameraProvider.h"
#import "CLEntityTypeRegistry.h"

static NSMutableArray<NSDictionary *> *sRecentErrors;
static NSMutableArray<NSDictionary *> *sRecentEvents;
static NSString *sSessionID;
static NSString *sBuildRevision;
static NSString *sBuildTimestamp;
static NSDictionary *sESPFrameMetrics;

static NSString *CLArchitectureName(void) {
#if defined(__arm64e__)
    return @"arm64e";
#elif defined(__arm64__)
    return @"arm64";
#elif defined(__x86_64__)
    return @"x86_64";
#elif defined(__arm__)
    return @"arm";
#else
    return @"unknown";
#endif
}

static NSString *CLDiagnosticTimestamp(void) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [formatter stringFromDate:[NSDate date]];
}

@implementation CLDiagnostics

+ (void)initialize {
    if (self != CLDiagnostics.class) return;
    sRecentErrors = [NSMutableArray array];
    sRecentEvents = [NSMutableArray array];
    sSessionID = @"uninitialized";
    sBuildRevision = @"unknown";
    sBuildTimestamp = @"unknown";
    sESPFrameMetrics = @{};
}

+ (void)configureWithSessionID:(NSString *)sessionID
                 buildRevision:(NSString *)buildRevision
                buildTimestamp:(NSString *)buildTimestamp {
    @synchronized (self) {
        if (sessionID.length > 0) sSessionID = [sessionID copy];
        if (buildRevision.length > 0) sBuildRevision = [buildRevision copy];
        if (buildTimestamp.length > 0) sBuildTimestamp = [buildTimestamp copy];
    }
}

+ (void)recordEvent:(NSString *)category
              stage:(NSString *)stage
            message:(NSString *)message
             fields:(NSDictionary<NSString *,id> *)fields {
    if (category.length == 0 || stage.length == 0) return;
    @synchronized (self) {
        [sRecentEvents addObject:@{
            @"timestamp": CLDiagnosticTimestamp(),
            @"sessionID": sSessionID ?: @"unknown",
            @"category": [category copy],
            @"stage": [stage copy],
            @"message": [message copy] ?: @"",
            @"fields": fields ?: @{}
        }];
        if (sRecentEvents.count > 128) {
            [sRecentEvents removeObjectsInRange:NSMakeRange(0, sRecentEvents.count - 128)];
        }
    }
}

+ (void)recordESPFrame:(NSDictionary<NSString *,NSNumber *> *)metrics {
    if (!metrics) return;
    @synchronized (self) { sESPFrameMetrics = [metrics copy]; }
}

+ (void)recordError:(NSString *)message {
    if (message.length == 0) return;
    @synchronized (self) {
        [sRecentErrors addObject:@{
            @"timestamp": CLDiagnosticTimestamp(),
            @"message": [message copy]
        }];
        if (sRecentErrors.count > 32) {
            [sRecentErrors removeObjectsInRange:NSMakeRange(0, sRecentErrors.count - 32)];
        }
    }
}

+ (NSDictionary *)runtimeReport {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSArray *errors;
    NSArray *events;
    NSString *sessionID;
    NSString *buildRevision;
    NSString *buildTimestamp;
    NSDictionary *espFrameMetrics;
    @synchronized (self) {
        errors = [sRecentErrors copy];
        events = [sRecentEvents copy];
        sessionID = [sSessionID copy];
        buildRevision = [sBuildRevision copy];
        buildTimestamp = [sBuildTimestamp copy];
        espFrameMetrics = [sESPFrameMetrics copy];
    }
    return @{
        @"schemaVersion": @2,
        @"producer": @"native ClientLoader.CLDiagnostics.runtimeReport",
        @"exportRoute": @"ClientMenu.exportDiagnostics",
        @"captureTimestamp": CLDiagnosticTimestamp(),
        @"sessionID": sessionID ?: @"unknown",
        @"buildRevision": buildRevision ?: @"unknown",
        @"buildTimestamp": buildTimestamp ?: @"unknown",
        @"minecraft": @{
            @"bundleIdentifier": info[@"CFBundleIdentifier"] ?: @"unknown",
            @"version": info[@"CFBundleShortVersionString"] ?: @"unknown",
            @"build": info[@"CFBundleVersion"] ?: @"unknown",
            @"processArchitecture": CLArchitectureName()
        },
        @"entityProvider": [CLEntityProvider diagnostics],
        @"entityTypeRegistry": [CLEntityTypeRegistry diagnostics],
        @"cameraProvider": [CLCameraProvider diagnostics],
        @"espFrameMetrics": espFrameMetrics ?: @{},
        @"recentLifecycleEvents": events ?: @[],
        @"recentErrors": errors ?: @[],
        @"captureStatus": ([CLEntityProvider status] == CLEntityProviderStatusReady &&
                           [CLCameraProvider status] == CLCameraProviderStatusReady)
            ? @"ready" : @"unavailable",
        @"limitations": @[
            @"No live entity data is included unless a verified native adapter publishes snapshots.",
            @"No camera data is included unless a verified camera adapter publishes a matrix.",
            @"Block/chunk data is not captured."
        ]
    };
}

+ (nullable NSString *)writeRuntimeReportToDocumentsFile:(NSString *)fileName
                                                   error:(NSError **)error {
    if (![fileName isKindOfClass:NSString.class] || fileName.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ClientLoader.Diagnostics"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"A JSON filename is required."}];
        }
        return nil;
    }
    NSRegularExpression *pattern = [NSRegularExpression
        regularExpressionWithPattern:@"^[A-Za-z0-9_-]{1,64}\\.json$"
                             options:0
                               error:error];
    if (!pattern) return nil;
    NSTextCheckingResult *match = [pattern firstMatchInString:fileName
                                                      options:0
                                                        range:NSMakeRange(0, fileName.length)];
    if (!match || match.range.length != fileName.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"ClientLoader.Diagnostics"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Invalid JSON export filename."}];
        }
        return nil;
    }

    NSURL *documents = [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    if (!documents) {
        if (error) {
            *error = [NSError errorWithDomain:@"ClientLoader.Diagnostics"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Documents directory is unavailable."}];
        }
        return nil;
    }
    NSURL *directory = [[documents URLByAppendingPathComponent:@"ClientLoader"
                                                   isDirectory:YES]
        URLByAppendingPathComponent:@"exports" isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
        if (error && *error) [self recordError:[*error localizedDescription]];
        return nil;
    }
    NSURL *url = [directory URLByAppendingPathComponent:fileName];
    NSDictionary *report = [self runtimeReport];
    NSData *data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) {
        if (error && *error) [self recordError:[*error localizedDescription]];
        return nil;
    }
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) {
        if (error && *error) [self recordError:[*error localizedDescription]];
        return nil;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:url.path error:error];
    if (!attributes || [attributes[NSFileSize] unsignedLongLongValue] != data.length) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"ClientLoader.Diagnostics"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Diagnostic export size verification failed."}];
        }
        if (error && *error) [self recordError:[*error localizedDescription]];
        return nil;
    }
    return url.path;
}

@end
