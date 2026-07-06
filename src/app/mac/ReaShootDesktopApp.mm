#import "../../platform/mac/mac_h264_preview_renderer.h"
#import "../../platform/mac/mac_helper_process.h"
#import "../../platform/mac/mac_preview_stream_client.h"

#include "../../core/helper_output_parser.h"
#include "../../core/remote_camera.h"
#include "../../desktop/desktop_workflow.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>
#include <cstdarg>
#include <cstdlib>
#include <memory>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace {

NSString *nsString(const std::string &value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string stdString(NSString *value) {
  return value.UTF8String ? value.UTF8String : "";
}

bool gDebugLogging = false;
NSFileHandle *gDebugLogFile = nil;

std::string redactedText(std::string value) {
  const std::vector<std::string> prefixes = {"token=", "code=", "pairingCode="};
  for (const std::string &prefix : prefixes) {
    std::string::size_type position = 0;
    while ((position = value.find(prefix, position)) != std::string::npos) {
      const std::string::size_type valueStart = position + prefix.size();
      std::string::size_type valueEnd = value.find_first_of(" \t\r\n", valueStart);
      if (valueEnd == std::string::npos) {
        valueEnd = value.size();
      }
      value.replace(valueStart, valueEnd - valueStart, "REDACTED");
      position = valueStart + 8;
    }
  }
  return value;
}

std::string redactedArguments(const std::vector<std::string> &arguments) {
  std::ostringstream stream;
  bool redactNext = false;
  for (size_t index = 0; index < arguments.size(); ++index) {
    if (index > 0) {
      stream << ' ';
    }
    if (redactNext) {
      stream << "REDACTED";
      redactNext = false;
      continue;
    }
    stream << redactedText(arguments[index]);
    if (arguments[index] == "--token" || arguments[index] == "--code") {
      redactNext = true;
    }
  }
  return stream.str();
}

std::string redactedSettingsSummary(const reashoot::core::RemoteCameraSettings &settings) {
  std::ostringstream stream;
  stream << "host=" << settings.host
         << " controlPort=" << settings.controlPort
         << " httpPort=" << settings.httpPort
         << " token=" << (settings.token.empty() ? "empty" : "present")
         << " profile=" << settings.resolution << "/" << settings.fps
         << " orientation=" << settings.orientation
         << " aspect=" << settings.aspect
         << " lens=" << settings.lens
         << " zoom=" << settings.zoom
         << " look=" << settings.look;
  return stream.str();
}

void debugLog(NSString *format, ...) {
  if (!gDebugLogging) {
    return;
  }
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                       dateStyle:NSDateFormatterNoStyle
                                                       timeStyle:NSDateFormatterMediumStyle];
  NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message ?: @""];
  fputs(line.UTF8String ?: "", stderr);
  if (gDebugLogFile) {
    [gDebugLogFile writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
  }
}

NSString *debugLogPath() {
  NSURL *logsURL = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
  logsURL = [[logsURL URLByAppendingPathComponent:@"Logs" isDirectory:YES] URLByAppendingPathComponent:@"ReaShoot" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:logsURL withIntermediateDirectories:YES attributes:nil error:nil];
  return [[logsURL URLByAppendingPathComponent:@"ReaShoot-debug.log"] path];
}

void initializeDebugLogging(int argc, const char *argv[]) {
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index] ? argv[index] : "";
    if (argument == "-debug" || argument == "--debug") {
      gDebugLogging = true;
      break;
    }
  }
  if (!gDebugLogging) {
    return;
  }
  NSString *path = debugLogPath();
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
  }
  gDebugLogFile = [NSFileHandle fileHandleForWritingAtPath:path];
  [gDebugLogFile seekToEndOfFile];
  debugLog(@"Debug logging enabled. path=%@ pid=%d", path, getpid());
}

std::string helperExecutablePath() {
  NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"reashoot-mac" ofType:nil];
  if (resourcePath.length > 0) {
    return stdString(resourcePath);
  }
  NSString *executableDir = [NSBundle mainBundle].executablePath.stringByDeletingLastPathComponent;
  NSString *sibling = [executableDir stringByAppendingPathComponent:@"reashoot-mac"];
  return stdString(sibling);
}

NSButton *makeButton(NSString *title, id target, SEL action) {
  NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
  button.bezelStyle = NSBezelStyleRounded;
  return button;
}

NSTextField *makeLabel(NSString *text) {
  NSTextField *label = [NSTextField labelWithString:text];
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  return label;
}

NSTextField *makeField(NSString *placeholder) {
  NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
  field.placeholderString = placeholder;
  field.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  return field;
}

NSPopUpButton *makePopup(NSArray<NSString *> *items) {
  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [popup addItemsWithTitles:items];
  return popup;
}

} // namespace

@interface ReaShootPreviewView : NSView
- (void)setFramePixels:(std::vector<uint8_t>)pixels width:(int)width height:(int)height stride:(int)stride;
@end

@implementation ReaShootPreviewView {
  std::vector<uint8_t> _pixels;
  int _frameWidth;
  int _frameHeight;
  int _frameStride;
}

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;
  }
  return self;
}

- (void)setFramePixels:(std::vector<uint8_t>)pixels width:(int)width height:(int)height stride:(int)stride {
  _pixels = std::move(pixels);
  _frameWidth = width;
  _frameHeight = height;
  _frameStride = stride;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  [NSColor.blackColor setFill];
  NSRectFill(dirtyRect);
  if (_pixels.empty() || _frameWidth <= 0 || _frameHeight <= 0 || _frameStride <= 0) {
    NSDictionary *attributes = @{NSForegroundColorAttributeName : NSColor.secondaryLabelColor};
    [@"Live iPhone preview" drawAtPoint:NSMakePoint(18, 18) withAttributes:attributes];
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
  const CGFloat imageAspect = static_cast<CGFloat>(_frameWidth) / static_cast<CGFloat>(_frameHeight);
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

@interface ReaShootAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation ReaShootAppDelegate {
  NSWindow *_window;
  NSTextField *_hostField;
  NSTextField *_tokenField;
  NSTextField *_pairCodeField;
  NSTextField *_downloadField;
  NSPopUpButton *_resolutionPopup;
  NSPopUpButton *_fpsPopup;
  NSPopUpButton *_orientationPopup;
  NSPopUpButton *_aspectPopup;
  NSPopUpButton *_lensPopup;
  NSTextField *_zoomField;
  NSPopUpButton *_lookPopup;
  NSTextField *_statusLabel;
  ReaShootPreviewView *_previewView;
  NSButton *_startButton;
  NSButton *_stopButton;
  NSButton *_previewButton;

  std::unique_ptr<reashoot::core::HelperProcess> _helper;
  std::unique_ptr<reashoot::core::RemoteCameraController> _camera;
  std::unique_ptr<reashoot::core::PreviewStreamClient> _previewClient;
  std::unique_ptr<reashoot::core::PreviewRenderer> _previewRenderer;
  reashoot::core::PreviewStreamDescriptor _previewDescriptor;
  std::shared_ptr<reashoot::core::AsyncCommandHandle> _activeCommand;
  bool _recording;
  bool _previewRunning;
  uint64_t _previewAccessUnitCount;
  uint64_t _previewFrameCount;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  const std::string helperPath = helperExecutablePath();
  debugLog(@"Application did finish launching. bundle=%@ helper=%@", NSBundle.mainBundle.bundlePath, nsString(helperPath));
  _helper = reashoot::platform::mac::createHelperProcess(helperPath, [](const std::string &message) {
    debugLog(@"helper: %@", nsString(redactedText(message)));
  });
  _camera = std::make_unique<reashoot::core::RemoteCameraController>(*_helper);
  _previewClient = reashoot::platform::mac::createPreviewStreamClient();
  _previewRenderer = reashoot::platform::mac::createH264PreviewRenderer([self](const reashoot::core::VideoFrame &frame) {
    ++_previewFrameCount;
    if (_previewFrameCount == 1 || _previewFrameCount % 60 == 0) {
      debugLog(@"Preview frame #%llu width=%d height=%d stride=%d bytes=%zu",
               _previewFrameCount,
               frame.width,
               frame.height,
               frame.strideBytes,
               frame.pixels.size());
    }
    [_previewView setFramePixels:frame.pixels width:frame.width height:frame.height stride:frame.strideBytes];
  });

  [self buildWindow];
  [self loadDefaults];
  [self updateButtons];
  [self setStatus:@"Ready. Open ReaShoot on your iPhone, then discover or enter its host."];
  [_window makeKeyAndOrderFront:nil];
  debugLog(@"Main window shown frame=%@", NSStringFromRect(_window.frame));
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  (void)sender;
  debugLog(@"Application terminating after last window closed.");
  return YES;
}

- (void)buildWindow {
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 980, 720)
                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
  _window.title = @"ReaShoot";
  _window.delegate = self;
  _window.minSize = NSMakeSize(780, 560);
  _window.maxSize = NSMakeSize(1280, 1200);
  [_window center];
  debugLog(@"Building main window initialFrame=%@ min=%@ max=%@",
           NSStringFromRect(_window.frame),
           NSStringFromSize(_window.minSize),
           NSStringFromSize(_window.maxSize));

  NSView *content = _window.contentView;
  NSStackView *root = [NSStackView stackViewWithViews:@[]];
  root.orientation = NSUserInterfaceLayoutOrientationVertical;
  root.alignment = NSLayoutAttributeLeading;
  root.spacing = 12;
  root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
  root.translatesAutoresizingMaskIntoConstraints = NO;
  [content addSubview:root];
  [NSLayoutConstraint activateConstraints:@[
    [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [root.topAnchor constraintEqualToAnchor:content.topAnchor],
    [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
  ]];

  _previewView = [[ReaShootPreviewView alloc] initWithFrame:NSZeroRect];
  _previewView.translatesAutoresizingMaskIntoConstraints = NO;
  [_previewView.heightAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;
  [root addArrangedSubview:_previewView];
  [_previewView.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.translatesAutoresizingMaskIntoConstraints = NO;
  grid.columnSpacing = 8;
  grid.rowSpacing = 8;
  [root addArrangedSubview:grid];
  [grid.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

  _hostField = makeField(@"kevin-long-iphone.local or IP address");
  _pairCodeField = makeField(@"Pairing code");
  _tokenField = makeField(@"Pairing token");
  _downloadField = makeField(@"Download folder");
  _zoomField = makeField(@"1.0");
  _resolutionPopup = makePopup(@[@"4K", @"1080p", @"720p"]);
  _fpsPopup = makePopup(@[@"30", @"24", @"60"]);
  _orientationPopup = makePopup(@[@"portrait", @"landscape", @"auto"]);
  _aspectPopup = makePopup(@[@"9:16", @"16:9", @"4:3", @"1:1"]);
  _lensPopup = makePopup(@[@"wide", @"ultrawide", @"telephoto"]);
  _lookPopup = makePopup(@[@"natural", @"cinematic", @"mono", @"ci:CIThermal"]);

  NSButton *discoverButton = makeButton(@"Discover", self, @selector(discoverPhone:));
  NSButton *pairButton = makeButton(@"Pair", self, @selector(pairPhone:));
  _previewButton = makeButton(@"Start Preview", self, @selector(togglePreview:));
  _startButton = makeButton(@"Start Recording", self, @selector(startRecording:));
  _stopButton = makeButton(@"Stop Recording", self, @selector(stopRecording:));
  NSButton *pendingButton = makeButton(@"Pending...", self, @selector(showPending:));
  NSButton *deleteAllButton = makeButton(@"Delete All Pending", self, @selector(deleteAllPending:));
  NSButton *chooseDownloadButton = makeButton(@"Choose...", self, @selector(chooseDownloadFolder:));

  [grid addRowWithViews:@[makeLabel(@"iPhone"), _hostField, discoverButton, makeLabel(@"Pair code"), _pairCodeField, pairButton]];
  [grid addRowWithViews:@[makeLabel(@"Token"), _tokenField, makeLabel(@""), makeLabel(@"Downloads"), _downloadField, chooseDownloadButton]];
  [grid addRowWithViews:@[makeLabel(@"Resolution"), _resolutionPopup, makeLabel(@"FPS"), _fpsPopup, makeLabel(@"Orientation"), _orientationPopup]];
  [grid addRowWithViews:@[makeLabel(@"Aspect"), _aspectPopup, makeLabel(@"Lens"), _lensPopup, makeLabel(@"Zoom"), _zoomField]];
  [grid addRowWithViews:@[makeLabel(@"Look"), _lookPopup, _previewButton, _startButton, _stopButton, pendingButton]];
  [grid addRowWithViews:@[makeLabel(@""), makeLabel(@""), makeLabel(@""), makeLabel(@""), makeLabel(@""), deleteAllButton]];

  for (NSInteger index = 0; index < grid.numberOfColumns; ++index) {
    [grid columnAtIndex:index].xPlacement = NSGridCellPlacementFill;
  }
  [_hostField.widthAnchor constraintLessThanOrEqualToConstant:300].active = YES;
  [_tokenField.widthAnchor constraintLessThanOrEqualToConstant:300].active = YES;
  [_pairCodeField.widthAnchor constraintLessThanOrEqualToConstant:140].active = YES;
  [_downloadField.widthAnchor constraintLessThanOrEqualToConstant:360].active = YES;
  [_zoomField.widthAnchor constraintLessThanOrEqualToConstant:90].active = YES;

  _statusLabel = makeLabel(@"");
  _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [root addArrangedSubview:_statusLabel];
  [_statusLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;
}

- (void)loadDefaults {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  _hostField.stringValue = [defaults stringForKey:@"host"] ?: @"";
  _downloadField.stringValue = [defaults stringForKey:@"downloadDirectory"] ?: nsString(reashoot::desktop::defaultDownloadDirectory());
  _zoomField.stringValue = [defaults stringForKey:@"zoom"] ?: @"1.0";
  debugLog(@"Loaded defaults host=%@ downloadDir=%@ zoom=%@",
           _hostField.stringValue,
           _downloadField.stringValue,
           _zoomField.stringValue);
}

- (void)saveDefaults {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:_hostField.stringValue forKey:@"host"];
  [defaults setObject:_downloadField.stringValue forKey:@"downloadDirectory"];
  [defaults setObject:_zoomField.stringValue forKey:@"zoom"];
  debugLog(@"Saved defaults host=%@ downloadDir=%@ zoom=%@",
           _hostField.stringValue,
           _downloadField.stringValue,
           _zoomField.stringValue);
}

- (reashoot::core::RemoteCameraSettings)settings {
  reashoot::core::RemoteCameraSettings settings;
  settings.host = stdString(_hostField.stringValue);
  settings.token = stdString(_tokenField.stringValue);
  settings.resolution = stdString(_resolutionPopup.titleOfSelectedItem);
  settings.fps = stdString(_fpsPopup.titleOfSelectedItem);
  settings.orientation = stdString(_orientationPopup.titleOfSelectedItem);
  settings.aspect = stdString(_aspectPopup.titleOfSelectedItem);
  settings.lens = stdString(_lensPopup.titleOfSelectedItem);
  settings.zoom = stdString(_zoomField.stringValue);
  settings.look = stdString(_lookPopup.titleOfSelectedItem);
  return settings;
}

- (void)setStatus:(NSString *)status {
  _statusLabel.stringValue = status ?: @"";
  debugLog(@"Status: %@", _statusLabel.stringValue);
}

- (void)setStatusFromResult:(const reashoot::core::CommandResult &)result fallback:(NSString *)fallback {
  debugLog(@"Applying command result status exit=%d fallback=%@ output=%@ error=%@",
           result.exitCode,
           fallback,
           nsString(redactedText(result.output)),
           nsString(redactedText(result.errorMessage)));
  if (result.exitCode == 0) {
    [self setStatus:fallback];
    return;
  }
  std::string message = result.errorMessage.empty() ? result.output : result.errorMessage;
  if (message.empty()) {
    message = "Command failed.";
  }
  [self setStatus:nsString(message)];
}

- (BOOL)requireHostAndToken {
  if (_hostField.stringValue.length == 0) {
    debugLog(@"Missing host for authenticated action.");
    [self setStatus:@"Enter or discover an iPhone host first."];
    return NO;
  }
  if (_tokenField.stringValue.length == 0) {
    debugLog(@"Missing token for authenticated action. host=%@", _hostField.stringValue);
    [self setStatus:@"Pair with the iPhone or enter a token first."];
    return NO;
  }
  return YES;
}

- (void)updateButtons {
  _startButton.enabled = !_recording;
  _stopButton.enabled = _recording;
  _previewButton.title = _previewRunning ? @"Stop Preview" : @"Start Preview";
  debugLog(@"Buttons updated recording=%d previewRunning=%d startEnabled=%d stopEnabled=%d previewTitle=%@",
           _recording,
           _previewRunning,
           _startButton.enabled,
           _stopButton.enabled,
           _previewButton.title);
}

- (void)runCommand:(NSString *)status
          settings:(const reashoot::core::RemoteCameraSettings &)settings
           command:(const std::string &)command
         arguments:(const std::vector<std::string> &)arguments
        completion:(void (^)(reashoot::core::CommandResult result))completion {
  [self setStatus:status];
  debugLog(@"Command start command=%s args=%s settings=%s",
           command.c_str(),
           redactedArguments(arguments).c_str(),
           redactedSettingsSummary(settings).c_str());
  void (^completionCopy)(reashoot::core::CommandResult) = [completion copy];
  _activeCommand = _camera->runAsync(settings, command, arguments, {}, [completionCopy](reashoot::core::CommandResult result) {
    debugLog(@"Command finish exit=%d output=%@ error=%@",
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    if (completionCopy) {
      completionCopy(std::move(result));
    }
  });
}

- (void)discoverPhone:(id)sender {
  (void)sender;
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Discover clicked settings=%s", redactedSettingsSummary(settings).c_str());
  [self runCommand:@"Discovering iPhones..."
          settings:settings
           command:"discover"
         arguments:{"--timeout", "3"}
        completion:^(reashoot::core::CommandResult result) {
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Discovery failed."];
      return;
    }
    const auto cameras = reashoot::desktop::parseDiscoveredCameras(result.output);
    debugLog(@"Discovery parsed %zu camera(s).", cameras.size());
    if (cameras.empty()) {
      [self setStatus:@"No iPhone found. Enter the host or IP address manually."];
      return;
    }
    const auto &camera = cameras.front();
    debugLog(@"Using discovered camera name=%@ host=%s controlPort=%s httpPort=%s paired=%d",
             nsString(camera.name),
             camera.host.c_str(),
             camera.controlPort.c_str(),
             camera.httpPort.c_str(),
             camera.paired);
    _hostField.stringValue = nsString(camera.host);
    [self saveDefaults];
    [self setStatus:[NSString stringWithFormat:@"Found %@ at %@", nsString(camera.name), nsString(camera.host)]];
  }];
}

- (void)pairPhone:(id)sender {
  (void)sender;
  debugLog(@"Pair clicked host=%@ codeLength=%lu", _hostField.stringValue, static_cast<unsigned long>(_pairCodeField.stringValue.length));
  if (_hostField.stringValue.length == 0 || _pairCodeField.stringValue.length == 0) {
    [self setStatus:@"Enter the iPhone host and pairing code."];
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [self runCommand:@"Pairing with iPhone..."
          settings:settings
           command:"pair"
         arguments:{"--code", stdString(_pairCodeField.stringValue)}
        completion:^(reashoot::core::CommandResult result) {
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Pairing failed."];
      return;
    }
    reashoot::core::FieldMap fields = reashoot::core::parseFields(result.output, ' ');
    auto token = fields.find("token");
    debugLog(@"Pair response parsed tokenPresent=%d raw=%@", token != fields.end() && !token->second.empty(), nsString(redactedText(result.output)));
    if (token == fields.end() || token->second.empty()) {
      [self setStatus:@"Pairing response did not include a token."];
      return;
    }
    _tokenField.stringValue = nsString(token->second);
    [self saveDefaults];
    [self setStatus:@"Paired. Token is kept in this session; store it securely if needed."];
  }];
}

- (void)togglePreview:(id)sender {
  (void)sender;
  debugLog(@"Toggle preview clicked current=%d", _previewRunning);
  if (_previewRunning) {
    [self stopPreview];
  } else {
    [self startPreview];
  }
}

- (void)startPreview {
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Starting preview with settings=%s", redactedSettingsSummary(settings).c_str());
  [self runCommand:@"Starting preview..."
          settings:settings
           command:"start-preview"
         arguments:reashoot::core::tokenArguments(settings)
        completion:^(reashoot::core::CommandResult result) {
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Preview failed."];
      return;
    }
    _previewDescriptor = reashoot::desktop::parsePreviewDescriptor(result.output);
    debugLog(@"Preview descriptor path=%s port=%d raw=%@", _previewDescriptor.streamPath.c_str(), _previewDescriptor.port, nsString(redactedText(result.output)));
    reashoot::core::PreviewStreamRequest request;
    request.host = stdString(_hostField.stringValue);
    request.port = _previewDescriptor.port;
    request.path = _previewDescriptor.streamPath;
    request.token = stdString(_tokenField.stringValue);
    _previewRenderer->reset();
    _previewAccessUnitCount = 0;
    _previewFrameCount = 0;
    const bool started = _previewClient->start(request,
                                               [self](std::vector<uint8_t> data) {
                                                 ++_previewAccessUnitCount;
                                                 if (_previewAccessUnitCount == 1 || _previewAccessUnitCount % 60 == 0) {
                                                   debugLog(@"Preview access unit #%llu bytes=%zu", _previewAccessUnitCount, data.size());
                                                 }
                                                 _previewRenderer->renderAnnexBAccessUnit(data.data(), data.size());
                                               },
                                               [self]() {
                                                 debugLog(@"Preview stream active.");
                                                 _previewRunning = true;
                                                 [self updateButtons];
                                                 [self setStatus:@"Preview streaming."];
                                               },
                                               [self](const std::string &message) {
                                                 debugLog(@"Preview stream error=%@", nsString(message));
                                                 _previewRunning = false;
                                                 [self updateButtons];
                                                 [self setStatus:nsString(message)];
                                               });
    if (!started) {
      debugLog(@"Preview stream client failed to start.");
      [self setStatus:@"Could not open preview stream."];
    }
  }];
}

- (void)stopPreview {
  debugLog(@"Stopping preview. running=%d accessUnits=%llu frames=%llu", _previewRunning, _previewAccessUnitCount, _previewFrameCount);
  _previewClient->stop();
  _previewRenderer->reset();
  _previewRunning = false;
  [self updateButtons];
  reashoot::core::RemoteCameraSettings settings = [self settings];
  if (!settings.host.empty() && !settings.token.empty()) {
    _activeCommand = _camera->runAsync(settings, "stop-preview", reashoot::core::tokenArguments(settings), {}, [](reashoot::core::CommandResult) {});
  }
  [self setStatus:@"Preview stopped."];
}

- (void)startRecording:(id)sender {
  (void)sender;
  debugLog(@"Start recording clicked.");
  if (![self requireHostAndToken]) {
    return;
  }
  [self saveDefaults];
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [self runCommand:@"Configuring iPhone..."
          settings:settings
           command:"configure"
         arguments:reashoot::core::configureArguments(settings)
        completion:^(reashoot::core::CommandResult configureResult) {
    if (configureResult.exitCode != 0) {
      [self setStatusFromResult:configureResult fallback:@"Configure failed."];
      return;
    }
    reashoot::core::RemoteCameraSettings startSettings = [self settings];
    std::string sessionID = reashoot::desktop::makeSessionID();
    debugLog(@"Configure succeeded. Starting recording session=%s", sessionID.c_str());
    [self runCommand:@"Starting recording..."
            settings:startSettings
             command:"start"
           arguments:reashoot::core::startArguments(startSettings, sessionID)
          completion:^(reashoot::core::CommandResult startResult) {
      if (startResult.exitCode != 0) {
        [self setStatusFromResult:startResult fallback:@"Start failed."];
        return;
      }
      _recording = true;
      [self updateButtons];
      [self setStatus:@"Recording on iPhone."];
    }];
  }];
}

- (void)stopRecording:(id)sender {
  (void)sender;
  debugLog(@"Stop recording clicked.");
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Stopping recording settings=%s", redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Stopping iPhone recording..."];
  _activeCommand = _camera->stop(settings, [self](reashoot::core::CommandResult result) {
    debugLog(@"Stop recording completed exit=%d output=%@ error=%@",
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    _recording = false;
    [self updateButtons];
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Stop failed."];
      return;
    }
    auto recordings = reashoot::desktop::parseRecordingDescriptors(result.output);
    debugLog(@"Stop parsed %zu recording descriptor(s).", recordings.size());
    if (recordings.empty()) {
      [self setStatus:@"Recording stopped, but no recording descriptor was returned."];
      return;
    }
    [self promptForRecording:recordings.front()];
  });
}

- (void)promptForRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording {
  debugLog(@"Prompting for recording id=%s filename=%s bytes=%s path=%s checksumPresent=%d",
           recording.id.c_str(),
           recording.filename.c_str(),
           recording.byteCount.c_str(),
           recording.downloadPath.c_str(),
           !recording.checksum.empty());
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Recording stopped";
  alert.informativeText = [NSString stringWithFormat:@"Download or delete %@?", nsString(recording.filename)];
  [alert addButtonWithTitle:@"Download"];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];
  NSModalResponse response = [alert runModal];
  debugLog(@"Recording prompt response=%ld", static_cast<long>(response));
  if (response == NSAlertFirstButtonReturn) {
    [self downloadRecording:recording];
  } else if (response == NSAlertSecondButtonReturn) {
    [self deleteRecording:recording.id];
  } else {
    [self setStatus:@"Recording remains pending on the iPhone."];
  }
}

- (void)downloadRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording {
  reashoot::core::RemoteCameraSettings settings = [self settings];
  std::string downloadDirectory = stdString(_downloadField.stringValue);
  if (downloadDirectory.empty()) {
    downloadDirectory = reashoot::desktop::defaultDownloadDirectory();
    _downloadField.stringValue = nsString(downloadDirectory);
  }
  debugLog(@"Downloading recording id=%s filename=%s directory=%s settings=%s",
           recording.id.c_str(),
           recording.filename.c_str(),
           downloadDirectory.c_str(),
           redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Downloading iPhone video..."];
  _activeCommand = _camera->downloadRecording(settings,
                                              recording,
                                              downloadDirectory,
                                              [self](const std::string &line) {
                                                debugLog(@"Download progress line=%@", nsString(redactedText(line)));
                                                std::string status = reashoot::core::progressStatusText(line);
                                                if (!status.empty()) {
                                                  [self setStatus:nsString(status)];
                                                }
                                              },
                                              [self](reashoot::core::CommandResult result) {
                                                debugLog(@"Download completed exit=%d output=%@ error=%@",
                                                         result.exitCode,
                                                         nsString(redactedText(result.output)),
                                                         nsString(redactedText(result.errorMessage)));
                                                if (result.exitCode != 0) {
                                                  [self setStatusFromResult:result fallback:@"Download failed."];
                                                  return;
                                                }
                                                std::string path = reashoot::core::parseDownloadedPath(result.output);
                                                if (path.empty()) {
                                                  [self setStatus:@"Download completed."];
                                                  return;
                                                }
                                                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:nsString(path)]]];
                                                [self setStatus:[NSString stringWithFormat:@"Downloaded %@", nsString(path)]];
                                              });
}

- (void)deleteRecording:(const std::string &)recordingID {
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Deleting recording id=%s settings=%s", recordingID.c_str(), redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Deleting iPhone recording..."];
  _activeCommand = _camera->deleteRecording(settings, recordingID, [self](reashoot::core::CommandResult result) {
    debugLog(@"Delete completed exit=%d output=%@ error=%@",
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    [self setStatusFromResult:result fallback:@"Recording deleted."];
  });
}

- (void)showPending:(id)sender {
  (void)sender;
  debugLog(@"Pending clicked.");
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Listing pending recordings settings=%s", redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Checking pending recordings..."];
  _activeCommand = _camera->listRecordings(settings, [self](reashoot::core::CommandResult result) {
    debugLog(@"List pending completed exit=%d output=%@ error=%@",
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Could not list recordings."];
      return;
    }
    auto recordings = reashoot::desktop::parseRecordingDescriptors(result.output);
    debugLog(@"List pending parsed %zu recording(s).", recordings.size());
    if (recordings.empty()) {
      [self setStatus:@"No pending recordings on the iPhone."];
      return;
    }
    [self promptForRecording:recordings.front()];
  });
}

- (void)deleteAllPending:(id)sender {
  (void)sender;
  debugLog(@"Delete all pending clicked.");
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Listing pending recordings before delete-all settings=%s", redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Checking pending recordings..."];
  _activeCommand = _camera->listRecordings(settings, [self](reashoot::core::CommandResult result) {
    debugLog(@"Delete-all list completed exit=%d output=%@ error=%@",
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Could not list recordings."];
      return;
    }
    auto recordings = reashoot::desktop::parseRecordingDescriptors(result.output);
    debugLog(@"Delete-all parsed %zu pending recording(s).", recordings.size());
    if (recordings.empty()) {
      [self setStatus:@"No pending recordings on the iPhone."];
      return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete all pending recordings?";
    alert.informativeText = [NSString stringWithFormat:@"This will delete %zu pending recording(s) from the iPhone.", recordings.size()];
    [alert addButtonWithTitle:@"Delete All"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
      debugLog(@"Delete-all canceled by user.");
      [self setStatus:@"Pending recordings were left on the iPhone."];
      return;
    }
    [self deletePendingRecordings:recordings index:0];
  });
}

- (void)deletePendingRecordings:(std::vector<reashoot::core::RemoteRecordingDescriptor>)recordings index:(size_t)index {
  if (index >= recordings.size()) {
    debugLog(@"Delete-all completed.");
    [self setStatus:@"All pending recordings deleted."];
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [self setStatus:[NSString stringWithFormat:@"Deleting pending recording %zu of %zu...", index + 1, recordings.size()]];
  const std::string recordingID = recordings[index].id;
  debugLog(@"Delete-all deleting index=%zu total=%zu id=%s", index, recordings.size(), recordingID.c_str());
  _activeCommand = _camera->deleteRecording(settings, recordingID, [self, recordings = std::move(recordings), index](reashoot::core::CommandResult result) mutable {
    debugLog(@"Delete-all item completed index=%zu exit=%d output=%@ error=%@",
             index,
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Delete failed."];
      return;
    }
    [self deletePendingRecordings:std::move(recordings) index:index + 1];
  });
}

- (void)chooseDownloadFolder:(id)sender {
  (void)sender;
  debugLog(@"Choose download folder clicked.");
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES;
  panel.allowsMultipleSelection = NO;
  if ([panel runModal] == NSModalResponseOK) {
    _downloadField.stringValue = panel.URL.path ?: @"";
    debugLog(@"Download folder selected %@", _downloadField.stringValue);
    [self saveDefaults];
  } else {
    debugLog(@"Download folder selection canceled.");
  }
}

- (void)windowDidResize:(NSNotification *)notification {
  (void)notification;
  debugLog(@"Window resized frame=%@ content=%@", NSStringFromRect(_window.frame), NSStringFromRect(_window.contentView.frame));
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
  (void)notification;
  debugLog(@"Window ended live resize frame=%@", NSStringFromRect(_window.frame));
}

@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    initializeDebugLogging(argc, argv);
    NSApplication *application = NSApplication.sharedApplication;
    ReaShootAppDelegate *delegate = [[ReaShootAppDelegate alloc] init];
    application.delegate = delegate;
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    [application activateIgnoringOtherApps:YES];
    [application run];
  }
  return 0;
}
