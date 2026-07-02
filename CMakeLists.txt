cmake_minimum_required(VERSION 3.22)

project(ReaPhoneVideo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(REAPHONE_REAPER_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/reaper-sdk/sdk" CACHE PATH "Path to the REAPER Extension SDK headers")
set(REAPHONE_REAPER_WDL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/reaper-sdk/WDL" CACHE PATH "Path to WDL/SWELL headers from the REAPER SDK")

add_library(reaphone_portability INTERFACE)
target_include_directories(reaphone_portability INTERFACE
  "${REAPHONE_REAPER_SDK_DIR}"
  "${REAPHONE_REAPER_WDL_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/desktop/reaper_plugin"
)
target_compile_features(reaphone_portability INTERFACE cxx_std_17)

add_library(reaphone_core
  desktop/core/reaphone/control_protocol.cpp
  desktop/core/reaphone/debug_logger.cpp
  desktop/core/reaphone/http_download.cpp
  desktop/core/reaphone/http_headers.cpp
  desktop/core/reaphone/json.cpp
  desktop/core/reaphone/plugin_settings.cpp
  desktop/core/reaphone/sha256.cpp
  desktop/core/reaphone/websocket.cpp
  desktop/core/reaphone/windows/control_client.cpp
  desktop/core/reaphone/windows/helper_launcher.cpp
  desktop/core/reaphone/windows/process_runner.cpp
  desktop/core/reaphone/windows/recording_downloader.cpp
)
target_include_directories(reaphone_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/desktop/core"
)
target_compile_features(reaphone_core PUBLIC cxx_std_17)

if(WIN32)
  target_link_libraries(reaphone_core PUBLIC ws2_32)
endif()

if(MSVC)
  target_compile_options(reaphone_core PRIVATE /W4 /permissive-)
else()
  target_compile_options(reaphone_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(WIN32)
  # The Windows control helper CLI, mirroring the macOS video-sync-mac tool. The
  # REAPER plugin launches it as a subprocess (via the process adapter) for each
  # pairing/control command.
  add_executable(video-sync-win
    desktop/helper/video_sync_win.cpp
  )
  target_link_libraries(video-sync-win PRIVATE reaphone_core)
endif()

include(CTest)
if(BUILD_TESTING)
  add_executable(reaphone_core_tests
    desktop/core/tests/http_headers_tests.cpp
  )
  target_link_libraries(reaphone_core_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_core_tests COMMAND reaphone_core_tests)

  add_executable(reaphone_websocket_tests
    desktop/core/tests/websocket_frame_tests.cpp
  )
  target_link_libraries(reaphone_websocket_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_websocket_tests COMMAND reaphone_websocket_tests)

  add_executable(reaphone_download_tests
    desktop/core/tests/download_tests.cpp
  )
  target_link_libraries(reaphone_download_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_download_tests COMMAND reaphone_download_tests)

  add_executable(reaphone_protocol_tests
    desktop/core/tests/protocol_tests.cpp
  )
  target_link_libraries(reaphone_protocol_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_protocol_tests COMMAND reaphone_protocol_tests)

  add_executable(reaphone_event_tests
    desktop/core/tests/event_tests.cpp
  )
  target_link_libraries(reaphone_event_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_event_tests COMMAND reaphone_event_tests)

  add_executable(reaphone_settings_tests
    desktop/core/tests/plugin_settings_tests.cpp
  )
  target_link_libraries(reaphone_settings_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_settings_tests COMMAND reaphone_settings_tests)

  add_executable(reaphone_logger_tests
    desktop/core/tests/debug_logger_tests.cpp
  )
  target_link_libraries(reaphone_logger_tests PRIVATE reaphone_core)
  add_test(NAME reaphone_logger_tests COMMAND reaphone_logger_tests)

  if(WIN32)
    add_executable(reaphone_process_tests
      desktop/core/tests/process_tests.cpp
    )
    target_link_libraries(reaphone_process_tests PRIVATE reaphone_core)
    add_test(NAME reaphone_process_tests COMMAND reaphone_process_tests)

    add_executable(reaphone_control_client_tests
      desktop/core/tests/control_client_tests.cpp
    )
    target_link_libraries(reaphone_control_client_tests PRIVATE reaphone_core)
    add_test(NAME reaphone_control_client_tests COMMAND reaphone_control_client_tests)

    add_executable(reaphone_helper_launcher_tests
      desktop/core/tests/helper_launcher_tests.cpp
    )
    target_link_libraries(reaphone_helper_launcher_tests PRIVATE reaphone_core)
    add_dependencies(reaphone_helper_launcher_tests video-sync-win)
    add_test(NAME reaphone_helper_launcher_tests COMMAND reaphone_helper_launcher_tests)

    add_executable(reaphone_recording_downloader_tests
      desktop/core/tests/recording_downloader_tests.cpp
    )
    target_link_libraries(reaphone_recording_downloader_tests PRIVATE reaphone_core)
    add_test(NAME reaphone_recording_downloader_tests COMMAND reaphone_recording_downloader_tests)
  endif()
endif()

if(WIN32)
  add_library(reaphonevideo MODULE
    src/windows/reaphonevideo_win_skeleton.cpp
  )
  target_link_libraries(reaphonevideo PRIVATE reaphone_portability)
  # REAPER only loads extension DLLs from UserPlugins whose filename starts
  # with "reaper_" (matching the macOS "reaper_video_recorder.dylib" convention),
  # so the output name must carry that prefix or REAPER silently ignores it.
  set_target_properties(reaphonevideo PROPERTIES
    PREFIX ""
    OUTPUT_NAME "reaper_reaphonevideo"
    SUFFIX ".dll"
  )

  if(MSVC)
    target_compile_options(reaphonevideo PRIVATE /W4 /permissive-)
  endif()

  install(TARGETS reaphonevideo
    RUNTIME DESTINATION "."
    LIBRARY DESTINATION "."
  )
else()
  add_custom_target(reaphonevideo_windows_skeleton
    SOURCES src/windows/reaphonevideo_win_skeleton.cpp
  )
endif()

add_custom_target(portability_matrix
  SOURCES docs/portability-matrix.md
)
