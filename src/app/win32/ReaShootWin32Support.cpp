#include "ReaShootWin32Support.h"

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <mutex>

namespace reashoot::win32app {
namespace {

bool gDebugLogging = false;
std::mutex gLogMutex;

std::filesystem::path debugLogPath() {
  wchar_t *localAppData = nullptr;
  std::filesystem::path base;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &localAppData)) && localAppData) {
    base = localAppData;
    CoTaskMemFree(localAppData);
  } else {
    base = std::filesystem::temp_directory_path();
  }
  base /= L"ReaShoot";
  std::error_code ec;
  std::filesystem::create_directories(base, ec);
  return base / L"ReaShoot-debug.log";
}

HKEY openSettingsKey(bool create) {
  HKEY key = nullptr;
  const REGSAM access = KEY_READ | KEY_WRITE;
  if (create) {
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\ReaShoot", 0, nullptr, 0, access, nullptr, &key, nullptr) !=
        ERROR_SUCCESS) {
      return nullptr;
    }
    return key;
  }
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\ReaShoot", 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return nullptr;
  }
  return key;
}

} // namespace

std::wstring widen(const std::string &value) {
  if (value.empty()) {
    return {};
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (length <= 0) {
    return {};
  }
  std::wstring output(static_cast<size_t>(length - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), length);
  return output;
}

std::string narrow(const std::wstring &value) {
  if (value.empty()) {
    return {};
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (length <= 0) {
    return {};
  }
  std::string output(static_cast<size_t>(length - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, output.data(), length, nullptr, nullptr);
  return output;
}

void initializeDebugLogging(bool enabled) {
  gDebugLogging = enabled;
  if (!gDebugLogging) {
    return;
  }
  debugLog("Debug logging enabled. pid=" + std::to_string(GetCurrentProcessId()));
}

bool debugLoggingEnabled() { return gDebugLogging; }

void debugLog(const std::string &message) {
  if (!gDebugLogging) {
    return;
  }
  std::lock_guard<std::mutex> lock(gLogMutex);
  const std::string line = "[ReaShoot] " + message + "\n";
  fputs(line.c_str(), stderr);
  static std::filesystem::path path = debugLogPath();
  std::ofstream log(path, std::ios::app);
  if (log) {
    log << line;
  }
}

std::string helperExecutablePath() {
  wchar_t modulePath[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, modulePath, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return "reashoot-win.exe";
  }
  std::filesystem::path executable(modulePath);
  return narrow((executable.parent_path() / L"reashoot-win.exe").wstring());
}

std::string localComputerName() {
  wchar_t buffer[256] = {};
  DWORD size = static_cast<DWORD>(std::size(buffer));
  if (GetComputerNameExW(ComputerNameDnsHostname, buffer, &size) && buffer[0]) {
    return narrow(std::wstring(buffer, size));
  }
  size = static_cast<DWORD>(std::size(buffer));
  if (GetComputerNameW(buffer, &size) && buffer[0]) {
    return narrow(std::wstring(buffer, size));
  }
  return "Windows PC";
}

std::string settingsGet(const std::string &key) {
  HKEY handle = openSettingsKey(false);
  if (!handle) {
    return {};
  }
  const std::wstring name = widen(key);
  DWORD type = 0;
  DWORD bytes = 0;
  std::string result;
  if (RegQueryValueExW(handle, name.c_str(), nullptr, &type, nullptr, &bytes) == ERROR_SUCCESS && type == REG_SZ &&
      bytes >= sizeof(wchar_t)) {
    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    if (RegQueryValueExW(handle, name.c_str(), nullptr, nullptr, reinterpret_cast<LPBYTE>(value.data()), &bytes) ==
        ERROR_SUCCESS) {
      while (!value.empty() && value.back() == L'\0') {
        value.pop_back();
      }
      result = narrow(value);
    }
  }
  RegCloseKey(handle);
  return result;
}

void settingsSet(const std::string &key, const std::string &value) {
  HKEY handle = openSettingsKey(true);
  if (!handle) {
    return;
  }
  const std::wstring name = widen(key);
  const std::wstring data = widen(value);
  RegSetValueExW(handle, name.c_str(), 0, REG_SZ, reinterpret_cast<const BYTE *>(data.c_str()),
                 static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(handle);
}

void settingsRemove(const std::string &key) {
  HKEY handle = openSettingsKey(false);
  if (!handle) {
    return;
  }
  RegDeleteValueW(handle, widen(key).c_str());
  RegCloseKey(handle);
}

std::string chooseDirectory(HWND owner, const std::string &currentDirectory) {
  IFileOpenDialog *dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return {};
  }
  std::string chosen;
  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
  }
  if (!currentDirectory.empty()) {
    IShellItem *item = nullptr;
    if (SUCCEEDED(SHCreateItemFromParsingName(widen(currentDirectory).c_str(), nullptr, IID_PPV_ARGS(&item))) && item) {
      dialog->SetFolder(item);
      item->Release();
    }
  }
  if (SUCCEEDED(dialog->Show(owner))) {
    IShellItem *result = nullptr;
    if (SUCCEEDED(dialog->GetResult(&result)) && result) {
      wchar_t *path = nullptr;
      if (SUCCEEDED(result->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
        chosen = narrow(path);
        CoTaskMemFree(path);
      }
      result->Release();
    }
  }
  dialog->Release();
  return chosen;
}

void revealInExplorer(const std::string &path) {
  if (path.empty()) {
    return;
  }
  const std::wstring wide = widen(path);
  if (std::filesystem::exists(path)) {
    const std::wstring parameters = L"/select,\"" + wide + L"\"";
    ShellExecuteW(nullptr, L"open", L"explorer.exe", parameters.c_str(), nullptr, SW_SHOWNORMAL);
    return;
  }
  ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

} // namespace reashoot::win32app
