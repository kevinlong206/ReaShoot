#pragma once

#import <Foundation/Foundation.h>

@interface ReaShootMacPreviewStreamClient : NSObject
- (BOOL)isRunning;
- (BOOL)startWithHost:(NSString *)host
                 port:(NSInteger)port
                 path:(NSString *)path
                token:(NSString *)token
               onData:(void (^)(NSData *accessUnit))onData
             onActive:(void (^)(void))onActive
              onError:(void (^)(NSError *error))onError;
- (void)stop;
@end
