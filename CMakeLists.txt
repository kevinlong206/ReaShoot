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
  desktop/core/reaphone/http_headers.cpp
  desktop/core/reaphone/websocket.cpp
)
target_include_directories(reaphone_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/desktop/core"
)
target_compile_features(reaphone_core PUBLIC cxx_std_17)

if(MSVC)
  target_compile_options(reaphone_core PRIVATE /W4 /permissive-)
else()
  target_compile_options(reaphone_core PRIVATE -Wall -Wextra -Wpedantic)
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
