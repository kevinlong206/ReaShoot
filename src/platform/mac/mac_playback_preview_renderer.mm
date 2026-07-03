#import "mac_playback_preview_renderer.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include <cmath>

@interface ReaShootMacPlaybackPreviewRenderer ()
@property(nonatomic, weak) NSView *containerView;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, copy) NSString *activePath;
@property(nonatomic, assign) CFTimeInterval lastSeekHostTime;
@property(nonatomic, assign) BOOL visible;
@end

@implementation ReaShootMacPlaybackPreviewRenderer

- (instancetype)initWithContainerView:(NSView *)containerView {
  self = [super init];
  if (self) {
    _containerView = containerView;
  }
  return self;
}

- (void)showPath:(NSString *)path
       itemStart:(double)itemStart
    sourceOffset:(double)sourceOffset
 projectPosition:(double)projectPosition {
  if (path.length == 0 || !self.containerView) {
    return;
  }

  const BOOL switchedSource = !self.player || ![self.activePath isEqualToString:path];
  if (switchedSource) {
    self.activePath = path;
    self.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    self.player.automaticallyWaitsToMinimizeStalling = NO;
    if (!self.playerLayer) {
      self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
      self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
      self.playerLayer.frame = self.containerView.bounds;
      self.playerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
      [self.containerView.layer addSublayer:self.playerLayer];
    } else {
      self.playerLayer.player = self.player;
    }
    self.player.muted = YES;
    self.player.volume = 0.0f;
  }

  self.playerLayer.hidden = NO;

  const double sourceTime = projectPosition - itemStart + sourceOffset;
  CMTime targetTime = CMTimeMakeWithSeconds(sourceTime > 0.0 ? sourceTime : 0.0, 600);
  const double currentTime = CMTimeGetSeconds(self.player.currentTime);
  const CFTimeInterval now = CACurrentMediaTime();
  const bool forceSeek = switchedSource || !self.visible || !std::isfinite(currentTime);
  const bool drifted = std::isfinite(currentTime) && std::fabs(currentTime - sourceTime) > 0.50;
  if (forceSeek || (drifted && now - self.lastSeekHostTime > 1.0)) {
    const CMTime tolerance = forceSeek ? kCMTimeZero : CMTimeMakeWithSeconds(0.05, 600);
    [self.player seekToTime:targetTime toleranceBefore:tolerance toleranceAfter:tolerance];
    self.lastSeekHostTime = now;
  }
  if (self.player.rate != 1.0f) {
    [self.player play];
  }
  self.visible = YES;
}

- (void)hide {
  [self.player pause];
  self.playerLayer.hidden = YES;
  self.visible = NO;
}

@end
