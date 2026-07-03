#import "mac_modal_prompts.h"

#include <memory>
#include <vector>

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

namespace reashoot::platform::mac {

namespace {

NSDictionary<NSString *, NSString *> *dictionaryFromRecording(const core::RemoteRecordingDescriptor &recording) {
  return @{
    @"id" : [NSString stringWithUTF8String:recording.id.c_str()] ?: @"",
    @"filename" : [NSString stringWithUTF8String:recording.filename.c_str()] ?: @"recording.mov",
    @"byteCount" : [NSString stringWithUTF8String:recording.byteCount.c_str()] ?: @"0",
    @"downloadPath" : [NSString stringWithUTF8String:recording.downloadPath.c_str()] ?: @"",
    @"checksum" : [NSString stringWithUTF8String:recording.checksum.c_str()] ?: @"",
  };
}

class MacModalPrompts final : public core::ModalPrompts {
public:
  core::PendingRecordingChoice choosePendingRecordingAction(const std::vector<core::RemoteRecordingDescriptor> &recordings) override {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *items = [NSMutableArray arrayWithCapacity:recordings.size()];
    for (const core::RemoteRecordingDescriptor &recording : recordings) {
      [items addObject:dictionaryFromRecording(recording)];
    }
    NSDictionary<NSString *, id> *choice = [ReaShootMacModalPrompts choosePendingRecordingAction:items];
    core::PendingRecordingChoice result;
    if (!choice) {
      return result;
    }
    NSString *action = choice[@"action"];
    NSDictionary<NSString *, NSString *> *recording = choice[@"recording"];
    result.recordingID = recording[@"id"].UTF8String ?: "";
    if ([action isEqualToString:@"download"]) {
      result.action = core::PendingRecordingAction::Download;
    } else if ([action isEqualToString:@"delete"]) {
      result.action = core::PendingRecordingAction::Delete;
    }
    return result;
  }

  bool confirmDeleteRecordingNamed(const std::string &filename) override {
    return [ReaShootMacModalPrompts confirmDeleteRecordingNamed:[NSString stringWithUTF8String:filename.c_str()]];
  }

  bool confirmDeleteAllRecordingsCount(size_t count) override {
    return [ReaShootMacModalPrompts confirmDeleteAllRecordingsCount:count];
  }

  core::StoppedRecordingAction chooseStoppedRecordingActionForFilename(const std::string &filename) override {
    ReaShootStoppedRecordingChoice choice =
        [ReaShootMacModalPrompts chooseStoppedRecordingActionForFilename:[NSString stringWithUTF8String:filename.c_str()]];
    return choice == ReaShootStoppedRecordingChoiceDelete
               ? core::StoppedRecordingAction::Delete
               : core::StoppedRecordingAction::Download;
  }
};

} // namespace

std::unique_ptr<core::ModalPrompts> createModalPrompts() {
  return std::make_unique<MacModalPrompts>();
}

} // namespace reashoot::platform::mac
