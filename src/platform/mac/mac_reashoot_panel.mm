#import "mac_reashoot_panel.h"

@interface ReaShootMacDockPanel ()
@property(nonatomic, strong) NSView *dockView;
@property(nonatomic, strong) NSView *previewView;
@property(nonatomic, strong) NSButton *iPhoneSetupButton;
@property(nonatomic, strong) NSButton *iPhonePendingButton;
@property(nonatomic, strong) NSButton *iPhoneDeleteAllButton;
@property(nonatomic, strong) NSWindow *iPhoneSetupWindow;
@property(nonatomic, strong) NSWindow *floatingPreviewWindow;
@property(nonatomic, strong) NSTextField *iPhoneHostField;
@property(nonatomic, strong) NSTextField *iPhoneTokenField;
@property(nonatomic, strong) NSTextField *iPhonePairingCodeField;
@property(nonatomic, strong) NSButton *iPhoneDiscoverButton;
@property(nonatomic, strong) NSButton *iPhonePairButton;
@property(nonatomic, strong) NSButton *iPhoneTestButton;
@property(nonatomic, strong) NSTextField *iPhoneSetupHostField;
@property(nonatomic, strong) NSTextField *iPhoneSetupTokenField;
@property(nonatomic, strong) NSTextField *iPhoneSetupPairingCodeField;
@property(nonatomic, strong) NSButton *iPhoneSetupDiscoverButton;
@property(nonatomic, strong) NSButton *iPhoneSetupPairButton;
@property(nonatomic, strong) NSButton *iPhoneSetupTestButton;
@property(nonatomic, strong) NSPopUpButton *iPhoneResolutionPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneFPSPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneOrientationPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneAspectPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneLensPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneZoomPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneLookPopup;
@property(nonatomic, strong) NSButton *iPhonePreviousLookButton;
@property(nonatomic, strong) NSButton *iPhoneNextLookButton;
@property(nonatomic, strong) NSTextField *formatLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@end

@implementation ReaShootMacDockPanel

static NSButton *makeButton(NSRect frame, NSString *title, id target, SEL action) {
  NSButton *button = [[NSButton alloc] initWithFrame:frame];
  button.title = title;
  button.bezelStyle = NSBezelStyleRounded;
  button.target = target;
  button.action = action;
  return button;
}

static NSString *displayTitleForRawFilterID(NSString *filterID) {
  NSString *name = [filterID hasPrefix:@"CI"] ? [filterID substringFromIndex:2] : filterID;
  NSMutableString *title = [NSMutableString stringWithString:@"CI: "];
  for (NSUInteger index = 0; index < name.length; ++index) {
    unichar character = [name characterAtIndex:index];
    if (index > 0) {
      unichar previous = [name characterAtIndex:index - 1];
      const BOOL previousIsLower = previous >= 'a' && previous <= 'z';
      const BOOL previousIsDigit = previous >= '0' && previous <= '9';
      const BOOL currentIsUpper = character >= 'A' && character <= 'Z';
      const BOOL currentIsDigit = character >= '0' && character <= '9';
      const BOOL currentIsLetter = (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z');
      if ((previousIsLower && currentIsUpper) ||
          (!previousIsDigit && currentIsDigit) ||
          (previousIsDigit && currentIsLetter)) {
        [title appendString:@" "];
      }
    }
    [title appendFormat:@"%C", character];
  }
  return title;
}

static void addRawCoreImageLookItems(NSPopUpButton *popup) {
  NSArray<NSString *> *rawFilterIDs = @[
    @"CIThermal", @"CIXRay", @"CIFalseColor", @"CIColorInvert", @"CIColorPosterize",
    @"CIColorThreshold", @"CIColorThresholdOtsu", @"CIVibrance", @"CIHueAdjust", @"CITemperatureAndTint",
    @"CIGloom", @"CISobelGradients", @"CIGaborGradients", @"CIMorphologyGradient", @"CIEdges",
    @"CIEdgeWork", @"CILineOverlay", @"CICannyEdgeDetector", @"CICrystallize", @"CIHexagonalPixellate",
    @"CIPixellate", @"CIPointillize", @"CIDotScreen", @"CICircularScreen", @"CILineScreen",
    @"CIHatchedScreen", @"CICMYKHalftone", @"CIKaleidoscope", @"CITriangleKaleidoscope", @"CITwirlDistortion",
    @"CIVortexDistortion", @"CILightTunnel", @"CIGlassDistortion", @"CIDisplacementDistortion"
  ];
  for (NSString *filterID in rawFilterIDs) {
    [popup addItemWithTitle:displayTitleForRawFilterID(filterID)];
    popup.lastItem.representedObject = [@"ci:" stringByAppendingString:filterID];
  }
}

- (instancetype)initWithTarget:(id)target
                          host:(NSString *)host
                         token:(NSString *)token
                    resolution:(NSString *)resolution
                           fps:(NSString *)fps
                   orientation:(NSString *)orientation
                        aspect:(NSString *)aspect
                          lens:(NSString *)lens
                          zoom:(NSString *)zoom
                          look:(NSString *)look
                    statusText:(NSString *)statusText {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSRect frame = NSMakeRect(0, 0, 640, 480);
  self.dockView = [[NSView alloc] initWithFrame:frame];
  self.dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.dockView.wantsLayer = YES;

  self.previewView = [[NSView alloc] initWithFrame:NSMakeRect(0, 130, frame.size.width, frame.size.height - 130)];
  self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.previewView.wantsLayer = YES;
  [self.dockView addSubview:self.previewView];

  self.iPhoneSetupButton = makeButton(NSMakeRect(frame.size.width - 112, 101, 100, 24), @"iPhone Setup", target, @selector(showIPhoneSetup:));
  self.iPhoneSetupButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [self.dockView addSubview:self.iPhoneSetupButton];

  self.iPhoneDeleteAllButton = makeButton(NSMakeRect(frame.size.width - 216, 101, 96, 24), @"Delete All", target, @selector(deleteAllPendingIPhoneRecordings));
  self.iPhoneDeleteAllButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [self.dockView addSubview:self.iPhoneDeleteAllButton];

  self.iPhonePendingButton = makeButton(NSMakeRect(frame.size.width - 328, 101, 104, 24), @"Pending...", target, @selector(restoreIPhoneRecording));
  self.iPhonePendingButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [self.dockView addSubview:self.iPhonePendingButton];

  self.iPhoneHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 127, (frame.size.width - 36) / 2.0, 22)];
  self.iPhoneHostField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneHostField.placeholderString = @"iPhone host, e.g. kevin-long-iphone.local";
  self.iPhoneHostField.stringValue = host ?: @"";
  self.iPhoneHostField.target = target;
  self.iPhoneHostField.action = @selector(iPhoneSettingsChanged:);
  self.iPhoneHostField.hidden = YES;
  [self.dockView addSubview:self.iPhoneHostField];

  self.iPhoneTokenField = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneHostField.frame) + 12, 127, (frame.size.width - 36) / 2.0, 22)];
  self.iPhoneTokenField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneTokenField.placeholderString = @"Pairing token";
  self.iPhoneTokenField.stringValue = token ?: @"";
  self.iPhoneTokenField.target = target;
  self.iPhoneTokenField.action = @selector(iPhoneSettingsChanged:);
  self.iPhoneTokenField.hidden = YES;
  [self.dockView addSubview:self.iPhoneTokenField];

  const CGFloat buttonWidth = 88.0;
  self.iPhonePairingCodeField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 101, frame.size.width - 24 - (buttonWidth * 3.0) - 18.0, 22)];
  self.iPhonePairingCodeField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhonePairingCodeField.placeholderString = @"Pairing code from iPhone";
  self.iPhonePairingCodeField.hidden = YES;
  [self.dockView addSubview:self.iPhonePairingCodeField];

  CGFloat buttonX = NSMaxX(self.iPhonePairingCodeField.frame) + 6.0;
  self.iPhoneDiscoverButton = makeButton(NSMakeRect(buttonX, 101, buttonWidth, 22), @"Discover", target, @selector(discoverIPhone:));
  self.iPhoneDiscoverButton.hidden = YES;
  [self.dockView addSubview:self.iPhoneDiscoverButton];

  buttonX += buttonWidth + 6.0;
  self.iPhonePairButton = makeButton(NSMakeRect(buttonX, 101, buttonWidth, 22), @"Pair", target, @selector(pairIPhone:));
  self.iPhonePairButton.hidden = YES;
  [self.dockView addSubview:self.iPhonePairButton];

  buttonX += buttonWidth + 6.0;
  self.iPhoneTestButton = makeButton(NSMakeRect(buttonX, 101, buttonWidth, 22), @"Test", target, @selector(testIPhoneConnection:));
  self.iPhoneTestButton.hidden = YES;
  [self.dockView addSubview:self.iPhoneTestButton];

  self.iPhoneDiscoverButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  self.iPhonePairButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  self.iPhoneTestButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;

  const CGFloat popupWidth = (frame.size.width - 64.0) / 6.0;
  self.iPhoneResolutionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 75, popupWidth, 24) pullsDown:NO];
  [self.iPhoneResolutionPopup addItemsWithTitles:@[ @"4K", @"1080p", @"720p" ]];
  [self.iPhoneResolutionPopup selectItemWithTitle:resolution ?: @"4K"];
  self.iPhoneResolutionPopup.target = target;
  self.iPhoneResolutionPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneResolutionPopup];

  self.iPhoneFPSPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneResolutionPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
  [self.iPhoneFPSPopup addItemsWithTitles:@[ @"24", @"30", @"60" ]];
  [self.iPhoneFPSPopup selectItemWithTitle:fps ?: @"30"];
  self.iPhoneFPSPopup.target = target;
  self.iPhoneFPSPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneFPSPopup];

  self.iPhoneOrientationPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneFPSPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
  [self.iPhoneOrientationPopup addItemWithTitle:@"Portrait"];
  self.iPhoneOrientationPopup.lastItem.representedObject = @"portrait";
  [self.iPhoneOrientationPopup addItemWithTitle:@"Landscape R"];
  self.iPhoneOrientationPopup.lastItem.representedObject = @"landscapeRight";
  [self.iPhoneOrientationPopup addItemWithTitle:@"Landscape L"];
  self.iPhoneOrientationPopup.lastItem.representedObject = @"landscapeLeft";
  NSInteger orientationIndex = [self.iPhoneOrientationPopup indexOfItemWithRepresentedObject:orientation ?: @"portrait"];
  if (orientationIndex >= 0) {
    [self.iPhoneOrientationPopup selectItemAtIndex:orientationIndex];
  }
  self.iPhoneOrientationPopup.target = target;
  self.iPhoneOrientationPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneOrientationPopup];

  self.iPhoneAspectPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneOrientationPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
  [self.iPhoneAspectPopup addItemsWithTitles:@[ @"9:16", @"16:9", @"1:1", @"4:5" ]];
  [self.iPhoneAspectPopup selectItemWithTitle:aspect ?: @"9:16"];
  self.iPhoneAspectPopup.target = target;
  self.iPhoneAspectPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneAspectPopup];

  self.iPhoneLensPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneAspectPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
  [self.iPhoneLensPopup addItemWithTitle:@"Wide"];
  self.iPhoneLensPopup.lastItem.representedObject = @"wide";
  [self.iPhoneLensPopup addItemWithTitle:@"Ultra Wide"];
  self.iPhoneLensPopup.lastItem.representedObject = @"ultrawide";
  [self.iPhoneLensPopup addItemWithTitle:@"Tele"];
  self.iPhoneLensPopup.lastItem.representedObject = @"telephoto";
  [self.iPhoneLensPopup addItemWithTitle:@"Auto"];
  self.iPhoneLensPopup.lastItem.representedObject = @"auto";
  NSInteger lensIndex = [self.iPhoneLensPopup indexOfItemWithRepresentedObject:lens ?: @"wide"];
  if (lensIndex >= 0) {
    [self.iPhoneLensPopup selectItemAtIndex:lensIndex];
  }
  self.iPhoneLensPopup.target = target;
  self.iPhoneLensPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneLensPopup];

  self.iPhoneZoomPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneLensPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
  [self.iPhoneZoomPopup addItemWithTitle:@"0.5x"];
  self.iPhoneZoomPopup.lastItem.representedObject = @"0.5";
  [self.iPhoneZoomPopup addItemWithTitle:@"1x"];
  self.iPhoneZoomPopup.lastItem.representedObject = @"1.0";
  [self.iPhoneZoomPopup addItemWithTitle:@"2x"];
  self.iPhoneZoomPopup.lastItem.representedObject = @"2.0";
  [self.iPhoneZoomPopup addItemWithTitle:@"3x"];
  self.iPhoneZoomPopup.lastItem.representedObject = @"3.0";
  NSInteger zoomIndex = [self.iPhoneZoomPopup indexOfItemWithRepresentedObject:zoom ?: @"1.0"];
  if (zoomIndex >= 0) {
    [self.iPhoneZoomPopup selectItemAtIndex:zoomIndex];
  }
  self.iPhoneZoomPopup.target = target;
  self.iPhoneZoomPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneZoomPopup];

  self.iPhonePreviousLookButton = makeButton(NSMakeRect(12, 49, 52, 24), @"Prev", target, @selector(previousIPhoneLook:));
  [self.dockView addSubview:self.iPhonePreviousLookButton];

  self.iPhoneLookPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, 49, frame.size.width - 140, 24) pullsDown:NO];
  [self.iPhoneLookPopup addItemWithTitle:@"Natural"];
  self.iPhoneLookPopup.lastItem.representedObject = @"natural";
  [self.iPhoneLookPopup addItemWithTitle:@"Warm Vintage"];
  self.iPhoneLookPopup.lastItem.representedObject = @"warmVintage";
  [self.iPhoneLookPopup addItemWithTitle:@"Cool Blue"];
  self.iPhoneLookPopup.lastItem.representedObject = @"coolBlue";
  [self.iPhoneLookPopup addItemWithTitle:@"High Contrast B&W"];
  self.iPhoneLookPopup.lastItem.representedObject = @"highContrastBW";
  [self.iPhoneLookPopup addItemWithTitle:@"Faded Film"];
  self.iPhoneLookPopup.lastItem.representedObject = @"fadedFilm";
  [self.iPhoneLookPopup addItemWithTitle:@"Dream Glow"];
  self.iPhoneLookPopup.lastItem.representedObject = @"dreamGlow";
  [self.iPhoneLookPopup addItemWithTitle:@"Noir"];
  self.iPhoneLookPopup.lastItem.representedObject = @"noir";
  [self.iPhoneLookPopup addItemWithTitle:@"Saturated Pop"];
  self.iPhoneLookPopup.lastItem.representedObject = @"saturatedPop";
  [self.iPhoneLookPopup addItemWithTitle:@"Bleach Bypass"];
  self.iPhoneLookPopup.lastItem.representedObject = @"bleachBypass";
  [self.iPhoneLookPopup addItemWithTitle:@"Sepia"];
  self.iPhoneLookPopup.lastItem.representedObject = @"sepia";
  [self.iPhoneLookPopup addItemWithTitle:@"Instant Photo"];
  self.iPhoneLookPopup.lastItem.representedObject = @"instantPhoto";
  [self.iPhoneLookPopup addItemWithTitle:@"Chrome"];
  self.iPhoneLookPopup.lastItem.representedObject = @"chrome";
  [self.iPhoneLookPopup addItemWithTitle:@"Tonal"];
  self.iPhoneLookPopup.lastItem.representedObject = @"tonal";
  [self.iPhoneLookPopup addItemWithTitle:@"Silvertone"];
  self.iPhoneLookPopup.lastItem.representedObject = @"silvertone";
  [self.iPhoneLookPopup addItemWithTitle:@"Dramatic Warm"];
  self.iPhoneLookPopup.lastItem.representedObject = @"dramaticWarm";
  [self.iPhoneLookPopup addItemWithTitle:@"Dramatic Cool"];
  self.iPhoneLookPopup.lastItem.representedObject = @"dramaticCool";
  [self.iPhoneLookPopup addItemWithTitle:@"Soft Matte"];
  self.iPhoneLookPopup.lastItem.representedObject = @"softMatte";
  [self.iPhoneLookPopup addItemWithTitle:@"Comic Book"];
  self.iPhoneLookPopup.lastItem.representedObject = @"comicBook";
  [self.iPhoneLookPopup addItemWithTitle:@"VHS"];
  self.iPhoneLookPopup.lastItem.representedObject = @"vhs";
  [self.iPhoneLookPopup addItemWithTitle:@"Music Video Pop"];
  self.iPhoneLookPopup.lastItem.representedObject = @"musicVideoPop";
  addRawCoreImageLookItems(self.iPhoneLookPopup);
  NSInteger lookIndex = [self.iPhoneLookPopup indexOfItemWithRepresentedObject:look ?: @"natural"];
  [self.iPhoneLookPopup selectItemAtIndex:lookIndex >= 0 ? lookIndex : 0];
  self.iPhoneLookPopup.target = target;
  self.iPhoneLookPopup.action = @selector(profileSelectionChanged:);
  [self.dockView addSubview:self.iPhoneLookPopup];

  self.iPhoneNextLookButton = makeButton(NSMakeRect(frame.size.width - 64, 49, 52, 24), @"Next", target, @selector(nextIPhoneLook:));
  [self.dockView addSubview:self.iPhoneNextLookButton];

  self.iPhoneResolutionPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneFPSPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneOrientationPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneAspectPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneLensPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneZoomPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhoneLookPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  self.iPhonePreviousLookButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  self.iPhoneNextLookButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;

  self.formatLabel = [NSTextField labelWithString:@"Format: unavailable"];
  self.formatLabel.frame = NSMakeRect(12, 29, frame.size.width - 24, 18);
  self.formatLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  [self.dockView addSubview:self.formatLabel];

  self.statusLabel = [NSTextField labelWithString:statusText ?: @"Idle"];
  self.statusLabel.frame = NSMakeRect(12, 9, frame.size.width - 24, 18);
  self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  [self.dockView addSubview:self.statusLabel];

  return self;
}

- (void)showSetupWindowWithTarget:(id)target host:(NSString *)host token:(NSString *)token {
  if (!self.iPhoneSetupWindow) {
    NSRect frame = NSMakeRect(0, 0, 520, 150);
    self.iPhoneSetupWindow = [[NSWindow alloc] initWithContentRect:frame
                                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
    self.iPhoneSetupWindow.releasedWhenClosed = NO;
    self.iPhoneSetupWindow.title = @"ReaShoot Setup";
    NSView *content = self.iPhoneSetupWindow.contentView;

    self.iPhoneSetupHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 112, 240, 22)];
    self.iPhoneSetupHostField.placeholderString = @"iPhone host, e.g. kevin-long-iphone.local";
    self.iPhoneSetupHostField.target = target;
    self.iPhoneSetupHostField.action = @selector(iPhoneSettingsChanged:);
    [content addSubview:self.iPhoneSetupHostField];

    self.iPhoneSetupTokenField = [[NSTextField alloc] initWithFrame:NSMakeRect(268, 112, 240, 22)];
    self.iPhoneSetupTokenField.placeholderString = @"Pairing token";
    self.iPhoneSetupTokenField.target = target;
    self.iPhoneSetupTokenField.action = @selector(iPhoneSettingsChanged:);
    [content addSubview:self.iPhoneSetupTokenField];

    self.iPhoneSetupPairingCodeField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 78, 220, 22)];
    self.iPhoneSetupPairingCodeField.placeholderString = @"Pairing code from iPhone";
    [content addSubview:self.iPhoneSetupPairingCodeField];

    self.iPhoneSetupDiscoverButton = makeButton(NSMakeRect(244, 77, 82, 24), @"Discover", target, @selector(discoverIPhone:));
    [content addSubview:self.iPhoneSetupDiscoverButton];

    self.iPhoneSetupPairButton = makeButton(NSMakeRect(338, 77, 76, 24), @"Pair", target, @selector(pairIPhone:));
    [content addSubview:self.iPhoneSetupPairButton];

    self.iPhoneSetupTestButton = makeButton(NSMakeRect(426, 77, 76, 24), @"Test", target, @selector(testIPhoneConnection:));
    [content addSubview:self.iPhoneSetupTestButton];

    NSTextField *hint = [NSTextField labelWithString:@"Launch the iPhone app, Discover, enter pairing code, Pair, then Test."];
    hint.frame = NSMakeRect(12, 24, 496, 36);
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:hint];
  }
  self.iPhoneSetupHostField.stringValue = host ?: @"";
  self.iPhoneSetupTokenField.stringValue = token ?: @"";
  [self.iPhoneSetupWindow makeKeyAndOrderFront:nil];
}

- (void)showFloatingPreview {
  if (!self.floatingPreviewWindow) {
    self.floatingPreviewWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 720, 540)
                                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
    self.floatingPreviewWindow.title = @"ReaShoot Preview";
    self.floatingPreviewWindow.releasedWhenClosed = NO;
  }
  self.dockView.frame = self.floatingPreviewWindow.contentView.bounds;
  self.dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.floatingPreviewWindow.contentView = self.dockView;
  [self.floatingPreviewWindow makeKeyAndOrderFront:nil];
}

- (void)hideFloatingPreview {
  if (!self.floatingPreviewWindow) {
    return;
  }
  [self.floatingPreviewWindow orderOut:nil];
  if (self.floatingPreviewWindow.contentView == self.dockView) {
    self.floatingPreviewWindow.contentView = [[NSView alloc] initWithFrame:self.floatingPreviewWindow.contentView.bounds];
  }
}

@end
