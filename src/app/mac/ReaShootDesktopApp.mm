#import "../../platform/mac/mac_h264_preview_renderer.h"
#import "../../platform/mac/mac_helper_process.h"
#import "../../platform/mac/mac_preview_stream_client.h"
#include "ReaShootMacIntegrationServer.h"
#import "ReaShootMacSupport.h"
#import "ReaShootMacUI.h"
#import "ReaShootPreviewView.h"

#include "../../core/control_protocol.h"
#include "../../core/helper_output_parser.h"
#include "../../core/log_sanitization.h"
#include "../../core/remote_camera.h"
#include "../../desktop/desktop_app_controller.h"
#include "../../desktop/desktop_app_model.h"
#include "../../desktop/desktop_workflow.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>
#include <cstdlib>
#include <exception>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

using reashoot::core::redactedArguments;
using reashoot::core::redactedSettingsSummary;
using reashoot::core::redactedText;

} // namespace

@interface ReaShootAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate>
@end

@implementation ReaShootAppDelegate {
  NSWindow *_window;
  NSWindow *_setupWindow;
  NSWindow *_videosWindow;
  NSTextField *_hostField;
  NSTextField *_downloadField;
  NSTextField *_pairedStatusLabel;
  NSTextField *_connectionStatusLabel;
  NSPopUpButton *_resolutionPopup;
  NSPopUpButton *_fpsPopup;
  NSPopUpButton *_orientationPopup;
  NSPopUpButton *_aspectPopup;
  NSPopUpButton *_lensPopup;
  NSTextField *_zoomField;
  NSPopUpButton *_lookPopup;
  NSTextField *_statusLabel;
  ReaShootPreviewView *_previewView;
  NSButton *_recordButton;
  NSButton *_previewButton;
  NSStackView *_videosList;
  NSTimer *_recordBlinkTimer;

  std::unique_ptr<reashoot::core::HelperProcess> _helper;
  std::unique_ptr<reashoot::core::RemoteCameraController> _camera;
  std::unique_ptr<reashoot::core::PreviewStreamClient> _previewClient;
  std::unique_ptr<reashoot::core::PreviewRenderer> _previewRenderer;
  std::unique_ptr<reashoot::app::mac::ReaShootMacIntegrationServer> _integrationServer;
  reashoot::core::PreviewStreamDescriptor _previewDescriptor;
  std::shared_ptr<reashoot::core::AsyncCommandHandle> _activeCommand;
  reashoot::desktop::DesktopAppController _desktopController;
  std::string _pairingToken;
  std::string _integrationApiToken;
  std::vector<reashoot::core::RemoteRecordingDescriptor> _phoneVideos;
  bool _recording;
  bool _recordBlinkOn;
  bool _previewRunning;
  bool _previewDesired;
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

  [self buildMenu];
  [self buildWindow];
  [self loadDefaults];
  [self updateButtons];
  [self updatePreviewEmptyState];
  [self startIntegrationServer];
  [self setStatus:@"Ready. Open ReaShoot on your iPhone, then discover or enter its host."];
  [_window makeKeyAndOrderFront:nil];
  debugLog(@"Main window shown frame=%@", NSStringFromRect(_window.frame));
  [self autoStartPreviewIfPossible];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  (void)sender;
  debugLog(@"Application terminating after last window closed.");
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  (void)notification;
  if (_integrationServer) {
    _integrationServer->stop();
  }
  reashoot::app::mac::removeIntegrationRegistration();
}

- (void)windowWillClose:(NSNotification *)notification {
  if (notification.object == _window) {
    debugLog(@"Main window closed; terminating app.");
    [_recordBlinkTimer invalidate];
    _recordBlinkTimer = nil;
    [NSApp terminate:self];
  }
}

- (void)buildMenu {
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
  NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:appMenuItem];

  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"ReaShoot"];
  NSMenuItem *setupItem = [[NSMenuItem alloc] initWithTitle:@"Setup..." action:@selector(showSetup:) keyEquivalent:@","];
  setupItem.target = self;
  [appMenu addItem:setupItem];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit ReaShoot" action:@selector(terminate:) keyEquivalent:@"q"]];

  appMenuItem.submenu = appMenu;
  NSApp.mainMenu = mainMenu;
}

- (void)buildWindow {
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 840, 680)
                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
  _window.title = @"ReaShoot";
  _window.delegate = self;
  _window.minSize = NSMakeSize(680, 520);
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

  NSStackView *controls = [NSStackView stackViewWithViews:@[]];
  controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  controls.alignment = NSLayoutAttributeCenterY;
  controls.spacing = 8;
  controls.translatesAutoresizingMaskIntoConstraints = NO;
  [root addArrangedSubview:controls];
  [controls.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

  _previewButton = makeButton(@"Start Preview", self, @selector(togglePreview:));
  _recordButton = makeButton(@"Start Recording", self, @selector(toggleRecording:));
  NSButton *videosButton = makeButton(@"Videos on iPhone", self, @selector(showPhoneVideos:));
  NSButton *setupButton = makeButton(@"Setup...", self, @selector(showSetup:));
  [_recordButton.widthAnchor constraintGreaterThanOrEqualToConstant:132].active = YES;
  for (NSView *view in @[_previewButton, _recordButton, videosButton, setupButton]) {
    [controls addArrangedSubview:view];
  }

  _connectionStatusLabel = makeLabel(@"Not paired");
  _connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [root addArrangedSubview:_connectionStatusLabel];
  [_connectionStatusLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

  _statusLabel = makeLabel(@"");
  _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [root addArrangedSubview:_statusLabel];
  [_statusLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

  [self buildSetupWindow];
}

- (void)buildSetupWindow {
  _setupWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 300)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  _setupWindow.title = @"ReaShoot Setup";
  _setupWindow.releasedWhenClosed = NO;
  _setupWindow.minSize = NSMakeSize(680, 260);
  [_setupWindow center];

  NSView *content = _setupWindow.contentView;
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

  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.translatesAutoresizingMaskIntoConstraints = NO;
  grid.columnSpacing = 8;
  grid.rowSpacing = 8;
  [root addArrangedSubview:grid];
  [grid.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;

  _hostField = makeField(@"kevin-long-iphone.local or IP address");
  _downloadField = makeField(@"Download folder");
  _zoomField = makeField(@"1.0");
  _resolutionPopup = makePopupFromChoices(reashoot::desktop::resolutionChoices());
  _fpsPopup = makePopupFromChoices(reashoot::desktop::fpsChoices());
  _orientationPopup = makePopupFromChoices(reashoot::desktop::orientationChoices());
  _aspectPopup = makePopupFromChoices(reashoot::desktop::aspectChoices());
  _lensPopup = makePopupFromChoices(reashoot::desktop::lensChoices());
  _lookPopup = makePopupFromChoices(reashoot::desktop::lookChoices());
  for (NSControl *control in @[_resolutionPopup, _fpsPopup, _orientationPopup, _aspectPopup, _lensPopup, _zoomField, _lookPopup]) {
    control.target = self;
    control.action = @selector(profileSelectionChanged:);
  }
  _zoomField.delegate = self;

  NSButton *discoverButton = makeButton(@"Discover", self, @selector(discoverPhone:));
  NSButton *pairButton = makeButton(@"Pair", self, @selector(pairPhone:));
  NSButton *chooseDownloadButton = makeButton(@"Choose...", self, @selector(chooseDownloadFolder:));
  _pairedStatusLabel = makeLabel(@"Not paired");

  [grid addRowWithViews:@[makeLabel(@"iPhone"), _hostField, discoverButton, makeLabel(@"Pairing"), _pairedStatusLabel, pairButton]];
  [grid addRowWithViews:@[makeLabel(@"Downloads"), _downloadField, chooseDownloadButton, makeLabel(@""), makeLabel(@""), makeLabel(@"")]];
  [grid addRowWithViews:@[makeLabel(@"Resolution"), _resolutionPopup, makeLabel(@"FPS"), _fpsPopup, makeLabel(@"Orientation"), _orientationPopup]];
  [grid addRowWithViews:@[makeLabel(@"Aspect"), _aspectPopup, makeLabel(@"Lens"), _lensPopup, makeLabel(@"Zoom"), _zoomField]];
  [grid addRowWithViews:@[makeLabel(@"Look"), _lookPopup, makeLabel(@""), makeLabel(@""), makeLabel(@""), makeLabel(@"")]];

  for (NSInteger index = 0; index < grid.numberOfColumns; ++index) {
    [grid columnAtIndex:index].xPlacement = NSGridCellPlacementFill;
  }
  [_hostField.widthAnchor constraintLessThanOrEqualToConstant:300].active = YES;
  [_pairedStatusLabel.widthAnchor constraintLessThanOrEqualToConstant:180].active = YES;
  [_downloadField.widthAnchor constraintLessThanOrEqualToConstant:360].active = YES;
  [_zoomField.widthAnchor constraintLessThanOrEqualToConstant:90].active = YES;
}

- (void)loadDefaults {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  _hostField.stringValue = [defaults stringForKey:@"host"] ?: @"";
  _downloadField.stringValue = [defaults stringForKey:@"downloadDirectory"] ?: nsString(reashoot::desktop::defaultDownloadDirectory());
  _zoomField.stringValue = [defaults stringForKey:@"zoom"] ?: nsString(reashoot::desktop::defaultZoom());
  selectPopupRepresentedValue(_resolutionPopup, [defaults stringForKey:@"resolution"], nsString(reashoot::desktop::defaultResolution()));
  selectPopupRepresentedValue(_fpsPopup, [defaults stringForKey:@"fps"], nsString(reashoot::desktop::defaultFps()));
  selectPopupRepresentedValue(_orientationPopup, [defaults stringForKey:@"orientation"], nsString(reashoot::desktop::defaultOrientation()));
  selectPopupRepresentedValue(_aspectPopup, [defaults stringForKey:@"aspect"], nsString(reashoot::desktop::defaultAspect()));
  selectPopupRepresentedValue(_lensPopup, [defaults stringForKey:@"lens"], nsString(reashoot::desktop::defaultLens()));
  selectPopupRepresentedValue(_lookPopup, [defaults stringForKey:@"look"], nsString(reashoot::desktop::defaultLook()));
  _pairingToken = stdString([defaults stringForKey:@"pairingToken"] ?: @"");
  [self updateConnectionStatusLabels];
  debugLog(@"Loaded defaults host=%@ downloadDir=%@ zoom=%@ orientation=%@ token=%@",
           _hostField.stringValue,
           _downloadField.stringValue,
           _zoomField.stringValue,
           _orientationPopup.titleOfSelectedItem,
           _pairingToken.empty() ? @"empty" : @"present");
}

- (void)saveDefaults {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:_hostField.stringValue forKey:@"host"];
  [defaults setObject:_downloadField.stringValue forKey:@"downloadDirectory"];
  [defaults setObject:_zoomField.stringValue forKey:@"zoom"];
  [defaults setObject:selectedPopupValue(_resolutionPopup, nsString(reashoot::desktop::defaultResolution())) forKey:@"resolution"];
  [defaults setObject:selectedPopupValue(_fpsPopup, nsString(reashoot::desktop::defaultFps())) forKey:@"fps"];
  [defaults setObject:selectedPopupValue(_orientationPopup, nsString(reashoot::desktop::defaultOrientation())) forKey:@"orientation"];
  [defaults setObject:selectedPopupValue(_aspectPopup, nsString(reashoot::desktop::defaultAspect())) forKey:@"aspect"];
  [defaults setObject:selectedPopupValue(_lensPopup, nsString(reashoot::desktop::defaultLens())) forKey:@"lens"];
  [defaults setObject:selectedPopupValue(_lookPopup, nsString(reashoot::desktop::defaultLook())) forKey:@"look"];
  if (_pairingToken.empty()) {
    [defaults removeObjectForKey:@"pairingToken"];
  } else {
    [defaults setObject:nsString(_pairingToken) forKey:@"pairingToken"];
  }
  debugLog(@"Saved defaults host=%@ downloadDir=%@ zoom=%@ orientation=%@ token=%@",
           _hostField.stringValue,
           _downloadField.stringValue,
           _zoomField.stringValue,
           _orientationPopup.titleOfSelectedItem,
           _pairingToken.empty() ? @"empty" : @"present");
  [self updateConnectionStatusLabels];
}

- (reashoot::core::RemoteCameraSettings)settings {
  reashoot::core::RemoteCameraSettings settings;
  settings.host = stdString(_hostField.stringValue);
  settings.token = _pairingToken;
  settings.resolution = stdString(selectedPopupValue(_resolutionPopup, nsString(reashoot::desktop::defaultResolution())));
  settings.fps = stdString(selectedPopupValue(_fpsPopup, nsString(reashoot::desktop::defaultFps())));
  settings.orientation = stdString(selectedPopupValue(_orientationPopup, nsString(reashoot::desktop::defaultOrientation())));
  settings.aspect = stdString(selectedPopupValue(_aspectPopup, nsString(reashoot::desktop::defaultAspect())));
  settings.lens = stdString(selectedPopupValue(_lensPopup, nsString(reashoot::desktop::defaultLens())));
  settings.zoom = stdString(_zoomField.stringValue);
  settings.look = stdString(selectedPopupValue(_lookPopup, nsString(reashoot::desktop::defaultLook())));
  return settings;
}

- (void)updateConnectionStatusLabels {
  [self syncDesktopControllerState];
  _pairedStatusLabel.stringValue = _desktopController.hasToken() ? @"Paired" : @"Not paired";
  _connectionStatusLabel.stringValue = nsString(_desktopController.connectionStatusText());
  [self updatePreviewEmptyState];
}

- (void)setStatus:(NSString *)status {
  _statusLabel.stringValue = status ?: @"";
  debugLog(@"Status: %@", _statusLabel.stringValue);
}

- (void)updatePreviewEmptyState {
  [self syncDesktopControllerState];
  [_previewView setEmptyMessage:nsString(_desktopController.previewEmptyMessage())];
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
    [_previewView clearFrameWithMessage:@"No iPhone selected."];
    return NO;
  }
  if (_pairingToken.empty()) {
    debugLog(@"Missing token for authenticated action. host=%@", _hostField.stringValue);
    [self setStatus:@"Pair with the iPhone first."];
    [_previewView clearFrameWithMessage:@"No paired iPhone."];
    return NO;
  }
  return YES;
}

- (void)updateButtons {
  [self syncDesktopControllerState];
  const reashoot::desktop::DesktopButtonState state = _desktopController.buttonState();
  _recordButton.enabled = state.recordEnabled;
  _previewButton.title = nsString(state.previewTitle);
  if (_recording && !_recordBlinkTimer) {
    _recordBlinkOn = true;
    _recordBlinkTimer = [NSTimer timerWithTimeInterval:2.5
                                                target:self
                                              selector:@selector(recordBlinkTimerFired:)
                                              userInfo:nil
                                               repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_recordBlinkTimer forMode:NSRunLoopCommonModes];
  } else if (!_recording && _recordBlinkTimer) {
    [_recordBlinkTimer invalidate];
    _recordBlinkTimer = nil;
    _recordBlinkOn = true;
  }
  applyRecordButtonAppearance(_recordButton, _recording, _recordBlinkOn);
  debugLog(@"Buttons updated recording=%d previewRunning=%d recordEnabled=%d previewTitle=%@",
           _recording,
           _previewRunning,
           _recordButton.enabled,
           _previewButton.title);
}

- (void)syncDesktopControllerState {
  _desktopController.setHost(stdString(_hostField.stringValue));
  _desktopController.setToken(_pairingToken);
  _desktopController.setRecording(_recording);
  _desktopController.setPreviewRunning(_previewRunning);
  _desktopController.setPreviewDesired(_previewDesired);
}

- (void)recordBlinkTimerFired:(NSTimer *)timer {
  (void)timer;
  if (!_recording) {
    [self updateButtons];
    return;
  }
  _recordBlinkOn = false;
  applyRecordButtonAppearance(_recordButton, true, _recordBlinkOn);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (_recording) {
      _recordBlinkOn = true;
      applyRecordButtonAppearance(_recordButton, true, _recordBlinkOn);
    }
  });
}

- (void)showSetup:(id)sender {
  (void)sender;
  [self saveDefaults];
  [_setupWindow makeKeyAndOrderFront:nil];
}

- (void)autoStartPreviewIfPossible {
  if (_pairingToken.empty()) {
    debugLog(@"Auto preview skipped: no saved token.");
    return;
  }
  _previewDesired = true;
  if (_hostField.stringValue.length == 0) {
    debugLog(@"Auto preview discovering host before start.");
    [self discoverPhone:nil];
    return;
  }
  debugLog(@"Auto preview scheduling start for host=%@", _hostField.stringValue);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (_previewDesired && !_previewRunning) {
      [self startPreviewWithRetryAttempt:0 automatic:YES];
    }
  });
}

- (void)schedulePreviewRetryAfterFailure:(const reashoot::core::CommandResult &)result
                                 attempt:(NSInteger)attempt
                               automatic:(BOOL)automatic
                                fallback:(NSString *)fallback {
  [self syncDesktopControllerState];
  const reashoot::desktop::PreviewRetryDecision retry = _desktopController.retryDecision(result, static_cast<int>(attempt));
  if (!retry.shouldRetry) {
    NSString *message = result.errorMessage.empty() ? nsString(result.output) : nsString(result.errorMessage);
    [_previewView clearFrameWithMessage:message.length > 0 ? message : fallback];
    [self setStatusFromResult:result fallback:fallback];
    return;
  }
  const NSInteger nextAttempt = retry.nextAttempt;
  const double delaySeconds = retry.delaySeconds;
  debugLog(@"Preview connection failed transiently; retrying attempt=%ld next=%ld delay=%.1fs automatic=%d",
           static_cast<long>(attempt),
           static_cast<long>(nextAttempt),
           delaySeconds,
           automatic);
  NSString *retryStatus = nsString(retry.statusText);
  [_previewView clearFrameWithMessage:retryStatus];
  [self setStatus:retryStatus];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(delaySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (_previewDesired && !_previewRunning) {
      [self startPreviewWithRetryAttempt:nextAttempt automatic:automatic];
    }
  });
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

- (reashoot::desktop::IntegrationStatus)integrationStatus {
  reashoot::desktop::IntegrationStatus status;
  status.paired = !_pairingToken.empty();
  status.previewRunning = _previewRunning;
  status.previewDesired = _previewDesired;
  status.recording = _recording;
  status.host = stdString(_hostField.stringValue);
  status.message = stdString(_statusLabel.stringValue);
  status.profile = [self settings];
  return status;
}

- (std::string)integrationStatusJson {
  return reashoot::desktop::statusToJson([self integrationStatus]).serialize();
}

- (void)applyIntegrationProfile:(const reashoot::core::RemoteCameraSettings &)settings {
  selectPopupRepresentedValue(_resolutionPopup, nsString(settings.resolution), nsString(reashoot::desktop::defaultResolution()));
  selectPopupRepresentedValue(_fpsPopup, nsString(settings.fps), nsString(reashoot::desktop::defaultFps()));
  selectPopupRepresentedValue(_orientationPopup, nsString(settings.orientation), nsString(reashoot::desktop::defaultOrientation()));
  selectPopupRepresentedValue(_aspectPopup, nsString(settings.aspect), nsString(reashoot::desktop::defaultAspect()));
  selectPopupRepresentedValue(_lensPopup, nsString(settings.lens), nsString(reashoot::desktop::defaultLens()));
  selectPopupRepresentedValue(_lookPopup, nsString(settings.look), nsString(reashoot::desktop::defaultLook()));
  _zoomField.stringValue = nsString(settings.zoom.empty() ? reashoot::desktop::defaultZoom() : settings.zoom);
  [self saveDefaults];
}

- (reashoot::desktop::IntegrationHttpResponse)handleIntegrationRequestOnMain:(const reashoot::desktop::IntegrationHttpRequest &)request {
  namespace desktop = reashoot::desktop;
  namespace core = reashoot::core;
  if (!desktop::requestHasValidToken(request, _integrationApiToken)) {
    return desktop::errorResponse(401, "unauthorized", "Invalid ReaShoot desktop API token.");
  }

  const auto busy = [self]() -> bool {
    return _activeCommand && _activeCommand->isRunning();
  };
  const auto accepted = [](const std::string &message) {
    return desktop::acceptedResponse(message);
  };

  if (request.method == "GET" && request.path == "/v1/status") {
    core::JsonValue::Object object;
    object.emplace("status", desktop::statusToJson([self integrationStatus]));
    return desktop::okResponse(std::move(object));
  }
  if (request.method == "GET" && request.path == "/v1/profile") {
    core::JsonValue::Object object;
    object.emplace("profile", desktop::profileToJson([self settings]));
    return desktop::okResponse(std::move(object));
  }
  if (request.method == "PUT" && request.path == "/v1/profile") {
    if (busy()) {
      return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
    }
    try {
      core::RemoteCameraSettings settings = [self settings];
      desktop::applyProfileJson(settings, core::parseJson(request.body));
      [self applyIntegrationProfile:settings];
      if (_previewRunning) {
        [self profileSelectionChanged:nil];
      }
      core::JsonValue::Object object;
      object.emplace("profile", desktop::profileToJson([self settings]));
      return desktop::okResponse(std::move(object));
    } catch (const std::exception &error) {
      return desktop::errorResponse(400, "invalid_json", error.what());
    }
  }
  if (request.method == "POST" && request.path == "/v1/phone/discover") {
    if (busy()) {
      return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
    }
    [self discoverPhone:nil];
    return accepted("Discovery started.");
  }
  if (request.method == "POST" && request.path == "/v1/phone/pair") {
    if (busy()) {
      return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
    }
    [self pairPhone:nil];
    return accepted("Pairing request started.");
  }
  if (request.method == "POST" && request.path == "/v1/preview/start") {
    if (busy()) {
      return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
    }
    _previewDesired = true;
    [self startPreview];
    return accepted("Preview start requested.");
  }
  if (request.method == "POST" && request.path == "/v1/preview/stop") {
    [self stopPreview];
    return accepted("Preview stop requested.");
  }
  if (request.method == "POST" && request.path == "/v1/recording/start") {
    if (busy() || _recording) {
      return desktop::errorResponse(409, "busy", "Recording is already active or ReaShoot is busy.");
    }
    [self startRecording:nil];
    return accepted("Recording start requested.");
  }
  if (request.method == "POST" && request.path == "/v1/recording/stop") {
    if (!_recording) {
      return desktop::errorResponse(409, "not_recording", "No recording is active.");
    }
    if (busy()) {
      return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
    }
    [self stopRecordingForIntegration];
    return accepted("Recording stop requested.");
  }
  if (request.method == "GET" && request.path == "/v1/recordings") {
    core::JsonValue::Object object;
    object.emplace("recordings", desktop::recordingsToJson([self settings], _phoneVideos));
    return desktop::okResponse(std::move(object));
  }
  if (request.method == "POST" && request.path == "/v1/recordings/refresh") {
    if (busy()) {
      return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
    }
    [self refreshPhoneVideos:nil];
    return accepted("Recording refresh requested.");
  }

  const std::string recordingsPrefix = "/v1/recordings/";
  if (request.path.rfind(recordingsPrefix, 0) == 0) {
    std::string remainder = request.path.substr(recordingsPrefix.size());
    std::string action;
    const size_t slash = remainder.find('/');
    if (slash != std::string::npos) {
      action = remainder.substr(slash + 1);
      remainder = remainder.substr(0, slash);
    }
    if (remainder.empty()) {
      return desktop::errorResponse(404, "not_found", "Recording ID is missing.");
    }
    if (request.method == "DELETE" || (request.method == "POST" && action == "download")) {
      if (busy()) {
        return desktop::errorResponse(409, "busy", "ReaShoot is busy with another operation.");
      }
    }
    auto found = std::find_if(_phoneVideos.begin(), _phoneVideos.end(), [&](const auto &recording) {
      return recording.id == remainder;
    });
    if (request.method == "DELETE" && action.empty()) {
      [self deleteRecording:remainder];
      return accepted("Recording delete requested.");
    }
    if (request.method == "POST" && action == "download") {
      if (found == _phoneVideos.end()) {
        return desktop::errorResponse(404, "not_found", "Recording is not in the current phone video list. Refresh recordings first.");
      }
      std::string downloadDirectory;
      if (!request.body.empty()) {
        try {
          downloadDirectory = core::parseJson(request.body).stringValue("downloadDirectory");
        } catch (const std::exception &error) {
          return desktop::errorResponse(400, "invalid_json", error.what());
        }
      }
      [self downloadRecording:*found directory:downloadDirectory revealDownloadedFile:NO];
      return accepted("Recording download requested.");
    }
  }

  return desktop::errorResponse(404, "not_found", "Unknown ReaShoot desktop API endpoint.");
}

- (reashoot::desktop::IntegrationHttpResponse)handleIntegrationRequest:(const reashoot::desktop::IntegrationHttpRequest &)request {
  if (NSThread.isMainThread) {
    return [self handleIntegrationRequestOnMain:request];
  }
  __block reashoot::desktop::IntegrationHttpResponse response;
  dispatch_sync(dispatch_get_main_queue(), ^{
    response = [self handleIntegrationRequestOnMain:request];
  });
  return response;
}

- (void)startIntegrationServer {
  _integrationApiToken = reashoot::app::mac::loadOrCreateIntegrationToken();
  _integrationServer = std::make_unique<reashoot::app::mac::ReaShootMacIntegrationServer>();
  std::string error;
  const bool started = _integrationServer->start(_integrationApiToken,
                                                 [self](const reashoot::desktop::IntegrationHttpRequest &request) {
                                                   return [self handleIntegrationRequest:request];
                                                 },
                                                 [self]() {
                                                   if (NSThread.isMainThread) {
                                                     return [self integrationStatusJson];
                                                   }
                                                   __block std::string snapshot;
                                                   dispatch_sync(dispatch_get_main_queue(), ^{
                                                     snapshot = [self integrationStatusJson];
                                                   });
                                                   return snapshot;
                                                 },
                                                 &error);
  if (!started) {
    debugLog(@"Desktop integration API failed to start: %@", nsString(error));
    return;
  }
  reashoot::app::mac::writeIntegrationRegistration(_integrationServer->port(), _integrationApiToken);
  debugLog(@"Desktop integration API listening on 127.0.0.1:%d", _integrationServer->port());
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
    if (_previewDesired && !_pairingToken.empty() && !_previewRunning) {
      [self startPreviewWithRetryAttempt:0 automatic:YES];
    }
  }];
}

- (void)pairPhone:(id)sender {
  (void)sender;
  if (_hostField.stringValue.length == 0) {
    [self setStatus:@"Enter or discover an iPhone host first."];
    return;
  }
  const std::string clientName = localComputerName();
  debugLog(@"Pair clicked host=%@ clientName=%@", _hostField.stringValue, nsString(clientName));
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [self runCommand:@"Pairing request sent. Accept it on the iPhone."
          settings:settings
           command:"pair"
         arguments:{"--client-name", clientName}
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
    _pairingToken = token->second;
    [self updateConnectionStatusLabels];
    [self saveDefaults];
    [self setStatus:@"Paired with iPhone."];
    _previewDesired = true;
    [self startPreviewWithRetryAttempt:0 automatic:YES];
  }];
}

- (void)profileSelectionChanged:(id)sender {
  [self saveDefaults];
  debugLog(@"Profile control changed sender=%@ profile=%s previewRunning=%d",
           sender ? NSStringFromClass([sender class]) : @"unknown",
           redactedSettingsSummary([self settings]).c_str(),
           _previewRunning);
  if (!_previewRunning) {
    return;
  }
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [self runCommand:@"Applying capture settings..."
          settings:settings
           command:"configure"
         arguments:reashoot::core::configureArguments(settings)
        completion:^(reashoot::core::CommandResult result) {
    if (result.exitCode != 0) {
      [self schedulePreviewRetryAfterFailure:result attempt:0 automatic:YES fallback:@"Could not apply capture settings."];
      return;
    }
    [self setStatus:@"Preview streaming."];
  }];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
  [self profileSelectionChanged:notification.object];
}

- (void)togglePreview:(id)sender {
  (void)sender;
  debugLog(@"Toggle preview clicked current=%d", _previewRunning);
  if (_previewRunning) {
    [self stopPreview];
  } else {
    _previewDesired = true;
    [self startPreview];
  }
}

- (void)toggleRecording:(id)sender {
  if (_recording) {
    [self stopRecording:sender];
  } else {
    [self startRecording:sender];
  }
}

- (void)startPreview {
  [self startPreviewWithRetryAttempt:0 automatic:NO];
}

- (void)startPreviewWithRetryAttempt:(NSInteger)attempt automatic:(BOOL)automatic {
  if (![self requireHostAndToken]) {
    return;
  }
  [self saveDefaults];
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [_previewView clearFrameWithMessage:@"Connecting to iPhone preview..."];
  debugLog(@"Starting preview attempt=%ld automatic=%d settings=%s",
           static_cast<long>(attempt),
           automatic,
           redactedSettingsSummary(settings).c_str());
  [self runCommand:@"Configuring preview..."
          settings:settings
           command:"configure"
         arguments:reashoot::core::configureArguments(settings)
        completion:^(reashoot::core::CommandResult configureResult) {
    if (configureResult.exitCode != 0) {
      [self schedulePreviewRetryAfterFailure:configureResult attempt:attempt automatic:automatic fallback:@"Configure failed."];
      return;
    }
    reashoot::core::RemoteCameraSettings previewSettings = [self settings];
    [self runCommand:@"Starting preview..."
            settings:previewSettings
             command:"start-preview"
           arguments:reashoot::core::tokenArguments(previewSettings)
          completion:^(reashoot::core::CommandResult result) {
      if (result.exitCode != 0) {
        [self schedulePreviewRetryAfterFailure:result attempt:attempt automatic:automatic fallback:@"Preview failed."];
        return;
      }
    _previewDescriptor = reashoot::desktop::parsePreviewDescriptor(result.output);
    debugLog(@"Preview descriptor path=%s port=%d raw=%@", _previewDescriptor.streamPath.c_str(), _previewDescriptor.port, nsString(redactedText(result.output)));
    reashoot::core::PreviewStreamRequest request;
    request.host = stdString(_hostField.stringValue);
    request.port = _previewDescriptor.port;
    request.path = _previewDescriptor.streamPath;
    request.token = _pairingToken;
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
                                               [self](const std::string &descriptorJson) {
                                                 try {
                                                   reashoot::core::ProtocolPreview preview =
                                                       reashoot::core::previewFromJson(reashoot::core::parseJson(descriptorJson));
                                                   const bool dimensionsChanged =
                                                       preview.width != _previewDescriptor.width ||
                                                       preview.height != _previewDescriptor.height ||
                                                       preview.displayWidth != _previewDescriptor.displayWidth ||
                                                       preview.displayHeight != _previewDescriptor.displayHeight ||
                                                       preview.resolvedOrientation != _previewDescriptor.resolvedOrientation;
                                                   _previewDescriptor.width = preview.width;
                                                   _previewDescriptor.height = preview.height;
                                                   _previewDescriptor.fps = preview.fps;
                                                   _previewDescriptor.orientation = preview.orientation;
                                                   _previewDescriptor.resolvedOrientation = preview.resolvedOrientation;
                                                   _previewDescriptor.displayWidth = preview.displayWidth;
                                                   _previewDescriptor.displayHeight = preview.displayHeight;
                                                   _previewDescriptor.displayAspectRatio = preview.displayAspectRatio;
                                                   _previewDescriptor.metadataVersion = preview.metadataVersion;
                                                   [_previewView setDisplaySizeWithWidth:_previewDescriptor.displayWidth
                                                                                  height:_previewDescriptor.displayHeight];
                                                   debugLog(@"Preview descriptor update width=%d height=%d orientation=%@ resolved=%@ aspect=%@",
                                                            _previewDescriptor.width,
                                                            _previewDescriptor.height,
                                                            nsString(_previewDescriptor.orientation),
                                                            nsString(_previewDescriptor.resolvedOrientation),
                                                            nsString(_previewDescriptor.displayAspectRatio));
                                                   if (dimensionsChanged) {
                                                     [_previewView clearFrameWithMessage:@"Updating preview orientation..."];
                                                   }
                                                 } catch (const std::exception &error) {
                                                   debugLog(@"Preview descriptor parse failed: %s", error.what());
                                                 }
                                               },
                                               [self]() {
                                                 debugLog(@"Preview stream active.");
                                                 _previewRunning = true;
                                                 [self updateButtons];
                                                 [_previewView setEmptyMessage:@"Waiting for video from iPhone..."];
                                                 [self setStatus:@"Preview streaming."];
                                               },
                                               [self](const std::string &message) {
                                                 debugLog(@"Preview stream error=%@", nsString(message));
                                                 _previewRunning = false;
                                                 _previewRenderer->reset();
                                                 [_previewView clearFrameWithMessage:@"No stream from phone."];
                                                 [self updateButtons];
                                                 [self setStatus:nsString(message)];
                                                 if (_previewDesired) {
                                                   reashoot::core::CommandResult transient;
                                                   transient.exitCode = 1;
                                                   transient.output = message;
                                                   [self schedulePreviewRetryAfterFailure:transient attempt:0 automatic:YES fallback:@"Preview stream failed."];
                                                 }
                                               });
    if (!started) {
      debugLog(@"Preview stream client failed to start.");
      [_previewView clearFrameWithMessage:@"Could not open preview stream."];
      [self setStatus:@"Could not open preview stream."];
    }
    }];
  }];
}

- (void)stopPreview {
  debugLog(@"Stopping preview. running=%d accessUnits=%llu frames=%llu", _previewRunning, _previewAccessUnitCount, _previewFrameCount);
  _previewDesired = false;
  _previewClient->stop();
  _previewRenderer->reset();
  _previewRunning = false;
  [_previewView clearFrameWithMessage:@"Preview stopped."];
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

- (void)stopRecordingForIntegration {
  debugLog(@"Integration stop recording requested.");
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Stopping recording for integration settings=%s", redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Stopping iPhone recording..."];
  _activeCommand = _camera->stop(settings, [self](reashoot::core::CommandResult result) {
    debugLog(@"Integration stop completed exit=%d output=%@ error=%@",
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
    if (!recordings.empty()) {
      _phoneVideos.insert(_phoneVideos.begin(), recordings.front());
      [self renderPhoneVideos];
      [self setStatus:@"Recording stopped. Use Videos on iPhone or the API to download or delete it."];
      return;
    }
    [self setStatus:@"Recording stopped, but no recording descriptor was returned."];
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

- (void)downloadRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording
                directory:(const std::string &)downloadDirectory
       revealDownloadedFile:(BOOL)revealDownloadedFile {
  reashoot::core::RemoteCameraSettings settings = [self settings];
  std::string resolvedDirectory = downloadDirectory.empty() ? reashoot::desktop::defaultDownloadDirectory() : downloadDirectory;
  debugLog(@"Downloading recording id=%s filename=%s directory=%s settings=%s",
           recording.id.c_str(),
           recording.filename.c_str(),
           resolvedDirectory.c_str(),
           redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Downloading iPhone video..."];
  _activeCommand = _camera->downloadRecording(settings,
                                              recording,
                                              resolvedDirectory,
                                              [self](const std::string &line) {
                                                debugLog(@"Download progress line=%@", nsString(redactedText(line)));
                                                std::string status = reashoot::core::progressStatusText(line);
                                                if (!status.empty()) {
                                                  [self setStatus:nsString(status)];
                                                }
                                              },
                                              [self, revealDownloadedFile](reashoot::core::CommandResult result) {
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
                                                if (revealDownloadedFile) {
                                                  [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:nsString(path)]]];
                                                }
                                                [self setStatus:[NSString stringWithFormat:@"Downloaded %@", nsString(path)]];
                                              });
}

- (void)downloadRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording {
  std::string downloadDirectory = stdString(_downloadField.stringValue);
  if (downloadDirectory.empty()) {
    downloadDirectory = reashoot::desktop::defaultDownloadDirectory();
    _downloadField.stringValue = nsString(downloadDirectory);
  }
  [self downloadRecording:recording directory:downloadDirectory revealDownloadedFile:YES];
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

- (NSString *)timestampTextForRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording {
  NSString *createdAt = nsString(recording.createdAt);
  if (createdAt.length > 0) {
    NSISO8601DateFormatter *isoFormatter = [[NSISO8601DateFormatter alloc] init];
    NSDate *date = [isoFormatter dateFromString:createdAt];
    if (date) {
      NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
      formatter.dateStyle = NSDateFormatterMediumStyle;
      formatter.timeStyle = NSDateFormatterShortStyle;
      return [formatter stringFromDate:date];
    }
    return createdAt;
  }
  return nsString(reashoot::desktop::recordingTimestampFallback(recording));
}

- (NSString *)byteCountTextForRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording {
  long long bytes = std::atoll(recording.byteCount.c_str());
  return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSURL *)thumbnailURLForRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording {
  const std::string url = reashoot::desktop::recordingThumbnailURL([self settings], recording);
  if (url.empty()) {
    return nil;
  }
  return [NSURL URLWithString:nsString(url)];
}

- (void)loadThumbnailForRecording:(const reashoot::core::RemoteRecordingDescriptor &)recording imageView:(NSImageView *)imageView {
  NSURL *url = [self thumbnailURLForRecording:recording];
  if (!url) {
    return;
  }
  [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error || data.length == 0) {
      debugLog(@"Thumbnail load failed id=%s error=%@", recording.id.c_str(), error.localizedDescription ?: @"empty");
      return;
    }
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (!image) {
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      imageView.image = image;
    });
  }] resume];
}

- (void)buildVideosWindowIfNeeded {
  if (_videosWindow) {
    return;
  }
  _videosWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 480)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
  _videosWindow.title = @"Videos on iPhone";
  _videosWindow.releasedWhenClosed = NO;

  NSView *content = _videosWindow.contentView;
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

  NSStackView *header = [NSStackView stackViewWithViews:@[]];
  header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  header.alignment = NSLayoutAttributeCenterY;
  header.spacing = 8;
  [root addArrangedSubview:header];
  [header.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;
  NSTextField *title = makeLabel(@"Videos stored on the iPhone");
  [title setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [header addArrangedSubview:title];
  NSButton *refreshButton = makeButton(@"Refresh", self, @selector(refreshPhoneVideos:));
  [header addArrangedSubview:refreshButton];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scrollView.hasVerticalScroller = YES;
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  [root addArrangedSubview:scrollView];
  [scrollView.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32].active = YES;
  [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:340].active = YES;

  _videosList = [NSStackView stackViewWithViews:@[]];
  _videosList.orientation = NSUserInterfaceLayoutOrientationVertical;
  _videosList.alignment = NSLayoutAttributeLeading;
  _videosList.spacing = 10;
  _videosList.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
  _videosList.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = _videosList;
  [_videosList.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor].active = YES;
}

- (void)renderPhoneVideos {
  for (NSView *view in _videosList.arrangedSubviews.copy) {
    [_videosList removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  if (_phoneVideos.empty()) {
    [_videosList addArrangedSubview:makeLabel(@"No videos are currently stored on the iPhone.")];
    return;
  }
  for (size_t index = 0; index < _phoneVideos.size(); ++index) {
    const auto &recording = _phoneVideos[index];
    NSStackView *row = [NSStackView stackViewWithViews:@[]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *thumbnail = [[NSImageView alloc] initWithFrame:NSZeroRect];
    thumbnail.imageScaling = NSImageScaleProportionallyUpOrDown;
    thumbnail.image = [NSImage imageNamed:NSImageNameQuickLookTemplate];
    [thumbnail.widthAnchor constraintEqualToConstant:96].active = YES;
    [thumbnail.heightAnchor constraintEqualToConstant:64].active = YES;
    [row addArrangedSubview:thumbnail];
    [self loadThumbnailForRecording:recording imageView:thumbnail];

    NSStackView *details = [NSStackView stackViewWithViews:@[]];
    details.orientation = NSUserInterfaceLayoutOrientationVertical;
    details.alignment = NSLayoutAttributeLeading;
    details.spacing = 3;
    NSTextField *filename = makeLabel(nsString(recording.filename));
    NSTextField *metadata = makeLabel([NSString stringWithFormat:@"%@ - %@", [self timestampTextForRecording:recording], [self byteCountTextForRecording:recording]]);
    metadata.textColor = NSColor.secondaryLabelColor;
    [details addArrangedSubview:filename];
    [details addArrangedSubview:metadata];
    [row addArrangedSubview:details];
    [details.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;

    NSButton *downloadButton = makeButton(@"Download", self, @selector(downloadPhoneVideo:));
    downloadButton.tag = static_cast<NSInteger>(index);
    NSButton *deleteButton = makeButton(@"Delete", self, @selector(deletePhoneVideo:));
    deleteButton.tag = static_cast<NSInteger>(index);
    [row addArrangedSubview:downloadButton];
    [row addArrangedSubview:deleteButton];
    [_videosList addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:_videosList.widthAnchor constant:-16].active = YES;
  }
}

- (void)showPhoneVideos:(id)sender {
  (void)sender;
  debugLog(@"Videos on iPhone clicked.");
  [self buildVideosWindowIfNeeded];
  [_videosWindow makeKeyAndOrderFront:nil];
  [self refreshPhoneVideos:nil];
}

- (void)refreshPhoneVideos:(id)sender {
  (void)sender;
  if (![self requireHostAndToken]) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  debugLog(@"Listing phone videos settings=%s", redactedSettingsSummary(settings).c_str());
  [self setStatus:@"Checking videos on iPhone..."];
  _activeCommand = _camera->listRecordings(settings, [self](reashoot::core::CommandResult result) {
    debugLog(@"List phone videos completed exit=%d output=%@ error=%@",
             result.exitCode,
             nsString(redactedText(result.output)),
             nsString(redactedText(result.errorMessage)));
    if (result.exitCode != 0) {
      [self setStatusFromResult:result fallback:@"Could not list recordings."];
      return;
    }
    _phoneVideos = reashoot::desktop::parseRecordingDescriptors(result.output);
    debugLog(@"List phone videos parsed %zu recording(s).", _phoneVideos.size());
    [self renderPhoneVideos];
    [self setStatus:_phoneVideos.empty() ? @"No videos on the iPhone." : @"Videos on iPhone refreshed."];
  });
}

- (void)downloadPhoneVideo:(NSButton *)sender {
  const NSInteger index = sender.tag;
  if (index < 0 || static_cast<size_t>(index) >= _phoneVideos.size()) {
    return;
  }
  [self downloadRecording:_phoneVideos[static_cast<size_t>(index)]];
}

- (void)deletePhoneVideo:(NSButton *)sender {
  const NSInteger index = sender.tag;
  if (index < 0 || static_cast<size_t>(index) >= _phoneVideos.size()) {
    return;
  }
  const auto recording = _phoneVideos[static_cast<size_t>(index)];
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Delete video from iPhone?";
  alert.informativeText = [NSString stringWithFormat:@"Delete %@ from the iPhone?", nsString(recording.filename)];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = [self settings];
  [self setStatus:@"Deleting iPhone video..."];
  _activeCommand = _camera->deleteRecording(settings, recording.id, [self](reashoot::core::CommandResult result) {
    [self setStatusFromResult:result fallback:@"Video deleted from iPhone."];
    if (result.exitCode == 0) {
      [self refreshPhoneVideos:nil];
    }
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
