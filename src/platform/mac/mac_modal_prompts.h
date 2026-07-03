#pragma once

#include "../../core/ui_interfaces.h"

#import <Cocoa/Cocoa.h>

#include <memory>

typedef NS_ENUM(NSInteger, ReaShootStoppedRecordingChoice) {
  ReaShootStoppedRecordingChoiceDownload = 0,
  ReaShootStoppedRecordingChoiceDelete = 1,
};

@interface ReaShootMacModalPrompts : NSObject
+ (NSDictionary<NSString *, id> *)choosePendingRecordingAction:(NSArray<NSDictionary<NSString *, NSString *> *> *)recordings;
+ (BOOL)confirmDeleteRecordingNamed:(NSString *)filename;
+ (BOOL)confirmDeleteAllRecordingsCount:(NSUInteger)count;
+ (ReaShootStoppedRecordingChoice)chooseStoppedRecordingActionForFilename:(NSString *)filename;
@end

namespace reashoot::platform::mac {

std::unique_ptr<core::ModalPrompts> createModalPrompts();

} // namespace reashoot::platform::mac
