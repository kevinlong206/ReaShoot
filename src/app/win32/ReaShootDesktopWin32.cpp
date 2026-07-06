#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "../../desktop/desktop_app_controller.h"

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  (void)instance;
  reashoot::desktop::DesktopAppController controller;
  controller.setPreviewDesired(false);
  MessageBoxW(nullptr,
              L"ReaShoot Windows desktop shell scaffold.\n\nShared desktop workflow state is linked and ready for a native WinUI/Win32 frontend.",
              L"ReaShoot",
              MB_OK | MB_ICONINFORMATION);
  return 0;
}
