#import "ReaShootMacUI.h"

namespace {

NSString *nsString(const std::string &value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

NSAttributedString *buttonTitle(NSString *title, NSColor *foreground, BOOL bold) {
  NSFont *font = bold ? [NSFont boldSystemFontOfSize:NSFont.systemFontSize] : [NSFont systemFontOfSize:NSFont.systemFontSize];
  return [[NSAttributedString alloc] initWithString:title ?: @""
                                        attributes:@{
                                          NSForegroundColorAttributeName: foreground ?: NSColor.controlTextColor,
                                          NSFontAttributeName: font,
                                        }];
}

void selectPopupItem(NSPopUpButton *popup, NSString *title, NSString *fallback) {
  NSString *candidate = title.length > 0 ? title : fallback;
  if (candidate.length == 0) {
    return;
  }
  if ([popup itemWithTitle:candidate]) {
    [popup selectItemWithTitle:candidate];
  } else if (fallback.length > 0 && [popup itemWithTitle:fallback]) {
    [popup selectItemWithTitle:fallback];
  }
}

} // namespace

NSButton *makeButton(NSString *title, id target, SEL action) {
  NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
  button.bezelStyle = NSBezelStyleRounded;
  return button;
}

void applyRecordButtonAppearance(NSButton *button, bool recording, bool blinkOn) {
  NSString *title = nsString(reashoot::desktop::recordButtonTitle(recording));
  button.title = title;
  button.wantsLayer = YES;
  button.layer.cornerRadius = 6.0;
  if (recording) {
    NSColor *red = blinkOn ? NSColor.systemRedColor : [NSColor colorWithCalibratedRed:0.58 green:0.0 blue:0.0 alpha:1.0];
    button.bordered = NO;
    button.layer.backgroundColor = red.CGColor;
    button.attributedTitle = buttonTitle(title, NSColor.whiteColor, YES);
    return;
  }
  button.bordered = YES;
  button.layer.backgroundColor = NSColor.clearColor.CGColor;
  button.attributedTitle = buttonTitle(title, NSColor.controlTextColor, NO);
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

NSPopUpButton *makePopupFromChoices(const std::vector<reashoot::desktop::DesktopChoice> &choices) {
  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  for (const auto &choice : choices) {
    [popup addItemWithTitle:nsString(choice.title)];
    popup.lastItem.representedObject = nsString(choice.value);
  }
  return popup;
}

void selectPopupRepresentedValue(NSPopUpButton *popup, NSString *value, NSString *fallback) {
  NSString *candidate = value.length > 0 ? value : fallback;
  for (NSMenuItem *item in popup.itemArray) {
    NSString *represented = [item.representedObject isKindOfClass:NSString.class] ? item.representedObject : nil;
    if ((represented.length > 0 && [represented isEqualToString:candidate]) || [item.title isEqualToString:candidate]) {
      [popup selectItem:item];
      return;
    }
  }
  selectPopupItem(popup, candidate, fallback);
}

NSString *selectedPopupValue(NSPopUpButton *popup, NSString *fallback) {
  id represented = popup.selectedItem.representedObject;
  if ([represented isKindOfClass:NSString.class] && [represented length] > 0) {
    return represented;
  }
  return popup.titleOfSelectedItem ?: fallback;
}
