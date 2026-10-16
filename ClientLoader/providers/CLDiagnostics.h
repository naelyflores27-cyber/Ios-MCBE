#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLDiagnostics : NSObject
+ (void)configureWithSessionID:(NSString *)sessionID
                                 buildRevision:(NSString *)buildRevision
                                 buildTimestamp:(NSString *)buildTimestamp;
+ (void)recordEvent:(NSString *)category
                            stage:(NSString *)stage
                        message:(NSString *)message
                         fields:(nullable NSDictionary<NSString *, id> *)fields;
+ (void)recordESPFrame:(NSDictionary<NSString *, NSNumber *> *)metrics;
+ (NSDictionary *)runtimeReport;
+ (void)recordError:(NSString *)message;
+ (nullable NSString *)writeRuntimeReportToDocumentsFile:(NSString *)fileName
                                                   error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
