#import "mac_modal_prompts.h"

@implementation ReaShootMacModalPrompts

+ (NSDictionary<NSString *, id> *)choosePendingRecordingAction:(NSArray<NSDictionary<NSString *, NSString *> *> *)recordings {
  if (recordings.count == 0) {
    return nil;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Pending iPhone Recordings";
  alert.informativeText = @"Choose a pending iPhone recording to download and insert at the current edit cursor, or delete it from the phone.";
  [alert addButtonWithTitle:@"Download"];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];

  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 420, 26) pullsDown:NO];
  for (NSDictionary<NSString *, NSString *> *recording in recordings) {
    NSString *filename = recording[@"filename"] ?: recording[@"id"] ?: @"recording.mov";
    NSString *byteCount = recording[@"byteCount"] ?: @"0";
    [popup addItemWithTitle:[NSString stringWithFormat:@"%@ (%@ bytes)", filename, byteCount]];
    popup.lastItem.representedObject = recording;
  }
  alert.accessoryView = popup;
  NSModalResponse response = [alert runModal];
  if (response == NSAlertThirdButtonReturn) {
    return nil;
  }
  NSDictionary<NSString *, NSString *> *recording = popup.selectedItem.representedObject;
  if (!recording) {
    return nil;
  }
  NSString *action = response == NSAlertSecondButtonReturn ? @"delete" : @"download";
  return @{@"action": action, @"recording": recording};
}

+ (BOOL)confirmDeleteRecordingNamed:(NSString *)filename {
  NSAlert *confirm = [[NSAlert alloc] init];
  confirm.messageText = @"Delete pending iPhone recording?";
  confirm.informativeText = [NSString stringWithFormat:@"Delete %@ from the iPhone without downloading it?", filename ?: @"the selected iPhone video"];
  [confirm addButtonWithTitle:@"Delete"];
  [confirm addButtonWithTitle:@"Cancel"];
  return [confirm runModal] == NSAlertFirstButtonReturn;
}

+ (BOOL)confirmDeleteAllRecordingsCount:(NSUInteger)count {
  NSAlert *confirm = [[NSAlert alloc] init];
  confirm.messageText = @"Delete all pending iPhone recordings?";
  confirm.informativeText = [NSString stringWithFormat:@"Delete %lu pending video(s) from the iPhone without downloading them?", (unsigned long)count];
  [confirm addButtonWithTitle:@"Delete All"];
  [confirm addButtonWithTitle:@"Cancel"];
  return [confirm runModal] == NSAlertFirstButtonReturn;
}

+ (ReaShootStoppedRecordingChoice)chooseStoppedRecordingActionForFilename:(NSString *)filename {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Download iPhone video?";
  alert.informativeText = [NSString stringWithFormat:@"Download %@ into the REAPER project, or delete it from the iPhone without downloading?", filename ?: @"the stopped iPhone video"];
  [alert addButtonWithTitle:@"Download"];
  [alert addButtonWithTitle:@"Delete from iPhone"];
  if ([alert runModal] == NSAlertFirstButtonReturn) {
    return ReaShootStoppedRecordingChoiceDownload;
  }

  NSAlert *confirm = [[NSAlert alloc] init];
  confirm.alertStyle = NSAlertStyleWarning;
  confirm.messageText = @"Delete iPhone recording?";
  confirm.informativeText = [NSString stringWithFormat:@"This will permanently delete %@ from the iPhone without downloading it.", filename ?: @"the stopped iPhone video"];
  [confirm addButtonWithTitle:@"Delete"];
  [confirm addButtonWithTitle:@"Cancel"];
  return [confirm runModal] == NSAlertFirstButtonReturn ? ReaShootStoppedRecordingChoiceDelete : ReaShootStoppedRecordingChoiceDownload;
}

@end
