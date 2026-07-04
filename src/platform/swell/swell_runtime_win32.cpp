#ifdef _WIN32

#include "swell_runtime.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>

namespace reashoot::platform::swell {
namespace {

constexpr const char *kHostClassName = "ReaShootSwellHost";
HWND g_currentParent = nullptr;
HFONT g_defaultGuiFont = nullptr;

HINSTANCE moduleHandle() {
  return GetModuleHandleA(nullptr);
}

LOGFONTA defaultMessageFont() {
  NONCLIENTMETRICSA metrics = {};
  metrics.cbSize = sizeof(metrics);
  if (SystemParametersInfoA(SPI_GETNONCLIENTMETRICS, metrics.cbSize, &metrics, 0)) {
    return metrics.lfMessageFont;
  }

  LOGFONTA fallback = {};
  fallback.lfHeight = -11;
  fallback.lfWeight = FW_NORMAL;
  lstrcpynA(fallback.lfFaceName, "Segoe UI", LF_FACESIZE);
  return fallback;
}

HFONT defaultGuiFont() {
  if (!g_defaultGuiFont) {
    LOGFONTA font = defaultMessageFont();
    g_defaultGuiFont = CreateFontIndirectA(&font);
  }
  return g_defaultGuiFont ? g_defaultGuiFont : reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
}

HWND applyDefaultControlFont(HWND hwnd) {
  if (hwnd) {
    SendMessageA(hwnd, WM_SETFONT, reinterpret_cast<WPARAM>(defaultGuiFont()), TRUE);
  }
  return hwnd;
}

HBRUSH dialogBrush(int level) {
  return GetSysColorBrush(level > 0 ? COLOR_3DLIGHT : COLOR_BTNFACE);
}

void prepareTextDC(HDC hdc) {
  if (!hdc) {
    return;
  }
  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, GetSysColor(COLOR_BTNTEXT));
  SelectObject(hdc, defaultGuiFont());
}

SIZE measureText(const char *text, HFONT font = nullptr) {
  SIZE size = {};
  if (!text || !text[0]) {
    return size;
  }

  HDC hdc = GetDC(g_currentParent ? g_currentParent : nullptr);
  if (!hdc) {
    return size;
  }
  HGDIOBJ previousFont = SelectObject(hdc, font ? font : defaultGuiFont());
  GetTextExtentPoint32A(hdc, text, static_cast<int>(std::strlen(text)), &size);
  if (previousFont) {
    SelectObject(hdc, previousFont);
  }
  ReleaseDC(g_currentParent ? g_currentParent : nullptr, hdc);
  return size;
}

void growTopLevelParentToFit(HWND parent, int neededClientRight, int neededClientBottom) {
  if (!parent || GetParent(parent)) {
    return;
  }
  RECT client = {};
  RECT window = {};
  if (!GetClientRect(parent, &client) || !GetWindowRect(parent, &window)) {
    return;
  }

  const int growWidth = (std::max)(0, neededClientRight - static_cast<int>(client.right));
  const int growHeight = (std::max)(0, neededClientBottom - static_cast<int>(client.bottom));
  if (growWidth == 0 && growHeight == 0) {
    return;
  }

  SetWindowPos(parent,
               nullptr,
               window.left,
               window.top,
               (window.right - window.left) + growWidth,
               (window.bottom - window.top) + growHeight,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void growControlToFit(HWND hwnd, int minimumWidth, int minimumHeight = 0) {
  if (!hwnd) {
    return;
  }
  HWND parent = GetParent(hwnd);
  RECT rect = {};
  if (!parent || !GetWindowRect(hwnd, &rect)) {
    return;
  }
  MapWindowPoints(HWND_DESKTOP, parent, reinterpret_cast<POINT *>(&rect), 2);

  const int currentWidth = rect.right - rect.left;
  const int currentHeight = rect.bottom - rect.top;
  const int newWidth = (std::max)(currentWidth, minimumWidth);
  const int newHeight = (std::max)(currentHeight, minimumHeight);
  if (newWidth != currentWidth || newHeight != currentHeight) {
    SetWindowPos(hwnd,
                 nullptr,
                 0,
                 0,
                 newWidth,
                 newHeight,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
  }
  growTopLevelParentToFit(parent, rect.left + newWidth + 12, rect.top + newHeight + 12);
}

HWND finalizeButton(HWND hwnd, const char *label) {
  applyDefaultControlFont(hwnd);
  SIZE textSize = measureText(label);
  growControlToFit(hwnd, 0, textSize.cy + 12);
  return hwnd;
}

HWND finalizeLabel(HWND hwnd, const char *label) {
  applyDefaultControlFont(hwnd);
  SIZE textSize = measureText(label);
  growControlToFit(hwnd, 0, textSize.cy + 6);
  return hwnd;
}

LRESULT CALLBACK hostWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  DLGPROC proc = reinterpret_cast<DLGPROC>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto *create = reinterpret_cast<CREATESTRUCT *>(lParam);
    proc = reinterpret_cast<DLGPROC>(create ? create->lpCreateParams : nullptr);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(proc));
  }
  if (proc) {
    LRESULT result = proc(hwnd, message, wParam, lParam);
    if (result != 0 || message == WM_COMMAND || message == WM_PAINT || message == WM_CLOSE ||
        message == WM_ERASEBKGND || message == WM_LBUTTONDOWN || message == WM_LBUTTONUP ||
        message == WM_MOUSEMOVE || message == WM_DESTROY) {
      return result;
    }
  }
  if (message == WM_CTLCOLORSTATIC || message == WM_CTLCOLORBTN) {
    prepareTextDC(reinterpret_cast<HDC>(wParam));
    return reinterpret_cast<LRESULT>(dialogBrush(0));
  }
  return DefWindowProc(hwnd, message, wParam, lParam);
}

void registerHostClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASSA windowClass = {};
  windowClass.lpfnWndProc = hostWindowProc;
  windowClass.hInstance = moduleHandle();
  windowClass.hCursor = LoadCursor(nullptr, IDC_ARROW);
  windowClass.hbrBackground = dialogBrush(0);
  windowClass.lpszClassName = kHostClassName;
  RegisterClassA(&windowClass);
  registered = true;
}

DWORD childStyle(DWORD extra = 0) {
  return WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | extra;
}

} // namespace

bool initializeSwellRuntime() {
  registerHostClass();
  return true;
}

bool hasSwellRuntime() {
  return true;
}

bool hasSwellDrawingRuntime() {
  return true;
}

void makeSetCurParms(float, float, float, float, HWND parent, bool, bool) {
  g_currentParent = parent;
}

HWND createDialog(void *, const char *, HWND parent, DLGPROC proc, LPARAM param) {
  initializeSwellRuntime();
  DWORD style = parent ? (WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS)
                       : (WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
  HWND hwnd = CreateWindowExA(0,
                              kHostClassName,
                              "ReaShoot",
                              style,
                              CW_USEDEFAULT,
                              CW_USEDEFAULT,
                              parent ? 700 : 540,
                              parent ? 460 : 300,
                              parent,
                              nullptr,
                              moduleHandle(),
                              reinterpret_cast<void *>(proc));
  if (hwnd && param != 0) {
    SetWindowLongPtr(hwnd, DWLP_USER, param);
  }
  g_currentParent = hwnd;
  return hwnd;
}

HWND getDlgItem(HWND parent, int controlID) {
  return parent ? GetDlgItem(parent, controlID) : nullptr;
}

void showWindow(HWND hwnd, int command) {
  if (hwnd) {
    ShowWindow(hwnd, command);
  }
}

void setWindowPos(HWND hwnd, HWND insertAfter, int x, int y, int width, int height, int flags) {
  if (hwnd) {
    SetWindowPos(hwnd, insertAfter, x, y, width, height, flags);
  }
}

bool getWindowRect(HWND hwnd, RECT *rect) {
  return hwnd && rect && GetWindowRect(hwnd, rect);
}

LONG_PTR getWindowLong(HWND hwnd, int index) {
  return hwnd ? GetWindowLongPtr(hwnd, index) : 0;
}

LONG_PTR setWindowLong(HWND hwnd, int index, LONG_PTR value) {
  return hwnd ? SetWindowLongPtr(hwnd, index, value) : 0;
}

HWND setCapture(HWND hwnd) {
  return SetCapture(hwnd);
}

void releaseCapture() {
  ReleaseCapture();
}

void getCursorPos(POINT *point) {
  if (point) {
    GetCursorPos(point);
  }
}

HWND makeButton(int isDefault, const char *label, int controlID, int x, int y, int width, int height, int flags) {
  DWORD style = childStyle(BS_PUSHBUTTON | WS_TABSTOP | (isDefault ? BS_DEFPUSHBUTTON : 0) | static_cast<DWORD>(flags));
  return finalizeButton(CreateWindowExA(0,
                                        "BUTTON",
                                        label ? label : "",
                                        style,
                                        x,
                                        y,
                                        width,
                                        height,
                                        g_currentParent,
                                        reinterpret_cast<HMENU>(static_cast<intptr_t>(controlID)),
                                        moduleHandle(),
                                        nullptr),
                        label);
}

HWND makeEditField(int controlID, int x, int y, int width, int height, int flags) {
  HWND field = applyDefaultControlFont(CreateWindowExA(WS_EX_CLIENTEDGE,
                                                       "EDIT",
                                                       "",
                                                       childStyle(ES_AUTOHSCROLL | WS_TABSTOP | static_cast<DWORD>(flags)),
                                                       x,
                                                       y,
                                                       width,
                                                       height,
                                                       g_currentParent,
                                                       reinterpret_cast<HMENU>(static_cast<intptr_t>(controlID)),
                                                       moduleHandle(),
                                                       nullptr));
  SIZE textSize = measureText("Mg");
  growControlToFit(field, 0, textSize.cy + 12);
  return field;
}

HWND makeLabel(int, const char *label, int controlID, int x, int y, int width, int height, int flags) {
  return finalizeLabel(CreateWindowExA(0,
                                       "STATIC",
                                       label ? label : "",
                                       childStyle(SS_LEFT | static_cast<DWORD>(flags)),
                                       x,
                                       y,
                                       width,
                                       height,
                                       g_currentParent,
                                       reinterpret_cast<HMENU>(static_cast<intptr_t>(controlID)),
                                       moduleHandle(),
                                       nullptr),
                       label);
}

HWND makeCombo(int controlID, int x, int y, int width, int height, int flags) {
  return applyDefaultControlFont(CreateWindowExA(0,
                                                 "COMBOBOX",
                                                 "",
                                                 childStyle(WS_TABSTOP | WS_VSCROLL | static_cast<DWORD>(flags)),
                                                 x,
                                                 y,
                                                 width,
                                                 height,
                                                 g_currentParent,
                                                 reinterpret_cast<HMENU>(static_cast<intptr_t>(controlID)),
                                                 moduleHandle(),
                                                 nullptr));
}

bool setDlgItemText(HWND parent, int controlID, const char *text) {
  if (!parent) {
    return false;
  }
  if (controlID == 0) {
    return SetWindowTextA(parent, text ? text : "") != 0;
  }
  return SetDlgItemTextA(parent, controlID, text ? text : "") != 0;
}

bool getDlgItemText(HWND parent, int controlID, char *text, int textLength) {
  if (!parent || !text || textLength <= 0) {
    return false;
  }
  text[0] = '\0';
  return GetDlgItemTextA(parent, controlID, text, textLength) > 0;
}

int comboAddString(HWND parent, int controlID, const char *text) {
  HWND combo = getDlgItem(parent, controlID);
  if (!combo) {
    return -1;
  }
  const int result = static_cast<int>(SendMessageA(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text ? text : "")));
  return result;
}

void comboSetCurSel(HWND parent, int controlID, int selection) {
  HWND combo = getDlgItem(parent, controlID);
  if (combo) {
    SendMessageA(combo, CB_SETCURSEL, static_cast<WPARAM>(selection), 0);
  }
}

int comboGetCurSel(HWND parent, int controlID) {
  HWND combo = getDlgItem(parent, controlID);
  return combo ? static_cast<int>(SendMessageA(combo, CB_GETCURSEL, 0, 0)) : -1;
}

bool getClientRect(HWND hwnd, RECT *rect) {
  return hwnd && rect && GetClientRect(hwnd, rect);
}

bool invalidateRect(HWND hwnd, const RECT *rect, bool eraseBackground) {
  return hwnd && InvalidateRect(hwnd, rect, eraseBackground ? TRUE : FALSE);
}

bool setTimer(HWND hwnd, UINT_PTR timerID, UINT rateMs) {
  return SetTimer(hwnd, timerID, rateMs, nullptr) != 0;
}

bool killTimer(HWND hwnd, UINT_PTR timerID) {
  return KillTimer(hwnd, timerID) != 0;
}

HDC beginPaint(HWND hwnd, PAINTSTRUCT *paint) {
  return BeginPaint(hwnd, paint);
}

bool endPaint(HWND hwnd, PAINTSTRUCT *paint) {
  return EndPaint(hwnd, paint) != 0;
}

void fillDialogBackground(HDC hdc, const RECT *rect, int level) {
  if (!hdc || !rect) {
    return;
  }
  FillRect(hdc, rect, dialogBrush(level));
}

bool drawFrame(HDC output, int x, int y, int width, int height, const void *bits, int sourceWidth, int sourceHeight) {
  if (!output || !bits || sourceWidth <= 0 || sourceHeight <= 0 || width <= 0 || height <= 0) {
    return false;
  }
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = sourceWidth;
  info.bmiHeader.biHeight = -sourceHeight;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  const int previousMode = SetStretchBltMode(output, HALFTONE);
  POINT previousOrigin = {};
  SetBrushOrgEx(output, 0, 0, &previousOrigin);
  const bool ok = StretchDIBits(output,
                                x,
                                y,
                                width,
                                height,
                                0,
                                0,
                                sourceWidth,
                                sourceHeight,
                                bits,
                                &info,
                                DIB_RGB_COLORS,
                                SRCCOPY) != GDI_ERROR;
  SetBrushOrgEx(output, previousOrigin.x, previousOrigin.y, nullptr);
  if (previousMode != 0) {
    SetStretchBltMode(output, previousMode);
  }
  return ok;
}

bool drawText(HDC output, const char *text, RECT *rect, int align) {
  prepareTextDC(output);
  return output && text && rect && DrawTextA(output, text, -1, rect, align) != 0;
}

int measureTextWidth(const char *text) {
  return measureText(text).cx;
}

HFONT createFont(int height, int weight, const char *faceName) {
  LOGFONTA font = defaultMessageFont();
  font.lfHeight = height;
  font.lfWeight = weight;
  if (faceName && faceName[0]) {
    lstrcpynA(font.lfFaceName, faceName, LF_FACESIZE);
  }
  return CreateFontIndirectA(&font);
}

LRESULT sendMessage(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  return hwnd ? SendMessage(hwnd, message, wParam, lParam) : 0;
}

void deleteObject(HGDIOBJ object) {
  if (object) {
    DeleteObject(object);
  }
}

} // namespace reashoot::platform::swell

#endif
