#pragma once

#include "../../desktop/desktop_app_model.h"

#import <Cocoa/Cocoa.h>

#include <string>
#include <vector>

NSButton *makeButton(NSString *title, id target, SEL action);
void applyRecordButtonAppearance(NSButton *button, bool recording, bool blinkOn);
NSTextField *makeLabel(NSString *text);
NSTextField *makeField(NSString *placeholder);
NSPopUpButton *makePopupFromChoices(const std::vector<reashoot::desktop::DesktopChoice> &choices);
void selectPopupRepresentedValue(NSPopUpButton *popup, NSString *value, NSString *fallback);
NSString *selectedPopupValue(NSPopUpButton *popup, NSString *fallback);
