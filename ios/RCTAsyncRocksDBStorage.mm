// Copyright 2004-present Facebook. All Rights Reserved.

#import "RCTAsyncRocksDBStorage.h"

#include <string>

#import <Foundation/Foundation.h>

#import "React/RCTConvert.h"
#import "React/RCTLog.h"
#import "React/RCTUtils.h"

#if !TARGET_IPHONE_SIMULATOR
#define ROCKSDB_LITE 1
#define IOS_CROSS_COMPILE 1

#include <rocksdb/db.h>
#include <rocksdb/merge_operator.h>
#include <rocksdb/options.h>
#include <rocksdb/slice.h>
#include <rocksdb/status.h>

static NSString *const RKAsyncRocksDBStorageDirectory = @"RKAsyncRocksDBStorage";

namespace {
    rocksdb::Slice SliceFromString(NSString *string)
    {
        const char* chars = [string UTF8String];
        NSUInteger len = strlen(chars);
        return rocksdb::Slice(chars, len);
    }

    void deepMergeInto(NSMutableDictionary *output, NSDictionary *input) {
        for (NSString *key in input) {
            id inputValue = input[key];
            if ([inputValue isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *nestedOutput;
                id outputValue = output[key];
                if ([outputValue isKindOfClass:[NSMutableDictionary class]]) {
                    nestedOutput = outputValue;
                } else {
                    if ([outputValue isKindOfClass:[NSDictionary class]]) {
                        nestedOutput = [outputValue mutableCopy];
                    } else {
                        output[key] = [inputValue copy];
                    }
                }
                if (nestedOutput) {
                    deepMergeInto(nestedOutput, inputValue);
                    output[key] = nestedOutput;
                }
            } else {
                output[key] = inputValue;
            }
        }
    }

    class JSONMergeOperator : public rocksdb::AssociativeMergeOperator {
    public:
        virtual bool Merge(const rocksdb::Slice &key,
                           const rocksdb::Slice *existingValue,
                           const rocksdb::Slice &newValue,
                           std::string *mergedValue,
                           rocksdb::Logger *logger) const override {

            NSError *error;
            NSMutableDictionary *existingDict;
            if (existingValue) {
                NSString *existingString = [NSString stringWithUTF8String:existingValue->data()];
                existingDict = RCTJSONParseMutable(existingString, &error);
                if (error) {
                    RCTLogError(@"Parse error in RKAsyncRocksDBStorage merge operation.  Error:\n%@\nString:\n%@", error, existingString);
                    return false;
                }
            } else {
                // Nothing to merge, just assign the string without even parsing.
                mergedValue->assign(newValue.data(), newValue.size());
                return true;
            }

            NSString *newString = [NSString stringWithUTF8String:newValue.data()];
            NSMutableDictionary *newDict = RCTJSONParse(newString, &error);
            deepMergeInto(existingDict, newDict);
            NSString *mergedNSString = RCTJSONStringify(existingDict, &error);
            mergedValue->assign([mergedNSString UTF8String], [mergedNSString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
            return true;
        }

        virtual const char *Name() const override {
            return "JSONMergeOperator";
        }
    };
}  // namespace

@implementation RCTAsyncRocksDBStorage
{
    rocksdb::DB *_db;
}

@synthesize methodQueue = _methodQueue;

static NSString *RCTGetStorageDirectory()
{
    static NSString *storageDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        storageDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        storageDirectory = [storageDirectory stringByAppendingPathComponent:RKAsyncRocksDBStorageDirectory];
    });
    return storageDirectory;
}

RCT_EXPORT_MODULE()

- (void)dealloc
{
    if (_db) {
        delete _db;
    }
}

- (BOOL)ensureDirectorySetup:(NSError **)error
{
    if (_db) {
        return YES;
    }
    rocksdb::Options options;
    options.create_if_missing = true;
    RCTAssert(error != nil, @"Must provide error pointer.");
    rocksdb::Status status = rocksdb::DB::Open(options, [RCTGetStorageDirectory() UTF8String], &_db);
    if (!status.ok() || !_db) {
        RCTLogError(@"Failed to open db at path %@.\n\nRocksDB Status: %s.\n\nNSError: %@", RCTGetStorageDirectory(), status.ToString().c_str(), *error);
        *error = [NSError errorWithDomain:@"rocksdb" code:100 userInfo:@{NSLocalizedDescriptionKey:@"Failed to open db"}];
        return NO;
    }
    return YES;
}


RCT_EXPORT_METHOD(multiGet:(NSStringArray *)keys
                  callback:(RCTResponseSenderBlock)callback)
{
    NSDictionary *errorOut;
    NSError *error;
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:keys.count];
    BOOL success = [self ensureDirectorySetup:&error];
    if (!success || error) {
        errorOut = RCTMakeError(@"Failed to setup directory", nil, nil);
    } else {
        std::vector<rocksdb::Slice> sliceKeys;
        sliceKeys.reserve(keys.count);
        for (NSString *key in keys) {
            sliceKeys.push_back(SliceFromString(key));
        }
        std::vector<std::string> values;
        std::vector<rocksdb::Status> statuses = _db->MultiGet(rocksdb::ReadOptions(), sliceKeys, &values);
        RCTAssert(values.size() == keys.count, @"Key and value arrays should be equal size");
        for (size_t ii = 0; ii < values.size(); ii++) {
            id value;
            auto status = statuses[ii];
            if (!status.IsNotFound()) {
                if (!status.ok()) {
                    errorOut = RCTMakeError(@"RKAsyncRocksDB failed getting key: ", keys[ii], keys[ii]);
                } else {
                    value = [NSString stringWithUTF8String:values[ii].c_str()];
                }
            } else {
                status = status;
            }

            if (value == nil) {
                value = [NSNull null];
            }

            [result addObject:@[keys[ii], value]];
        }
    }
    if (callback) {
        callback(@[errorOut ? @[errorOut] : [NSNull null], result]);
    }
}

// kvPairs is a list of key-value pairs, e.g. @[@[key1, val1], @[key2, val2], ...]
// TODO: write custom RCTConvert category method for kvPairs
RCT_EXPORT_METHOD(multiSet:(NSArray *)kvPairs
                  callback:(RCTResponseSenderBlock)callback)
{
    auto updates = rocksdb::WriteBatch();
    for (NSArray *kvPair in kvPairs) {
        NSStringArray *pair = [RCTConvert NSStringArray:kvPair];
        if (pair.count == 2) {
            updates.Put(SliceFromString(pair[0]), SliceFromString(pair[1]));
        } else {
            if (callback) {
                callback(@[@[RCTMakeAndLogError(@"Input must be an array of [key, value] arrays, got: ", kvPair, nil)]]);
            }
            return;
        }
    }
    [self _performWriteBatch:&updates callback:callback];
}

RCT_EXPORT_METHOD(multiMerge:(NSArray *)kvPairs
                  callback:(RCTResponseSenderBlock)callback)
{
    auto updates = rocksdb::WriteBatch();
    for (NSArray *kvPair in kvPairs) {
        NSStringArray *pair = [RCTConvert NSStringArray:kvPair];
        if (pair.count == 2) {
            updates.Merge(SliceFromString(pair[0]), SliceFromString(pair[1]));
        } else {
            if (callback) {
                callback(@[@[RCTMakeAndLogError(@"Input must be an array of [key, value] arrays, got: ", kvPair, nil)]]);
            }
            return;
        }
    }
    [self _performWriteBatch:&updates callback:callback];
}

RCT_EXPORT_METHOD(multiRemove:(NSArray *)keys
                  callback:(RCTResponseSenderBlock)callback)
{
    auto updates = rocksdb::WriteBatch();
    for (NSString *key in keys) {
        updates.Delete(SliceFromString(key));
    }
    [self _performWriteBatch:&updates callback:callback];
}

// TODO (#5906496): There's a lot of duplication in the error handling code here - can we refactor this?

- (void)_performWriteBatch:(rocksdb::WriteBatch *)updates callback:(RCTResponseSenderBlock)callback
{
    NSDictionary *errorOut;
    NSError *error;
    BOOL success = [self ensureDirectorySetup:&error];
    if (!success || error) {
        errorOut = RCTMakeError(@"Failed to setup storage", nil, nil);
    } else {
        rocksdb::Status status = _db->Write(rocksdb::WriteOptions(), updates);
        if (!status.ok()) {
            errorOut = RCTMakeError(@"Failed to write to RocksDB database.", nil, nil);
        }
    }
    if (callback) {
        callback(@[errorOut ? @[errorOut] : [NSNull null]]);
    }
}

RCT_EXPORT_METHOD(clear:(RCTResponseSenderBlock)callback)
{
    NSError *error;
    NSDictionary *errorOut;
    BOOL success = [self ensureDirectorySetup:&error];
    if (!success || error) {
        errorOut = RCTMakeError(@"Failed to setup storage", nil, nil);
    } else {
        delete _db;
        NSDictionary *errorOut;
        NSString* dir = RCTGetStorageDirectory();
        rocksdb::Status status = rocksdb::DestroyDB([dir UTF8String], rocksdb::Options());
        if (!status.ok()) {
            errorOut = RCTMakeError(@"RocksDB:clear failed to destroy db at path ", dir, nil);
        }

        _db = nil;
    }

    if (callback) {
        callback(@[errorOut ?: [NSNull null]]);
    }
}

RCT_EXPORT_METHOD(getAllKeysWithPrefix:(NSString*) prefix callback:(RCTResponseSenderBlock)callback)
{
  NSError *error;
  NSMutableArray *keys = [NSMutableArray new];
  NSInteger prefixLength = [prefix length];
  NSDictionary *errorOut;
  BOOL success = [self ensureDirectorySetup:&error];
  if (!success || error) {
    errorOut = RCTMakeError(@"Failed to setup storage", nil, nil);
  } else {
    rocksdb::Iterator *it = _db->NewIterator(rocksdb::ReadOptions());
    rocksdb::Slice start = [prefix UTF8String];
    for (it->Seek(start); it->Valid() && it->key().starts_with(start); it->Next()) {
      std::string rawKey = it->key().ToString();// [NSString stringWithUTF8String:chars];
      NSString* key = [[NSString stringWithFormat:@"%s", rawKey.c_str()] substringFromIndex:prefixLength];
      [keys addObject:key];
    }
  }
  if (callback) {
    callback(@[errorOut ?: [NSNull null], keys]);
  }
}

RCT_EXPORT_METHOD(getAllKeys:(RCTResponseSenderBlock)callback)
{
    NSError *error;
    NSMutableArray *allKeys = [NSMutableArray new];
    NSDictionary *errorOut;
    BOOL success = [self ensureDirectorySetup:&error];
    if (!success || error) {
        errorOut = RCTMakeError(@"Failed to setup storage", nil, nil);
    } else {
        rocksdb::Iterator *it = _db->NewIterator(rocksdb::ReadOptions());
        for (it->SeekToFirst(); it->Valid(); it->Next()) {
            std::string rawKey = it->key().ToString();// [NSString stringWithUTF8String:chars];
            NSString* key = [NSString stringWithFormat:@"%s", rawKey.c_str()];
            [allKeys addObject:key];
        }
    }
    if (callback) {
        callback(@[errorOut ?: [NSNull null], allKeys]);
    }
}

@end
#endif
