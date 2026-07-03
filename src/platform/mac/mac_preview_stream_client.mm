#import "mac_preview_stream_client.h"

@interface ReaShootMacPreviewStreamClient ()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionWebSocketTask *task;
@property(nonatomic, copy) void (^onData)(NSData *accessUnit);
@property(nonatomic, copy) void (^onActive)(void);
@property(nonatomic, copy) void (^onError)(NSError *error);
@property(nonatomic, assign) BOOL active;
@end

@implementation ReaShootMacPreviewStreamClient

- (BOOL)isRunning {
  return self.task != nil;
}

- (BOOL)startWithHost:(NSString *)host
                 port:(NSInteger)port
                 path:(NSString *)path
                token:(NSString *)token
               onData:(void (^)(NSData *accessUnit))onData
             onActive:(void (^)(void))onActive
              onError:(void (^)(NSError *error))onError {
  [self stop];

  NSURLComponents *components = [[NSURLComponents alloc] init];
  components.scheme = @"ws";
  components.host = host;
  components.port = @(port > 0 ? port : 8789);
  components.path = path.length > 0 ? path : @"/preview";
  components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"token" value:token ?: @""] ];
  NSURL *url = components.URL;
  if (!url) {
    return NO;
  }

  self.onData = onData;
  self.onActive = onActive;
  self.onError = onError;
  self.active = NO;
  self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
  self.task = [self.session webSocketTaskWithURL:url];
  [self.task resume];
  [self receiveNextMessageForTask:self.task];
  return YES;
}

- (void)stop {
  [self.task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
  self.task = nil;
  [self.session invalidateAndCancel];
  self.session = nil;
  self.onData = nil;
  self.onActive = nil;
  self.onError = nil;
  self.active = NO;
}

- (void)receiveNextMessageForTask:(NSURLSessionWebSocketTask *)task {
  if (!task) {
    return;
  }
  __weak ReaShootMacPreviewStreamClient *weakSelf = self;
  [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      ReaShootMacPreviewStreamClient *strongSelf = weakSelf;
      if (!strongSelf || task != strongSelf.task) {
        return;
      }
      if (error) {
        void (^onError)(NSError *) = strongSelf.onError;
        [strongSelf stop];
        if (onError) {
          onError(error);
        }
        return;
      }
      if (!strongSelf.active) {
        strongSelf.active = YES;
        if (strongSelf.onActive) {
          strongSelf.onActive();
        }
      }
      if (message.type == NSURLSessionWebSocketMessageTypeData && strongSelf.onData) {
        strongSelf.onData(message.data);
      }
      [strongSelf receiveNextMessageForTask:task];
    });
  }];
}

@end
