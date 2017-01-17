#import "React/RCTBridgeModule.h"

@interface RCTAsyncRocksDBStorage : NSObject <RCTBridgeModule>

- (void)multiGet:(NSArray *)keys callback:(RCTResponseSenderBlock)callback;
- (void)multiSet:(NSArray *)kvPairs callback:(RCTResponseSenderBlock)callback;
- (void)multiRemove:(NSArray *)keys callback:(RCTResponseSenderBlock)callback;
- (void)clear:(RCTResponseSenderBlock)callback;
- (void)getAllKeys:(RCTResponseSenderBlock)callback;

@end
