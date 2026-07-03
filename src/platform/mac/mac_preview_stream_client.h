#pragma once

#include "../../core/platform_interfaces.h"

#import <Foundation/Foundation.h>

#include <memory>

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

namespace reashoot::platform::mac {

std::unique_ptr<core::PreviewStreamClient> createPreviewStreamClient();

} // namespace reashoot::platform::mac
