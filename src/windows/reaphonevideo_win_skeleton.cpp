#ifndef _WIN32
#error "reaphonevideo_win_skeleton.cpp is only intended for Windows builds."
#endif

#include "reaper_plugin.h"

#define REAPERAPI_IMPLEMENT
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_ShowConsoleMsg
#include "reaper_plugin_functions.h"

#include "reaphone_action_ids.h"

namespace {

int g_diagnosticCommand = 0;
reaper_plugin_info_t *g_reaper = nullptr;

bool hookCommand2(KbdSectionInfo *section, int command, int value, int valuehw, int relmode, HWND hwnd) {
  (void)section;
  (void)value;
  (void)valuehw;
  (void)relmode;
  (void)hwnd;

  if (command != g_diagnosticCommand) {
    return false;
  }

  if (ShowConsoleMsg) {
    ShowConsoleMsg("ReaPhoneVideo Windows skeleton loaded and handling actions.\n");
  }
  return true;
}

bool registerActions(reaper_plugin_info_t *rec) {
  custom_action_register_t diagnosticAction = {
      0,
      reaphone::actions::kWindowsDiagnosticId,
      reaphone::actions::kWindowsDiagnosticName,
      nullptr,
  };

  g_diagnosticCommand = rec->Register("custom_action", &diagnosticAction);
  return g_diagnosticCommand != 0 &&
         rec->Register("hookcommand2", reinterpret_cast<void *>(hookCommand2));
}

void unregisterActions(reaper_plugin_info_t *rec) {
  rec->Register("-hookcommand2", reinterpret_cast<void *>(hookCommand2));
}

} // namespace

extern "C" {

REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t *rec) {
  (void)hInstance;

  if (!rec) {
    if (g_reaper) {
      unregisterActions(g_reaper);
    }
    g_reaper = nullptr;
    return 0;
  }

  g_reaper = rec;
  if (REAPERAPI_LoadAPI(rec->GetFunc) != 0) {
    return 0;
  }

  return registerActions(rec) ? 1 : 0;
}

}
