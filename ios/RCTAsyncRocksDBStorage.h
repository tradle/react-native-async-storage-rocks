#import "React/RCTBridgeModule.h"

@interface RCTAsyncRocksDBStorage : NSObject <RCTBridgeModule>

- (void)multiGet:(NSArray *)keys callback:(RCTResponseSenderBlock)callback;
- (void)multiSet:(NSArray *)kvPairs callback:(RCTResponseSenderBlock)callback;
- (void)multiRemove:(NSArray *)keys callback:(RCTResponseSenderBlock)callback;
- (void)clear:(RCTResponseSenderBlock)callback;
- (void)getAllKeys:(RCTResponseSenderBlock)callback;
- (void)getAllKeysWithPrefix:(NSString*) prefix callback:(RCTResponseSenderBlock)callback;
- (void)getAllKeysInRange:(NSString*) lte gte:(NSString*) gte callback:(RCTResponseSenderBlock)callback;

@end
