#import "mac_preview_stream_client.h"

#include <memory>
#include <utility>
#include <vector>

@interface ReaShootMacPreviewStreamClient ()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionWebSocketTask *task;
@property(nonatomic, copy) void (^onData)(NSData *accessUnit);
@property(nonatomic, copy) void (^onText)(NSString *text);
@property(nonatomic, copy) void (^onActive)(void);
@property(nonatomic, copy) void (^onError)(NSError *error);
@property(nonatomic, strong) dispatch_queue_t processingQueue;
@property(nonatomic, assign) BOOL active;
@end

namespace reashoot::platform::mac {

namespace {

void performOnMainRunLoopCommonModes(dispatch_block_t block) {
  if (!block) {
    return;
  }
  if ([NSThread isMainThread]) {
    block();
    return;
  }
  CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, block);
  CFRunLoopWakeUp(CFRunLoopGetMain());
}

class MacPreviewStreamClient final : public core::PreviewStreamClient {
public:
  MacPreviewStreamClient() : client_([[ReaShootMacPreviewStreamClient alloc] init]) {}

  bool isRunning() const override { return [client_ isRunning]; }

  bool start(const core::PreviewStreamRequest &request,
             core::BinaryDataCallback onData,
             core::TextDataCallback onText,
             core::VoidCallback onActive,
             core::ErrorCallback onError) override {
    return [client_ startWithHost:[NSString stringWithUTF8String:request.host.c_str()]
                             port:request.port
                             path:[NSString stringWithUTF8String:request.path.c_str()]
                            token:[NSString stringWithUTF8String:request.token.c_str()]
                           onData:^(NSData *accessUnit) {
      if (!onData || accessUnit.length == 0) {
        return;
      }
      const auto *bytes = static_cast<const uint8_t *>(accessUnit.bytes);
      onData(std::vector<uint8_t>(bytes, bytes + accessUnit.length));
    }
                          onText:^(NSString *text) {
      if (onText) {
        onText(text.UTF8String ?: "");
      }
    }
                         onActive:^{
      if (onActive) {
        onActive();
      }
    }
                          onError:^(NSError *error) {
      if (onError) {
        onError(error.localizedDescription.UTF8String ?: "Preview stream failed");
      }
    }];
  }

  void stop() override { [client_ stop]; }

private:
  __strong ReaShootMacPreviewStreamClient *client_ = nil;
};

} // namespace

std::unique_ptr<core::PreviewStreamClient> createPreviewStreamClient() {
  return std::make_unique<MacPreviewStreamClient>();
}

} // namespace reashoot::platform::mac

@implementation ReaShootMacPreviewStreamClient

- (BOOL)isRunning {
  return self.task != nil;
}

- (BOOL)startWithHost:(NSString *)host
                 port:(NSInteger)port
                 path:(NSString *)path
                token:(NSString *)token
               onData:(void (^)(NSData *accessUnit))onData
               onText:(void (^)(NSString *text))onText
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
  self.onText = onText;
  self.onActive = onActive;
  self.onError = onError;
  self.active = NO;
  self.processingQueue = dispatch_queue_create("com.kevinlong.reashoot.preview-stream-client", DISPATCH_QUEUE_SERIAL);
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
  self.onText = nil;
  self.onActive = nil;
  self.onError = nil;
  self.processingQueue = nil;
  self.active = NO;
}

- (void)receiveNextMessageForTask:(NSURLSessionWebSocketTask *)task {
  if (!task) {
    return;
  }
  __weak ReaShootMacPreviewStreamClient *weakSelf = self;
  [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
    ReaShootMacPreviewStreamClient *strongSelf = weakSelf;
    if (!strongSelf || task != strongSelf.task) {
      return;
    }
    if (error) {
      reashoot::platform::mac::performOnMainRunLoopCommonModes(^{
        ReaShootMacPreviewStreamClient *mainSelf = weakSelf;
        if (!mainSelf || task != mainSelf.task) {
          return;
        }
        void (^onError)(NSError *) = mainSelf.onError;
        [mainSelf stop];
        if (onError) {
          onError(error);
        }
      });
      return;
    }
    if (!strongSelf.active) {
      reashoot::platform::mac::performOnMainRunLoopCommonModes(^{
        ReaShootMacPreviewStreamClient *mainSelf = weakSelf;
        if (!mainSelf || task != mainSelf.task || mainSelf.active) {
          return;
        }
        mainSelf.active = YES;
        if (mainSelf.onActive) {
          mainSelf.onActive();
        }
      });
    }

    if (message.type == NSURLSessionWebSocketMessageTypeData && strongSelf.onData) {
      NSData *data = message.data;
      dispatch_queue_t processingQueue = strongSelf.processingQueue;
      if (!processingQueue) {
        return;
      }
      dispatch_async(processingQueue, ^{
        ReaShootMacPreviewStreamClient *processingSelf = weakSelf;
        if (!processingSelf || task != processingSelf.task) {
          return;
        }
        void (^onData)(NSData *) = processingSelf.onData;
        if (onData && data.length > 0) {
          onData(data);
        }
        [processingSelf receiveNextMessageForTask:task];
      });
      return;
    }

    reashoot::platform::mac::performOnMainRunLoopCommonModes(^{
      ReaShootMacPreviewStreamClient *mainSelf = weakSelf;
      if (!mainSelf || task != mainSelf.task) {
        return;
      }
      if (!mainSelf.active) {
        mainSelf.active = YES;
        if (mainSelf.onActive) {
          mainSelf.onActive();
        }
      }
      if (message.type == NSURLSessionWebSocketMessageTypeString && mainSelf.onText) {
        mainSelf.onText(message.string);
      }
      [mainSelf receiveNextMessageForTask:task];
    });
  }];
}

@end
