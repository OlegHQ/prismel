#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <cmath>
#include <memory>

@interface PrismelTestDrawable : NSObject <MTLDrawable>
@property(nonatomic) NSUInteger drawableID;
@property(nonatomic) CFTimeInterval presentedTime;
@property(nonatomic, copy) MTLDrawablePresentedHandler handler;
@property(nonatomic) NSInteger scheduleMode;
@property(nonatomic) CFTimeInterval scheduleTime;
@end
@implementation PrismelTestDrawable
- (void)present { self.scheduleMode = 0; self.presentedTime = 1.0;
  if (self.handler) self.handler(self); }
- (void)presentAtTime:(CFTimeInterval)value { self.scheduleMode = 1;
  self.scheduleTime = value; self.presentedTime = value; if (self.handler) self.handler(self); }
- (void)presentAfterMinimumDuration:(CFTimeInterval)value { self.scheduleMode = 2;
  self.scheduleTime = value; self.presentedTime = value; if (self.handler) self.handler(self); }
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)handler { self.handler = handler; }
@end

int main() { @autoreleasepool {
  PrismelTestDrawable *drawable = [PrismelTestDrawable new]; drawable.drawableID = 17;
  __weak PrismelTestDrawable *weak = drawable;
  auto calls = std::make_shared<std::atomic<int>>(0);
  auto delivered = std::make_shared<std::atomic<bool>>(false);
  __block NSUInteger identifier = 0;
  [drawable addPresentedHandler:^(id<MTLDrawable> completed) {
    bool expected = false;
    if (delivered->compare_exchange_strong(expected, true)) {
      calls->fetch_add(1); identifier = completed.drawableID;
    }
  }];
  [drawable presentAtTime:2.5]; drawable.handler(drawable);
  if (calls->load() != 1 || identifier != 17 || drawable.scheduleMode != 1
      || drawable.presentedTime != 2.5) return 1;
  if (!std::isfinite(drawable.presentedTime) || drawable.presentedTime < 0.0) return 2;
  __strong PrismelTestDrawable *parent = drawable; drawable = nil;
  if (weak == nil || parent.drawableID != 17) return 3;
  parent.handler = nil; parent = nil;
  if (weak != nil) return 4;
  return 0;
} }
