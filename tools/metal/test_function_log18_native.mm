#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface PrismelTestFunctionLogLocation : NSObject <MTLFunctionLogDebugLocation> {
  NSURL *_URL;
  NSString *_functionName;
}
@property(nonatomic, strong, nullable) NSURL *URL;
@property(nonatomic) NSUInteger line;
@property(nonatomic) NSUInteger column;
- (void)setTestFunctionName:(nullable NSString *)name;
@end
@implementation PrismelTestFunctionLogLocation
- (NSString *)functionName { return _functionName; }
- (void)setTestFunctionName:(NSString *)name { _functionName = [name copy]; }
@end

@interface PrismelTestFunctionLog : NSObject <MTLFunctionLog> {
  NSString *_encoderLabel;
}
@property(nonatomic) MTLFunctionLogType type;
@property(nonatomic, strong, nullable) PrismelTestFunctionLogLocation *debugLocation;
@property(nonatomic, strong, nullable) id<MTLFunction> function;
- (void)setTestEncoderLabel:(nullable NSString *)label;
@end
@implementation PrismelTestFunctionLog
- (NSString *)encoderLabel { return _encoderLabel; }
- (void)setTestEncoderLabel:(NSString *)label { _encoderLabel = [label copy]; }
@end

static NSString *nullable_url_snapshot(id<MTLFunctionLogDebugLocation> location) {
  return [location.URL.absoluteString copy];
}

int main(void) {
  NSString *url_snapshot = nil;
  NSString *name_snapshot = nil;
  NSString *label_snapshot = nil;
  @autoreleasepool {
    PrismelTestFunctionLogLocation *location = [PrismelTestFunctionLogLocation new];
    location.URL = [NSURL URLWithString:@"file:///tmp/prismel-%CE%BB.metal"];
    [location setTestFunctionName:@"kernel_λ"];
    location.line = 17;
    location.column = 9;
    PrismelTestFunctionLog *log = [PrismelTestFunctionLog new];
    log.type = MTLFunctionLogTypeValidation;
    log.debugLocation = location;
    [log setTestEncoderLabel:@"compute_λ"];
    log.function = nil;
    if (log.type != MTLFunctionLogTypeValidation || log.function != nil) return 1;
    if (log.debugLocation.line != 17 || log.debugLocation.column != 9) return 2;
    url_snapshot = nullable_url_snapshot(log.debugLocation);
    name_snapshot = [log.debugLocation.functionName copy];
    label_snapshot = [log.encoderLabel copy];
  }
  /* Snapshots outlive the callback/autorelease scope that supplied the log. */
  if (![url_snapshot isEqualToString:@"file:///tmp/prismel-%CE%BB.metal"]) return 3;
  if (![name_snapshot isEqualToString:@"kernel_λ"]) return 4;
  if (![label_snapshot isEqualToString:@"compute_λ"]) return 5;
  @autoreleasepool {
    PrismelTestFunctionLog *nullable = [PrismelTestFunctionLog new];
    if (nullable.debugLocation != nil || nullable.encoderLabel != nil ||
        nullable.function != nil || nullable_url_snapshot(nil) != nil) return 6;
  }
  return 0;
}
