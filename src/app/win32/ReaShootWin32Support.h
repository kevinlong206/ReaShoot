#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <string>

namespace reashoot::win32app {

// UTF-8 <-> UTF-16 conversion helpers for bridging the shared std::string core
// with the wide Win32 API.
std::wstring widen(const std::string &value);
std::string narrow(const std::wstring &value);

// Redacted debug logging. Enabled by passing -debug / --debug on the command
// line. Writes to stderr and %LOCALAPPDATA%\ReaShoot\ReaShoot-debug.log.
void initializeDebugLogging(bool enabled);
bool debugLoggingEnabled();
void debugLog(const std::string &message);

// Absolute path to the bundled reashoot-win.exe helper (sits next to the app
// executable).
std::string helperExecutablePath();

// A friendly name for this computer, used as the pairing client name.
std::string localComputerName();

// Persistent settings backed by HKCU\Software\ReaShoot.
std::string settingsGet(const std::string &key);
void settingsSet(const std::string &key, const std::string &value);
void settingsRemove(const std::string &key);

// Modern folder picker. Returns an empty string when the user cancels.
std::string chooseDirectory(HWND owner, const std::string &currentDirectory);

// Reveals a file in File Explorer with it selected.
void revealInExplorer(const std::string &path);

} // namespace reashoot::win32app
