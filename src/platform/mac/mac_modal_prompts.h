#pragma once

#import <Cocoa/Cocoa.h>

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
