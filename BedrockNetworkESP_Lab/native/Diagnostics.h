#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void BNEInitializeDiagnostics(void);
void BNELogDiagnostic(NSString *message);
void BNELogEvent(NSString *category,
				 NSString *stage,
				 NSString *message,
				 nullable NSDictionary<NSString *, id> *fields);
void BNEUpdateDiagnosticStatus(NSString *section,
							   NSString *key,
							   id value,
							   NSString *reason);
void BNERecordRenderFrame(NSDictionary<NSString *, NSNumber *> *metrics);
void BNEFlushDiagnosticReports(NSString *reason);
NSString *BNECurrentSessionID(void);

NS_ASSUME_NONNULL_END