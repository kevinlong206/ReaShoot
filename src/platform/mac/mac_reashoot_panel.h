#pragma once

#import <Cocoa/Cocoa.h>

@interface ReaShootMacDockPanel : NSObject
@property(nonatomic, strong, readonly) NSView *dockView;
@property(nonatomic, strong, readonly) NSView *previewView;
@property(nonatomic, strong, readonly) NSButton *iPhoneSetupButton;
@property(nonatomic, strong, readonly) NSButton *iPhonePendingButton;
@property(nonatomic, strong, readonly) NSButton *iPhoneDeleteAllButton;
@property(nonatomic, strong, readonly) NSWindow *iPhoneSetupWindow;
@property(nonatomic, strong, readonly) NSWindow *floatingPreviewWindow;
@property(nonatomic, strong, readonly) NSTextField *iPhoneHostField;
@property(nonatomic, strong, readonly) NSTextField *iPhoneTokenField;
@property(nonatomic, strong, readonly) NSTextField *iPhonePairingCodeField;
@property(nonatomic, strong, readonly) NSButton *iPhoneDiscoverButton;
@property(nonatomic, strong, readonly) NSButton *iPhonePairButton;
@property(nonatomic, strong, readonly) NSButton *iPhoneTestButton;
@property(nonatomic, strong, readonly) NSTextField *iPhoneSetupHostField;
@property(nonatomic, strong, readonly) NSTextField *iPhoneSetupTokenField;
@property(nonatomic, strong, readonly) NSTextField *iPhoneSetupPairingCodeField;
@property(nonatomic, strong, readonly) NSButton *iPhoneSetupDiscoverButton;
@property(nonatomic, strong, readonly) NSButton *iPhoneSetupPairButton;
@property(nonatomic, strong, readonly) NSButton *iPhoneSetupTestButton;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneResolutionPopup;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneFPSPopup;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneOrientationPopup;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneAspectPopup;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneLensPopup;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneZoomPopup;
@property(nonatomic, strong, readonly) NSPopUpButton *iPhoneLookPopup;
@property(nonatomic, strong, readonly) NSButton *iPhonePreviousLookButton;
@property(nonatomic, strong, readonly) NSButton *iPhoneNextLookButton;
@property(nonatomic, strong, readonly) NSTextField *formatLabel;
@property(nonatomic, strong, readonly) NSTextField *statusLabel;

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
                    statusText:(NSString *)statusText;
- (void)showSetupWindowWithTarget:(id)target host:(NSString *)host token:(NSString *)token;
- (void)showFloatingPreview;
- (void)hideFloatingPreview;
@end
