#import "ReaShootMacSupport.h"

#include <cstdarg>

#include <unistd.h>

namespace {

bool gDebugLogging = false;
NSFileHandle *gDebugLogFile = nil;

NSString *debugLogPath() {
  NSURL *logsURL = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
  logsURL = [[logsURL URLByAppendingPathComponent:@"Logs" isDirectory:YES] URLByAppendingPathComponent:@"ReaShoot" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:logsURL withIntermediateDirectories:YES attributes:nil error:nil];
  return [[logsURL URLByAppendingPathComponent:@"ReaShoot-debug.log"] path];
}

} // namespace

NSString *nsString(const std::string &value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string stdString(NSString *value) {
  return value.UTF8String ? value.UTF8String : "";
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

std::string localComputerName() {
  NSString *localizedName = NSHost.currentHost.localizedName;
  if (localizedName.length > 0) {
    return stdString(localizedName);
  }
  NSString *hostName = NSHost.currentHost.name;
  if (hostName.length > 0) {
    return stdString(hostName);
  }
  char buffer[256] = {};
  if (gethostname(buffer, sizeof(buffer) - 1) == 0 && buffer[0]) {
    return buffer;
  }
  return "Mac";
}
