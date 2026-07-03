cmake_minimum_required(VERSION 3.22)

project(ReaShoot LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(REASHOOT_REAPER_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/reaper-sdk/sdk" CACHE PATH "Path to the REAPER Extension SDK headers")
set(REASHOOT_REAPER_WDL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/reaper-sdk/WDL" CACHE PATH "Path to WDL/SWELL headers from the REAPER SDK")

# Real WebRTC preview support is backed by the webrtc-sdk/libwebrtc prebuilt
# (the libwebrtc C++ wrapper API), vendored under vendor/libwebrtc. It shares
# the WebRTC lineage of the iPhone app's LiveKit build, keeping codecs
# compatible. When the prebuilt is absent the plugin falls back to the stub
# receiver so the rest of the build still works.
option(REASHOOT_WITH_LIBWEBRTC "Build the libwebrtc-backed WebRTC preview receiver when the prebuilt is present" ON)
set(REASHOOT_LIBWEBRTC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/libwebrtc/extracted/libwebrtc-x64-release" CACHE PATH "Path to the extracted webrtc-sdk/libwebrtc prebuilt (include/ and lib/)")

set(REASHOOT_HAVE_LIBWEBRTC FALSE)
if(WIN32 AND REASHOOT_WITH_LIBWEBRTC)
  set(REASHOOT_LIBWEBRTC_INCLUDE "${REASHOOT_LIBWEBRTC_DIR}/include")
  set(REASHOOT_LIBWEBRTC_IMPLIB "${REASHOOT_LIBWEBRTC_DIR}/lib/libwebrtc.dll.lib")
  set(REASHOOT_LIBWEBRTC_DLL "${REASHOOT_LIBWEBRTC_DIR}/lib/libwebrtc.dll")
  if(EXISTS "${REASHOOT_LIBWEBRTC_INCLUDE}/libwebrtc.h" AND EXISTS "${REASHOOT_LIBWEBRTC_IMPLIB}")
    set(REASHOOT_HAVE_LIBWEBRTC TRUE)
    message(STATUS "ReaShoot: libwebrtc prebuilt found at ${REASHOOT_LIBWEBRTC_DIR}")
  else()
    message(WARNING "ReaShoot: REASHOOT_WITH_LIBWEBRTC is ON but no libwebrtc prebuilt at ${REASHOOT_LIBWEBRTC_DIR}; falling back to the stub receiver")
  endif()
endif()

add_library(reashoot_portability INTERFACE)
target_include_directories(reashoot_portability INTERFACE
  "${REASHOOT_REAPER_SDK_DIR}"
  "${REASHOOT_REAPER_WDL_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/desktop/reaper_plugin"
)
target_compile_features(reashoot_portability INTERFACE cxx_std_17)

add_library(reashoot_core
  desktop/core/reashoot/audio_align.cpp
  desktop/core/reashoot/control_protocol.cpp
  desktop/core/reashoot/debug_logger.cpp
  desktop/core/reashoot/http_download.cpp
  desktop/core/reashoot/http_headers.cpp
  desktop/core/reashoot/json.cpp
  desktop/core/reashoot/plugin_settings.cpp
  desktop/core/reashoot/sha256.cpp
  desktop/core/reashoot/webrtc_sdp.cpp
  desktop/core/reashoot/websocket.cpp
  desktop/core/reashoot/windows/control_client.cpp
  desktop/core/reashoot/windows/helper_launcher.cpp
  desktop/core/reashoot/windows/process_runner.cpp
  desktop/core/reashoot/windows/recording_downloader.cpp
)
target_include_directories(reashoot_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/desktop/core"
)
target_compile_features(reashoot_core PUBLIC cxx_std_17)

if(WIN32)
  target_link_libraries(reashoot_core PUBLIC ws2_32)
endif()

if(MSVC)
  target_compile_options(reashoot_core PRIVATE /W4 /permissive-)
else()
  target_compile_options(reashoot_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(WIN32)
  # The Windows control helper CLI, mirroring the macOS video-sync-mac tool. The
  # REAPER plugin launches it as a subprocess (via the process adapter) for each
  # pairing/control command.
  add_executable(reashoot-helper
    desktop/helper/reashoot_helper.cpp
  )
  target_link_libraries(reashoot-helper PRIVATE reashoot_core)
endif()

include(CTest)
if(BUILD_TESTING)
  add_executable(reashoot_core_tests
    desktop/core/tests/http_headers_tests.cpp
  )
  target_link_libraries(reashoot_core_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_core_tests COMMAND reashoot_core_tests)

  add_executable(reashoot_websocket_tests
    desktop/core/tests/websocket_frame_tests.cpp
  )
  target_link_libraries(reashoot_websocket_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_websocket_tests COMMAND reashoot_websocket_tests)

  add_executable(reashoot_download_tests
    desktop/core/tests/download_tests.cpp
  )
  target_link_libraries(reashoot_download_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_download_tests COMMAND reashoot_download_tests)

  add_executable(reashoot_protocol_tests
    desktop/core/tests/protocol_tests.cpp
  )
  target_link_libraries(reashoot_protocol_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_protocol_tests COMMAND reashoot_protocol_tests)

  add_executable(reashoot_event_tests
    desktop/core/tests/event_tests.cpp
  )
  target_link_libraries(reashoot_event_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_event_tests COMMAND reashoot_event_tests)

  add_executable(reashoot_settings_tests
    desktop/core/tests/plugin_settings_tests.cpp
  )
  target_link_libraries(reashoot_settings_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_settings_tests COMMAND reashoot_settings_tests)

  add_executable(reashoot_logger_tests
    desktop/core/tests/debug_logger_tests.cpp
  )
  target_link_libraries(reashoot_logger_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_logger_tests COMMAND reashoot_logger_tests)

  add_executable(reashoot_preview_tests
    desktop/core/tests/preview_tests.cpp
  )
  target_link_libraries(reashoot_preview_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_preview_tests COMMAND reashoot_preview_tests)

  add_executable(reashoot_webrtc_sdp_tests
    desktop/core/tests/webrtc_sdp_tests.cpp
  )
  target_link_libraries(reashoot_webrtc_sdp_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_webrtc_sdp_tests COMMAND reashoot_webrtc_sdp_tests)

  add_executable(reashoot_audio_align_tests
    desktop/core/tests/audio_align_tests.cpp
  )
  target_link_libraries(reashoot_audio_align_tests PRIVATE reashoot_core)
  add_test(NAME reashoot_audio_align_tests COMMAND reashoot_audio_align_tests)

  if(WIN32)
    add_executable(reashoot_process_tests
      desktop/core/tests/process_tests.cpp
    )
    target_link_libraries(reashoot_process_tests PRIVATE reashoot_core)
    add_test(NAME reashoot_process_tests COMMAND reashoot_process_tests)

    add_executable(reashoot_control_client_tests
      desktop/core/tests/control_client_tests.cpp
    )
    target_link_libraries(reashoot_control_client_tests PRIVATE reashoot_core)
    add_test(NAME reashoot_control_client_tests COMMAND reashoot_control_client_tests)

    add_executable(reashoot_helper_launcher_tests
      desktop/core/tests/helper_launcher_tests.cpp
    )
    target_link_libraries(reashoot_helper_launcher_tests PRIVATE reashoot_core)
    add_dependencies(reashoot_helper_launcher_tests reashoot-helper)
    add_test(NAME reashoot_helper_launcher_tests COMMAND reashoot_helper_launcher_tests)

    add_executable(reashoot_recording_downloader_tests
      desktop/core/tests/recording_downloader_tests.cpp
    )
    target_link_libraries(reashoot_recording_downloader_tests PRIVATE reashoot_core)
    add_test(NAME reashoot_recording_downloader_tests COMMAND reashoot_recording_downloader_tests)
  endif()
endif()

if(WIN32)
  add_library(reashoot MODULE
    src/windows/reashoot_win_skeleton.cpp
    src/windows/preview_panel_win32.cpp
    src/windows/settings_dialog_win32.cpp
  )
  target_link_libraries(reashoot PRIVATE reashoot_portability reashoot_core gdi32 user32)

  if(REASHOOT_HAVE_LIBWEBRTC)
    target_sources(reashoot PRIVATE src/windows/webrtc_receiver_libwebrtc.cpp)
    target_include_directories(reashoot PRIVATE "${REASHOOT_LIBWEBRTC_INCLUDE}")
    # LIB_WEBRTC_API_DLL selects __declspec(dllimport) in the libwebrtc headers;
    # REASHOOT_WITH_LIBWEBRTC gates the receiver factory in the plugin TU.
    target_compile_definitions(reashoot PRIVATE REASHOOT_WITH_LIBWEBRTC LIB_WEBRTC_API_DLL)
    target_link_libraries(reashoot PRIVATE "${REASHOOT_LIBWEBRTC_IMPLIB}")
    # Stage libwebrtc.dll next to the plugin so REAPER can load it at runtime.
    add_custom_command(TARGET reashoot POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${REASHOOT_LIBWEBRTC_DLL}" "$<TARGET_FILE_DIR:reashoot>/libwebrtc.dll"
      VERBATIM
    )
    install(FILES "${REASHOOT_LIBWEBRTC_DLL}" DESTINATION ".")
  endif()
  # REAPER only loads extension DLLs from UserPlugins whose filename starts
  # with "reaper_" (matching the macOS "reaper_video_recorder.dylib" convention),
  # so the output name must carry that prefix or REAPER silently ignores it.
  set_target_properties(reashoot PROPERTIES
    PREFIX ""
    OUTPUT_NAME "reaper_reashoot"
    SUFFIX ".dll"
  )

  if(MSVC)
    target_compile_options(reashoot PRIVATE /W4 /permissive-)
  endif()

  install(TARGETS reashoot
    RUNTIME DESTINATION "."
    LIBRARY DESTINATION "."
  )
else()
  add_custom_target(reashoot_windows_skeleton
    SOURCES src/windows/reashoot_win_skeleton.cpp
  )
endif()

add_custom_target(portability_matrix
  SOURCES docs/portability-matrix.md
)
