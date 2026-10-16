#import <UIKit/UIKit.h>

#import "CameraDataSource.h"
#import "../src/entity/BNEEntityTracker.h"

NS_ASSUME_NONNULL_BEGIN

@interface BNEESPOverlay : UIView
@property(nonatomic) double maximumRenderDistance;
@property(nonatomic) BOOL showsNamesAndDistance;
@property(nonatomic, copy) NSArray<NSString *> *includedTypeIdentifiers;

- (void)updateWithSnapshot:(nullable const BNESnapshot *)snapshot
                    camera:(nullable const BNECameraSnapshot *)camera;

@end

NS_ASSUME_NONNULL_END