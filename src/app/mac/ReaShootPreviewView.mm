#import "ReaShootPreviewView.h"

#include <algorithm>

@implementation ReaShootPreviewView {
  std::vector<uint8_t> _pixels;
  int _frameWidth;
  int _frameHeight;
  int _frameStride;
  int _displayWidth;
  int _displayHeight;
  NSString *_emptyMessage;
}

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;
    _emptyMessage = @"No paired iPhone.";
  }
  return self;
}

- (void)setFramePixels:(std::vector<uint8_t>)pixels width:(int)width height:(int)height stride:(int)stride {
  _pixels = std::move(pixels);
  _frameWidth = width;
  _frameHeight = height;
  _frameStride = stride;
  _displayWidth = width;
  _displayHeight = height;
  [self setNeedsDisplay:YES];
}

- (void)setDisplaySizeWithWidth:(int)width height:(int)height {
  _displayWidth = width;
  _displayHeight = height;
  [self setNeedsDisplay:YES];
}

- (void)clearFrameWithMessage:(NSString *)message {
  _pixels.clear();
  _frameWidth = 0;
  _frameHeight = 0;
  _frameStride = 0;
  _emptyMessage = [message copy] ?: @"No preview stream.";
  [self setNeedsDisplay:YES];
}

- (void)setEmptyMessage:(NSString *)message {
  _emptyMessage = [message copy] ?: @"No preview stream.";
  if (_pixels.empty()) {
    [self setNeedsDisplay:YES];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [NSColor.blackColor setFill];
  NSRectFill(dirtyRect);
  if (_pixels.empty() || _frameWidth <= 0 || _frameHeight <= 0 || _frameStride <= 0) {
    NSString *message = _emptyMessage.length > 0 ? _emptyMessage : @"No preview stream.";
    NSDictionary *attributes = @{
      NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
      NSFontAttributeName : [NSFont systemFontOfSize:18 weight:NSFontWeightMedium],
    };
    NSSize textSize = [message sizeWithAttributes:attributes];
    NSPoint point = NSMakePoint(std::max<CGFloat>(18, (self.bounds.size.width - textSize.width) * 0.5),
                                std::max<CGFloat>(18, (self.bounds.size.height - textSize.height) * 0.5));
    [message drawAtPoint:point withAttributes:attributes];
    return;
  }

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, _pixels.data(), _pixels.size(), nullptr);
  CGImageRef image = CGImageCreate(_frameWidth,
                                   _frameHeight,
                                   8,
                                   32,
                                   _frameStride,
                                   colorSpace,
                                   kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                                   provider,
                                   nullptr,
                                   false,
                                   kCGRenderingIntentDefault);
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(colorSpace);
  if (!image) {
    return;
  }

  NSRect bounds = self.bounds;
  const int displayWidth = _displayWidth > 0 ? _displayWidth : _frameWidth;
  const int displayHeight = _displayHeight > 0 ? _displayHeight : _frameHeight;
  const CGFloat imageAspect = static_cast<CGFloat>(displayWidth) / static_cast<CGFloat>(displayHeight);
  const CGFloat viewAspect = bounds.size.width / std::max<CGFloat>(bounds.size.height, 1.0);
  NSRect drawRect = bounds;
  if (imageAspect > viewAspect) {
    drawRect.size.height = bounds.size.width / imageAspect;
    drawRect.origin.y += (bounds.size.height - drawRect.size.height) * 0.5;
  } else {
    drawRect.size.width = bounds.size.height * imageAspect;
    drawRect.origin.x += (bounds.size.width - drawRect.size.width) * 0.5;
  }
  CGContextRef context = NSGraphicsContext.currentContext.CGContext;
  CGContextSaveGState(context);
  CGContextTranslateCTM(context, 0, bounds.size.height);
  CGContextScaleCTM(context, 1, -1);
  CGRect flipped = CGRectMake(drawRect.origin.x, bounds.size.height - NSMaxY(drawRect), drawRect.size.width, drawRect.size.height);
  CGContextDrawImage(context, flipped, image);
  CGContextRestoreGState(context);
  CGImageRelease(image);
}

@end
