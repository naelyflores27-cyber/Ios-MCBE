#import "Diagnostics.h"

#import <CommonCrypto/CommonDigest.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#ifndef BNE_BUILD_REVISION
#define BNE_BUILD_REVISION "unknown"
#endif
#ifndef BNE_BUILD_TIMESTAMP
#define BNE_BUILD_TIMESTAMP "unknown"
#endif
#ifndef BNE_EXPECTED_GAME_BUILD
#define BNE_EXPECTED_GAME_BUILD "1.26.33.01"
#endif
#ifndef BNE_EXPECTED_ESP_TEST_JS_SHA256
#define BNE_EXPECTED_ESP_TEST_JS_SHA256 "c733b58b9299e69031a326d2102c596882ffe12e2653c3ed5e0c98f9e54d30bc"
#endif

static const unsigned long long kBNELogMaximumBytes = 512 * 1024;
static const NSUInteger kBNELogBackupCount = 3;
static const NSUInteger kBNEStageRecordLimit = 128;
static NSRecursiveLock *sDiagnosticsLock;
static NSMutableArray<NSDictionary *> *sStages;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sStatuses;
static NSMutableDictionary<NSString *, NSNumber *> *sRenderMetrics;
static NSString *sSessionID;
static uint64_t sRenderFrameCount;

static NSString *BNEUTCNow(void) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [formatter stringFromDate:[NSDate date]];
}

static NSString *BNEArchitecture(void) {
#if defined(__arm64e__)
    return @"arm64e";
#elif defined(__arm64__)
    return @"arm64";
#elif defined(__x86_64__)
    return @"x86_64";
#else
    return @"unknown";
#endif
}

static NSURL *BNEDocumentsURL(void) {
    return [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
}

static NSURL *BNEDiagnosticsDirectory(void) {
    NSURL *documents = BNEDocumentsURL();
    if (!documents) return nil;
    return [documents URLByAppendingPathComponent:@"ClientLoader" isDirectory:YES];
}

static BOOL BNEEnsureDirectory(NSURL *directory, NSError **error) {
    if (!directory) return NO;
    return [[NSFileManager defaultManager]
        createDirectoryAtURL:directory
  withIntermediateDirectories:YES
                   attributes:nil
                        error:error];
}

static void BNERotateLogIfNeeded(NSURL *logURL) {
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:logURL.path error:nil];
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    if (size < kBNELogMaximumBytes) return;

    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *oldest = [logURL URLByAppendingPathExtension:@"3"];
    [manager removeItemAtURL:oldest error:nil];
    for (NSInteger index = (NSInteger)kBNELogBackupCount - 1; index >= 1; index--) {
        NSURL *source = [logURL URLByAppendingPathExtension:[NSString stringWithFormat:@"%ld", (long)index]];
        NSURL *destination = [logURL URLByAppendingPathExtension:[NSString stringWithFormat:@"%ld", (long)index + 1]];
        if ([manager fileExistsAtPath:source.path]) [manager moveItemAtURL:source toURL:destination error:nil];
    }
    if ([manager fileExistsAtPath:logURL.path]) {
        [manager moveItemAtURL:logURL
                         toURL:[logURL URLByAppendingPathExtension:@"1"]
                         error:nil];
    }
}

static BOOL BNEAppendLogData(NSData *data, BOOL synchronize, NSError **error) {
    NSURL *directory = BNEDiagnosticsDirectory();
    if (!BNEEnsureDirectory(directory, error)) return NO;
    NSURL *logURL = [directory URLByAppendingPathComponent:@"BedrockNetworkESP_Lab.log"];
    BNERotateLogIfNeeded(logURL);
    int descriptor = open(logURL.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (descriptor < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                code:errno
                                            userInfo:nil];
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    size_t remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(descriptor, bytes, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            int writeError = errno;
            close(descriptor);
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                    code:writeError
                                                userInfo:nil];
            return NO;
        }
        bytes += written;
        remaining -= (size_t)written;
    }
    if (synchronize) fsync(descriptor);
    close(descriptor);
    return YES;
}

static NSString *BNEImageBaseName(const char *imageName) {
    if (!imageName) return @"";
    return [[NSString stringWithUTF8String:imageName] lastPathComponent] ?: @"";
}

static NSArray<NSString *> *BNERelatedLoadedImages(void) {
    NSMutableArray<NSString *> *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        NSString *name = BNEImageBaseName(_dyld_get_image_name(index));
        NSString *lower = name.lowercaseString;
        if ([lower containsString:@"minecraftpe"] ||
            [lower containsString:@"clientloader"] ||
            [lower containsString:@"bedrocknetworkesp"] ||
            [lower containsString:@"javascriptcore"]) {
            [images addObject:name];
        }
    }
    return images;
}

static NSString *BNESHA256ForFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return @"unavailable";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static NSDictionary *BNEBridgeProbe(void) {
    Class contextClass = objc_getClass("JSContext");
    Class bridgeClass = objc_getClass("ClientMenuBridge");
    NSArray<NSString *> *selectors = @[
        @"registerAction:callback:",
        @"registerFeature:enabled:callback:",
        @"isFeatureEnabled:",
        @"notify:",
        @"exportJSON:fileName:",
        @"setSyntheticESPEnabled:",
        @"setLiveESPEnabled:",
        @"exportDiagnostics:"
    ];
    NSMutableArray *available = [NSMutableArray array];
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if (bridgeClass && class_getInstanceMethod(bridgeClass, selector)) {
            [available addObject:name];
        }
    }
    return @{
        @"JSContextClassPresent": @(contextClass != Nil),
        @"ClientMenuBridgeClassPresent": @(bridgeClass != Nil),
        @"bridgeSelectorsPresent": available,
        @"scriptEvaluationObserved": @NO,
        @"scriptEvaluationReason": @"This dylib does not own ClientLoader's JSContext; consult ClientLoader.log for evaluation events."
    };
}

static NSDictionary *BNEInstalledScripts(void) {
    NSURL *documents = BNEDocumentsURL();
    if (!documents) return @{@"status": @"unavailable", @"reason": @"Documents URL unavailable", @"files": @[]};
    NSURL *directory = [[documents URLByAppendingPathComponent:@"ClientLoader" isDirectory:YES]
        URLByAppendingPathComponent:@"scripts" isDirectory:YES];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:directory.path isDirectory:&isDirectory] || !isDirectory) {
        return @{@"status": @"missing", @"reason": @"Documents/ClientLoader/scripts does not exist", @"files": @[]};
    }
    NSError *listingError = nil;
    NSArray<NSURL *> *items = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles
        error:&listingError];
    if (!items) {
        return @{@"status": @"error", @"reason": listingError.localizedDescription ?: @"Directory listing failed", @"files": @[]};
    }
    NSMutableArray *scripts = [NSMutableArray array];
    for (NSURL *item in items ?: @[]) {
        if (![item.pathExtension.lowercaseString isEqualToString:@"js"]) continue;
        NSDictionary *attributes = [[NSFileManager defaultManager]
            attributesOfItemAtPath:item.path error:nil];
        NSString *hash = BNESHA256ForFile(item.path);
        NSMutableDictionary *script = [@{
            @"file": item.lastPathComponent,
            @"bytes": attributes[NSFileSize] ?: @0,
            @"sha256": hash,
            @"evaluationStatus": @"not-observed-by-this-dylib"
        } mutableCopy];
        if ([item.lastPathComponent isEqualToString:@"esp_test.js"]) {
            script[@"expectedSourceSHA256"] = @BNE_EXPECTED_ESP_TEST_JS_SHA256;
            script[@"sourceMatchStatus"] = [hash isEqualToString:@BNE_EXPECTED_ESP_TEST_JS_SHA256]
                ? @"matched" : @"mismatch";
        }
        [scripts addObject:script];
    }
    return @{@"status": @"readable", @"directory": @"Documents/ClientLoader/scripts", @"files": scripts};
}

static NSDictionary *BNEClientLoaderLogEvidence(void) {
    NSURL *directory = BNEDiagnosticsDirectory();
    NSURL *logURL = [directory URLByAppendingPathComponent:@"ClientLoader.log"];
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:logURL.path error:nil];
    if (!attributes) return @{@"status": @"missing", @"events": @[]};

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:logURL.path];
    if (!handle) return @{@"status": @"unreadable", @"events": @[]};
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    unsigned long long start = size > 64 * 1024 ? size - 64 * 1024 : 0;
    [handle seekToFileOffset:start];
    NSData *tail = [handle readDataToEndOfFile];
    [handle closeFile];
    NSString *text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding];
    if (!text) return @{@"status": @"invalid-utf8", @"events": @[]};
    NSString *sessionID = [NSUserDefaults.standardUserDefaults
        stringForKey:@"ClientLoader.diagnostics.sessionID"];

    NSArray<NSString *> *markers = @[
        @"Evaluating script ", @"Loaded ", @"JavaScript exception",
        @"registerFeature.success", @"registerAction.success", @"callback.begin",
        @"callback.end", @"callback.exception", @"script.evaluate.end",
        @"ui.toggle.changed", @"synthetic.enabled", @"synthetic.disabled",
        @"live.enabled", @"live.disabled", @"Exported native CLDiagnostics",
        @"diagnostic export failed"
    ];
    NSMutableArray *events = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (sessionID.length > 0 && ![line containsString:sessionID]) continue;
        BOOL relevant = NO;
        for (NSString *marker in markers) {
            if ([line containsString:marker]) { relevant = YES; break; }
        }
        if (!relevant) continue;
        NSString *boundedLine = line.length > 512 ? [line substringToIndex:512] : line;
        [events addObject:boundedLine];
        if (events.count == 48) break;
    }
    return @{
        @"status": @"available",
        @"source": @"existing ClientLoader.log, filtered to script/ESP/export markers",
        @"clientLoaderSessionID": sessionID ?: @"unavailable",
        @"tailBytesRead": @(tail.length),
        @"filteredEvents": events
    };
}

static NSDictionary *BNEEnvironment(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    NSArray *images = BNERelatedLoadedImages();
    NSDictionary *clientLogEvidence = BNEClientLoaderLogEvidence();
    NSArray<NSString *> *scriptEvents = clientLogEvidence[@"filteredEvents"] ?: @[];
    BOOL evaluationObserved = NO;
    BOOL registrationObserved = NO;
    BOOL controlBuildObserved = NO;
    BOOL callbackStartObserved = NO;
    BOOL callbackFinishObserved = NO;
    for (NSString *event in scriptEvents) {
        if ([event containsString:@"script.evaluate.end"] || [event containsString:@"Evaluating script "]) evaluationObserved = YES;
        if ([event containsString:@"registerFeature.success"] || [event containsString:@"registerAction.success"]) registrationObserved = YES;
        if ([event containsString:@"ui.controls.created"]) controlBuildObserved = YES;
        if ([event containsString:@"callback.begin"]) callbackStartObserved = YES;
        if ([event containsString:@"callback.end"]) callbackFinishObserved = YES;
    }
    NSMutableDictionary *bridge = [BNEBridgeProbe() mutableCopy];
    bridge[@"scriptEvaluationObserved"] = @(evaluationObserved);
    bridge[@"controlRegistrationObserved"] = @(registrationObserved);
    bridge[@"nativeControlCreationObserved"] = @(controlBuildObserved);
    bridge[@"callbackStartObserved"] = @(callbackStartObserved);
    bridge[@"callbackCompletionObserved"] = @(callbackFinishObserved);
    bridge[@"callbackStatus"] = callbackFinishObserved ? @"completion-observed" :
        (callbackStartObserved ? @"started-no-completion-observed" : @"no-current-session-evidence");
    bridge[@"scriptLogEvidenceStatus"] = clientLogEvidence[@"status"] ?: @"unknown";
    bridge[@"scriptEvaluationReason"] = evaluationObserved
        ? @"Evaluation markers found in the filtered ClientLoader.log tail."
        : @"No evaluation marker found in the readable ClientLoader.log tail; this is not proof the script was never evaluated.";
    return @{
        @"processName": NSProcessInfo.processInfo.processName ?: @"unknown",
        @"processID": @(NSProcessInfo.processInfo.processIdentifier),
        @"bundleIdentifier": bundleID,
        @"expectedMinecraftProcess": @([bundleID isEqualToString:@"com.mojang.minecraftpe"]),
        @"minecraftVersion": info[@"CFBundleShortVersionString"] ?: @"unknown",
        @"minecraftBuild": info[@"CFBundleVersion"] ?: @"unknown",
        @"expectedBuildFromSuppliedPayload": @BNE_EXPECTED_GAME_BUILD,
        @"operatingSystem": NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown",
        @"architecture": BNEArchitecture(),
        @"loadedRelatedImageBasenames": images,
        @"mainExecutableImagePresent": @([images containsObject:@"minecraftpe"]),
        @"clientLoaderImagePresent": @([images containsObject:@"ClientLoader.dylib"]),
        @"experimentalImagePresent": @([images containsObject:@"BedrockNetworkESP_Lab.dylib"]),
        @"javascriptCoreImagePresent": @([images containsObject:@"JavaScriptCore"]),
        @"installedScripts": BNEInstalledScripts(),
        @"scriptBridge": bridge,
        @"scriptLogEvidence": clientLogEvidence
    };
}

static NSDictionary *BNECommonReport(NSString *reason) {
    NSString *clientSession = [NSUserDefaults.standardUserDefaults
        stringForKey:@"ClientLoader.diagnostics.sessionID"] ?: @"unavailable";
    NSDate *clientSessionStart = [NSUserDefaults.standardUserDefaults
        objectForKey:@"ClientLoader.diagnostics.startedAt"];
    BOOL linkedSessionCurrent = clientSessionStart &&
        [[NSDate date] timeIntervalSinceDate:clientSessionStart] < 600.0;
    return @{
        @"schemaVersion": @1,
        @"generatedAt": BNEUTCNow(),
        @"sessionID": sSessionID ?: @"uninitialized",
        @"clientLoaderSessionID": clientSession,
        @"clientLoaderSessionLinkStatus": linkedSessionCurrent ? @"current" : @"missing-or-stale",
        @"buildID": @BNE_BUILD_REVISION,
        @"reportReason": reason ?: @"unspecified"
    };
}

static NSDictionary *BNEBuildManifest(void) {
    NSArray<NSString *> *images = BNERelatedLoadedImages();
    NSString *libraryHash = @"unavailable";
    NSString *clientLoaderHash = @"unavailable";
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *imageName = _dyld_get_image_name(index);
        NSString *baseName = BNEImageBaseName(imageName);
        if ([baseName isEqualToString:@"BedrockNetworkESP_Lab.dylib"]) {
            libraryHash = BNESHA256ForFile([NSString stringWithUTF8String:imageName]);
        } else if ([baseName isEqualToString:@"ClientLoader.dylib"]) {
            clientLoaderHash = BNESHA256ForFile([NSString stringWithUTF8String:imageName]);
        }
    }
    return @{
        @"sourceRevision": @BNE_BUILD_REVISION,
        @"buildTimestamp": @BNE_BUILD_TIMESTAMP,
        @"runtimeGeneratedAt": BNEUTCNow(),
        @"targetArchitecture": BNEArchitecture(),
        @"minimumIOS": @"15.0",
        @"expectedMinecraftBuild": @BNE_EXPECTED_GAME_BUILD,
        @"runtimeMinecraftBuild": BNEEnvironment()[@"minecraftBuild"] ?: @"unknown",
        @"libraryFilename": @"BedrockNetworkESP_Lab.dylib",
        @"loadedLibrarySHA256": libraryHash,
        @"clientLoaderLibraryFilename": @"ClientLoader.dylib",
        @"clientLoaderLibrarySHA256": clientLoaderHash,
        @"compiledFeatures": @[@"bounded-jsonl-diagnostics", @"source-independent-tracker",
            @"touch-through-overlay", @"camera-input-validation", @"no-network-decoder",
            @"no-game-memory-hook"]
    };
}

static NSDictionary *BNEReportForName(NSString *name, NSString *reason) {
    NSMutableDictionary *report = [BNECommonReport(reason) mutableCopy];
    if ([name isEqualToString:@"BuildManifest.json"]) {
        [report addEntriesFromDictionary:BNEBuildManifest()];
    } else if ([name isEqualToString:@"StartupReport.json"]) {
        report[@"environment"] = BNEEnvironment();
        report[@"stages"] = [sStages copy] ?: @[];
        report[@"status"] = [sStatuses copy] ?: @{};
        report[@"loaderMode"] = @"separate in-process dylib; startup uses UIKit scene/window lookup";
    } else if ([name isEqualToString:@"ESPDiagnostic.json"]) {
        report[@"renderer"] = @"BNEESPOverlay";
        report[@"renderMetrics"] = [sRenderMetrics copy] ?: @{};
        report[@"drawPolicy"] = @{
            @"requiresPositionedFreshSnapshot": @YES,
            @"requiresFreshCamera": @YES,
            @"fixturePositionsRendered": @NO,
            @"bounds": @"provisional 0.6 x 1.8 x 0.6 world units"
        };
    } else if ([name isEqualToString:@"GameDataDiagnostic.json"]) {
        report[@"sources"] = @{
            @"nativeEntitySource": @{@"status": @"unavailable", @"reason": @"No verified producer calls the lab snapshot-provider API."},
            @"camera": @{@"status": @"unavailable", @"reason": @"No verified game camera producer publishes a matrix."},
            @"entityRegistry": @{@"status": @"definitions-only", @"reason": @"A registry maps type metadata; it is not a live entity list."},
            @"clientLoaderJavaScript": @{@"status": @"separate-runtime", @"reason": @"ClientLoader's JavaScriptCore context is not the Minecraft Script API runtime."},
            @"behaviorPackScript": @{@"status": @"not-observed", @"reason": @"No enabled script pack or supported bridge was verified."}
        };
    } else if ([name isEqualToString:@"NetworkDiagnostic.json"]) {
        report[@"observation"] = @{
            @"status": @"not-implemented",
            @"transport": @"unknown",
            @"payloadReadability": @"unknown",
            @"entityPacketsDecoded": @NO,
            @"reason": @"No authorized controlled capture or protocol decoder is connected.",
            @"credentialsCollected": @NO
        };
    } else if ([name isEqualToString:@"SymbolResearch.json"]) {
        report[@"candidates"] = @[
            @{@"name": @"ScriptDimension::getEntities", @"evidence": @"String/binding metadata in supplied 1.26.33 static analysis", @"validatedCallable": @NO, @"confidence": @"candidate-only"},
            @{@"name": @"MinecraftCamera::ActiveCameraComponent", @"evidence": @"Type-name record in supplied binary", @"validatedAccessor": @NO, @"confidence": @"candidate-only"},
            @{@"name": @"CurrentViewProjectionMatrixUniform", @"evidence": @"Renderer uniform name; not a CPU matrix accessor", @"validatedAccessor": @NO, @"confidence": @"candidate-only"}
        ];
    }
    return report;
}

static BOOL BNEWriteJSONReport(NSString *fileName, NSDictionary *report, NSError **error) {
    NSURL *directory = [[[[BNEDiagnosticsDirectory() URLByAppendingPathComponent:@"exports" isDirectory:YES]
        URLByAppendingPathComponent:@"BedrockNetworkESP_Lab" isDirectory:YES] copy];
    if (!BNEEnsureDirectory(directory, error)) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) return NO;
    NSURL *fileURL = [directory URLByAppendingPathComponent:fileName];
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:error]) return NO;
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:fileURL.path error:error];
    return attributes && [attributes[NSFileSize] unsignedLongLongValue] == data.length;
}

void BNEInitializeDiagnostics(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sDiagnosticsLock = [NSRecursiveLock new];
        [sDiagnosticsLock lock];
        sSessionID = NSUUID.UUID.UUIDString;
        sStages = [NSMutableArray array];
        sStatuses = [NSMutableDictionary dictionary];
        sRenderMetrics = [NSMutableDictionary dictionary];
        sStatuses[@"entity"] = [@{@"state": @"unavailable", @"reason": @"No verified entity event source is connected."} mutableCopy];
        sStatuses[@"camera"] = [@{@"state": @"unavailable", @"reason": @"No verified active-camera producer is connected."} mutableCopy];
        sStatuses[@"network"] = [@{@"state": @"not-implemented", @"reason": @"No capture or packet decoder is active."} mutableCopy];
        NSDictionary *bridge = BNEBridgeProbe();
        sStatuses[@"clientMenuBridge"] = [@{
            @"state": [bridge[@"ClientMenuBridgeClassPresent"] boolValue] ? @"class-present" : @"unavailable",
            @"reason": bridge[@"scriptEvaluationReason"] ?: @"Bridge evaluation is not owned by this dylib.",
            @"probe": bridge
        } mutableCopy];
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
        sStatuses[@"targetProcess"] = [@{
            @"state": [bundleID isEqualToString:@"com.mojang.minecraftpe"] ? @"matched" : @"mismatch",
            @"bundleIdentifier": bundleID
        } mutableCopy];
        [sDiagnosticsLock unlock];
    });
}

NSString *BNECurrentSessionID(void) {
    BNEInitializeDiagnostics();
    [sDiagnosticsLock lock];
    NSString *sessionID = [sSessionID copy];
    [sDiagnosticsLock unlock];
    return sessionID;
}

void BNELogEvent(NSString *category,
                 NSString *stage,
                 NSString *message,
                 NSDictionary<NSString *,id> *fields) {
    BNEInitializeDiagnostics();
    NSDictionary *event = @{
        @"timestamp": BNEUTCNow(),
        @"sessionID": sSessionID ?: @"unknown",
        @"clientLoaderSessionID": [NSUserDefaults.standardUserDefaults
            stringForKey:@"ClientLoader.diagnostics.sessionID"] ?: @"unavailable",
        @"buildID": @BNE_BUILD_REVISION,
        @"category": category ?: @"RUNTIME",
        @"stage": stage ?: @"unspecified",
        @"message": message ?: @"",
        @"fields": fields ?: @{}
    };
    NSError *serializationError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:&serializationError];
    NSMutableData *line = [NSMutableData dataWithData:json ?: [NSData data]];
    const uint8_t newline = '\n';
    [line appendBytes:&newline length:1];
    BOOL synchronize = [[category uppercaseString] containsString:@"ERROR"] ||
        [[category uppercaseString] containsString:@"INIT"] ||
        [[category uppercaseString] containsString:@"EXPORT"];

    [sDiagnosticsLock lock];
    [sStages addObject:event];
    if (sStages.count > kBNEStageRecordLimit) {
        [sStages removeObjectsInRange:NSMakeRange(0, sStages.count - kBNEStageRecordLimit)];
    }
    NSError *writeError = serializationError;
    BOOL wrote = json && BNEAppendLogData(line, synchronize, &writeError);
    [sDiagnosticsLock unlock];

    NSLog(@"[%@] session=%@ stage=%@ %@",
          category ?: @"BNE_RUNTIME", sSessionID ?: @"unknown", stage ?: @"unspecified", message ?: @"");
    if (!wrote) {
        NSLog(@"[BNE_ERROR] native log write failed; fallback=system-log; error=%@",
              writeError.localizedDescription ?: @"unknown error");
    }
}

void BNELogDiagnostic(NSString *message) {
    BNELogEvent(@"BNE_RUNTIME", @"diagnostic", message, nil);
}

void BNEUpdateDiagnosticStatus(NSString *section,
                               NSString *key,
                               id value,
                               NSString *reason) {
    if (section.length == 0 || key.length == 0 || !value) return;
    BNEInitializeDiagnostics();
    [sDiagnosticsLock lock];
    NSMutableDictionary *entry = sStatuses[section];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        sStatuses[section] = entry;
    }
    entry[key] = value;
    if (reason.length > 0) entry[@"reason"] = reason;
    [sDiagnosticsLock unlock];
    BNELogEvent(@"BNE_RUNTIME", [NSString stringWithFormat:@"status.%@.%@", section, key],
                [NSString stringWithFormat:@"%@=%@", key, value], nil);
}

void BNERecordRenderFrame(NSDictionary<NSString *,NSNumber *> *metrics) {
    BNEInitializeDiagnostics();
    [sDiagnosticsLock lock];
    sRenderFrameCount++;
    [sRenderMetrics addEntriesFromDictionary:metrics ?: @{}];
    sRenderMetrics[@"frameCount"] = @(sRenderFrameCount);
    BOOL milestone = (sRenderFrameCount % 300) == 0;
    NSDictionary *snapshot = [sRenderMetrics copy];
    [sDiagnosticsLock unlock];
    if (!milestone) return;
    BNELogEvent(@"BNE_ESP", @"render.milestone", @"Overlay frame summary", snapshot);
    BNEFlushDiagnosticReports(@"render-milestone");
}

void BNEFlushDiagnosticReports(NSString *reason) {
    BNEInitializeDiagnostics();
    NSArray<NSString *> *names = @[
        @"StartupReport.json", @"ESPDiagnostic.json", @"GameDataDiagnostic.json",
        @"NetworkDiagnostic.json", @"SymbolResearch.json", @"BuildManifest.json"
    ];
    [sDiagnosticsLock lock];
    for (NSString *name in names) {
        NSError *error = nil;
        NSDictionary *report = BNEReportForName(name, reason);
        BOOL success = BNEWriteJSONReport(name, report, &error);
        if (success) {
            BNELogEvent(@"BNE_EXPORT", @"report.write", @"Diagnostic report written and size-verified",
                @{@"file": name, @"status": @"written"});
        } else {
            NSLog(@"[BNE_ERROR] session=%@ stage=report.write file=%@ status=failed error=%@; fallback=ClientLoader.log/system-log",
                  sSessionID ?: @"unknown", name, error.localizedDescription ?: @"unknown error");
            NSDictionary *failure = @{
                @"timestamp": BNEUTCNow(),
                @"sessionID": sSessionID ?: @"unknown",
                @"buildID": @BNE_BUILD_REVISION,
                @"category": @"BNE_ERROR",
                @"stage": @"report.write",
                @"message": @"Diagnostic report write failed",
                @"fields": @{@"file": name, @"error": error.localizedDescription ?: @"unknown error"}
            };
            NSData *failureJSON = [NSJSONSerialization dataWithJSONObject:failure options:0 error:nil];
            NSMutableData *line = failureJSON ? [failureJSON mutableCopy] : [NSMutableData data];
            const uint8_t newline = '\n';
            [line appendBytes:&newline length:1];
            NSError *logError = nil;
            if (failureJSON) BNEAppendLogData(line, YES, &logError);
        }
    }
    [sDiagnosticsLock unlock];
}