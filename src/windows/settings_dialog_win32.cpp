#ifndef _WIN32
#error "settings_dialog_win32.cpp is only intended for Windows builds."
#endif

#include "settings_dialog_win32.h"

#include <string>
#include <vector>

namespace reaphone {

namespace {

constexpr wchar_t kDialogClassName[] = L"ReaPhoneVideoSettingsDialog";

enum ControlId : int {
  kIdHost = 1001,
  kIdToken,
  kIdControlPort,
  kIdHttpPort,
  kIdResolution,
  kIdFps,
  kIdOk,
  kIdCancel,
  kFieldCount = 6,
};

struct Field {
  const wchar_t *label;
  std::string PluginSettings::*member;
};

const Field kFields[kFieldCount] = {
    {L"iPhone host:", &PluginSettings::host},
    {L"Pairing token:", &PluginSettings::token},
    {L"Control port:", &PluginSettings::controlPort},
    {L"HTTP port:", &PluginSettings::httpPort},
    {L"Resolution:", &PluginSettings::resolution},
    {L"FPS:", &PluginSettings::fps},
};

struct DialogState {
  PluginSettings *settings = nullptr;
  bool ok = false;
  bool done = false;
  HWND edits[kFieldCount] = {0};
};

std::wstring widen(const std::string &value) {
  if (value.empty()) {
    return {};
  }
  const int needed = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(static_cast<std::size_t>(needed), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), needed);
  return result;
}

std::string narrow(const std::wstring &value) {
  if (value.empty()) {
    return {};
  }
  const int needed =
      WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(static_cast<std::size_t>(needed), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), needed, nullptr,
                      nullptr);
  return result;
}

std::string readEditText(HWND edit) {
  const int length = GetWindowTextLengthW(edit);
  std::wstring buffer(static_cast<std::size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(edit, buffer.data(), length + 1);
  buffer.resize(static_cast<std::size_t>(copied));
  return narrow(buffer);
}

void createControls(HWND dialog, HINSTANCE instance, DialogState *state) {
  HFONT font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));

  const int labelX = 12;
  const int editX = 130;
  const int editWidth = 260;
  const int rowHeight = 30;
  const int firstY = 14;

  for (int i = 0; i < kFieldCount; ++i) {
    const int y = firstY + i * rowHeight;
    HWND label = CreateWindowExW(0, L"STATIC", kFields[i].label, WS_CHILD | WS_VISIBLE, labelX, y + 3, 112, 20,
                                 dialog, nullptr, instance, nullptr);
    SendMessageW(label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);

    const DWORD extra = (i == kIdToken - kIdHost) ? ES_PASSWORD : 0;
    HWND edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", widen(state->settings->*(kFields[i].member)).c_str(),
                                WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | extra, editX, y, editWidth, 22,
                                dialog, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdHost + i)), instance,
                                nullptr);
    SendMessageW(edit, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    state->edits[i] = edit;
  }

  const int buttonsY = firstY + kFieldCount * rowHeight + 6;
  HWND ok = CreateWindowExW(0, L"BUTTON", L"Save", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, editX + 96,
                            buttonsY, 80, 26, dialog, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdOk)), instance,
                            nullptr);
  SendMessageW(ok, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  HWND cancel =
      CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | WS_TABSTOP, editX + 182, buttonsY, 80, 26,
                      dialog, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdCancel)), instance, nullptr);
  SendMessageW(cancel, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

void commit(HWND dialog, DialogState *state) {
  for (int i = 0; i < kFieldCount; ++i) {
    state->settings->*(kFields[i].member) = readEditText(state->edits[i]);
  }
  state->ok = true;
  state->done = true;
  DestroyWindow(dialog);
}

LRESULT CALLBACK dialogProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  if (message == WM_CREATE) {
    auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
    auto *state = reinterpret_cast<DialogState *>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    createControls(hwnd, create->hInstance, state);
    return 0;
  }

  auto *state = reinterpret_cast<DialogState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

  switch (message) {
  case WM_COMMAND: {
    const int id = LOWORD(wParam);
    if (id == kIdOk && state) {
      commit(hwnd, state);
      return 0;
    }
    if (id == kIdCancel) {
      if (state) {
        state->done = true;
      }
      DestroyWindow(hwnd);
      return 0;
    }
    break;
  }
  case WM_CLOSE:
    if (state) {
      state->done = true;
    }
    DestroyWindow(hwnd);
    return 0;
  default:
    break;
  }
  return DefWindowProcW(hwnd, message, wParam, lParam);
}

bool ensureClassRegistered(HINSTANCE instance) {
  static bool registered = false;
  if (registered) {
    return true;
  }
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &dialogProc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
  wc.lpszClassName = kDialogClassName;
  registered = RegisterClassExW(&wc) != 0;
  return registered;
}

} // namespace

bool showSettingsDialog(HWND parent, HINSTANCE instance, PluginSettings &settings) {
  if (!ensureClassRegistered(instance)) {
    return false;
  }

  DialogState state;
  state.settings = &settings;

  const int width = 430;
  const int height = 14 + kFieldCount * 30 + 6 + 26 + 48;

  RECT parentRect{};
  int x = CW_USEDEFAULT;
  int y = CW_USEDEFAULT;
  if (parent && GetWindowRect(parent, &parentRect)) {
    x = parentRect.left + ((parentRect.right - parentRect.left) - width) / 2;
    y = parentRect.top + ((parentRect.bottom - parentRect.top) - height) / 2;
  }

  HWND dialog = CreateWindowExW(WS_EX_DLGMODALFRAME, kDialogClassName, L"ReaPhoneVideo Settings",
                                WS_POPUP | WS_CAPTION | WS_SYSMENU, x, y, width, height, parent, nullptr, instance,
                                &state);
  if (!dialog) {
    return false;
  }

  const bool hadParent = parent != nullptr;
  if (hadParent) {
    EnableWindow(parent, FALSE);
  }
  ShowWindow(dialog, SW_SHOW);
  UpdateWindow(dialog);

  MSG msg{};
  while (!state.done && GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(dialog, &msg)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }

  if (hadParent) {
    EnableWindow(parent, TRUE);
    SetActiveWindow(parent);
  }
  return state.ok;
}

} // namespace reaphone
