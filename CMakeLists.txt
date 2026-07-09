cmake_minimum_required(VERSION 3.21)

project(ReaShoot VERSION 0.1 LANGUAGES CXX)

if(APPLE)
  enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(REASHOOT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")
set(REASHOOT_SDK_DIR "${REASHOOT_ROOT}/vendor/reaper-sdk/sdk")
set(REASHOOT_WARNING_FLAGS)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  list(APPEND REASHOOT_WARNING_FLAGS -Wall -Wextra -Wno-unused-parameter)
endif()

file(GLOB REASHOOT_CORE_SOURCES CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/core/*.cpp")
file(GLOB REASHOOT_CORE_HEADERS CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/core/*.h")
file(GLOB REASHOOT_DESKTOP_SOURCES CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/desktop/*.cpp")
file(GLOB REASHOOT_DESKTOP_HEADERS CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/desktop/*.h")
file(GLOB REASHOOT_FFMPEG_SOURCES CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/platform/ffmpeg/*.cpp")
file(GLOB REASHOOT_FFMPEG_HEADERS CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/platform/ffmpeg/*.h")

add_library(reashoot_core STATIC ${REASHOOT_CORE_SOURCES} ${REASHOOT_CORE_HEADERS})
target_include_directories(reashoot_core
  PUBLIC
    "${REASHOOT_ROOT}/src"
    "${REASHOOT_SDK_DIR}"
)
target_compile_options(reashoot_core PRIVATE ${REASHOOT_WARNING_FLAGS})
set_target_properties(reashoot_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(reashoot_desktop_core STATIC ${REASHOOT_DESKTOP_SOURCES} ${REASHOOT_DESKTOP_HEADERS})
target_link_libraries(reashoot_desktop_core PUBLIC reashoot_core)
target_include_directories(reashoot_desktop_core PUBLIC "${REASHOOT_ROOT}/src")
target_compile_options(reashoot_desktop_core PRIVATE ${REASHOOT_WARNING_FLAGS})
set_target_properties(reashoot_desktop_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(reashoot_core_tests "${REASHOOT_ROOT}/tests/core_tests.cpp")
target_link_libraries(reashoot_core_tests PRIVATE reashoot_core reashoot_desktop_core)
target_compile_options(reashoot_core_tests PRIVATE ${REASHOOT_WARNING_FLAGS})

enable_testing()
add_test(NAME reashoot_core_tests COMMAND reashoot_core_tests)
add_test(NAME reashoot_gui_drift_guard
         COMMAND "${CMAKE_COMMAND}" "-DREASHOOT_ROOT=${REASHOOT_ROOT}" -P "${REASHOOT_ROOT}/tests/gui_drift_guard.cmake")

file(GLOB REASHOOT_HELPER_SOURCES CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/helper/*.cpp")
add_executable(reashoot_helper ${REASHOOT_HELPER_SOURCES})
target_link_libraries(reashoot_helper PRIVATE reashoot_desktop_core)
target_compile_options(reashoot_helper PRIVATE ${REASHOOT_WARNING_FLAGS})
if(WIN32)
  target_link_libraries(reashoot_helper PRIVATE ws2_32 iphlpapi shell32)
  set_target_properties(reashoot_helper PROPERTIES OUTPUT_NAME "reashoot-win")
elseif(APPLE)
  set_target_properties(reashoot_helper PROPERTIES OUTPUT_NAME "reashoot-mac")
else()
  set_target_properties(reashoot_helper PROPERTIES OUTPUT_NAME "reashoot-helper")
endif()

if(APPLE)
  add_library(reaper_reashoot SHARED
    "${REASHOOT_ROOT}/src/reashoot.mm"
    "${REASHOOT_ROOT}/src/reaper/reaper_host.cpp"
    "${REASHOOT_ROOT}/src/platform/mac/mac_media_audio_reader.mm"
  )
  target_link_libraries(reaper_reashoot
    PRIVATE
      reashoot_desktop_core
      "-framework Cocoa"
      "-framework AVFoundation"
      "-framework AudioToolbox"
  )
  target_include_directories(reaper_reashoot PRIVATE "${REASHOOT_ROOT}/src" "${REASHOOT_SDK_DIR}")
  target_compile_options(reaper_reashoot PRIVATE
    ${REASHOOT_WARNING_FLAGS}
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
  )
  target_link_options(reaper_reashoot PRIVATE
    -undefined dynamic_lookup
    -Wl,-rpath,@loader_path
    -sectcreate __TEXT __info_plist "${REASHOOT_ROOT}/Info.plist"
  )
  set_target_properties(reaper_reashoot PROPERTIES PREFIX "" SUFFIX ".dylib")

  set(REAPER_USERPLUGINS_DIR "$ENV{HOME}/Library/Application Support/REAPER/UserPlugins"
      CACHE PATH "REAPER UserPlugins install directory")
  install(CODE
    "file(REMOVE
       \"${REAPER_USERPLUGINS_DIR}/reaper_video_recorder.dylib\"
       \"${REAPER_USERPLUGINS_DIR}/reashoot.dylib\"
       \"${REAPER_USERPLUGINS_DIR}/video-sync-mac\")")
  install(TARGETS reaper_reashoot reashoot_helper
          RUNTIME DESTINATION "${REAPER_USERPLUGINS_DIR}"
          LIBRARY DESTINATION "${REAPER_USERPLUGINS_DIR}")
  install(CODE
    "execute_process(COMMAND /usr/bin/codesign --force --sign - \"${REAPER_USERPLUGINS_DIR}/reashoot-mac\" COMMAND_ERROR_IS_FATAL ANY)
     execute_process(COMMAND /usr/bin/codesign --force --sign - \"${REAPER_USERPLUGINS_DIR}/reaper_reashoot.dylib\" COMMAND_ERROR_IS_FATAL ANY)")

  add_executable(reashoot_desktop MACOSX_BUNDLE
    "${REASHOOT_ROOT}/src/app/mac/ReaShootDesktopApp.mm"
    "${REASHOOT_ROOT}/src/app/mac/ReaShootMacIntegrationServer.mm"
    "${REASHOOT_ROOT}/src/app/mac/ReaShootMacSupport.mm"
    "${REASHOOT_ROOT}/src/app/mac/ReaShootMacUI.mm"
    "${REASHOOT_ROOT}/src/app/mac/ReaShootPreviewView.mm"
    "${REASHOOT_ROOT}/src/platform/mac/mac_helper_process.mm"
    "${REASHOOT_ROOT}/src/platform/mac/mac_preview_stream_client.mm"
    "${REASHOOT_ROOT}/src/platform/mac/mac_h264_preview_renderer.mm"
  )
  target_link_libraries(reashoot_desktop
    PRIVATE
      reashoot_desktop_core
      "-framework Cocoa"
      "-framework Foundation"
      "-framework CoreMedia"
      "-framework QuartzCore"
      "-framework VideoToolbox"
  )
  target_include_directories(reashoot_desktop PRIVATE "${REASHOOT_ROOT}/src")
  target_compile_options(reashoot_desktop PRIVATE
    ${REASHOOT_WARNING_FLAGS}
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
  )
  set_target_properties(reashoot_desktop PROPERTIES
    OUTPUT_NAME "ReaShoot"
    MACOSX_BUNDLE_INFO_PLIST "${REASHOOT_ROOT}/src/app/mac/Info.plist"
  )
  add_dependencies(reashoot_desktop reashoot_helper)
  add_custom_command(TARGET reashoot_desktop POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:reashoot_desktop>/Resources"
    COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:reashoot_helper>" "$<TARGET_BUNDLE_CONTENT_DIR:reashoot_desktop>/Resources/reashoot-mac"
  )
endif()

if(WIN32)
  option(REASHOOT_BUILD_DESKTOP_WIN32 "Build the standalone Windows desktop app (ReaShoot.exe)" ON)
  option(REASHOOT_WITH_FFMPEG_DECODER "Use shared FFmpeg for Windows live and playback preview decoding" ON)
  file(GLOB REASHOOT_WIN32_SOURCES CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/platform/win32/*.cpp")
  file(GLOB REASHOOT_SWELL_CPP_SOURCES CONFIGURE_DEPENDS "${REASHOOT_ROOT}/src/platform/swell/*.cpp")
  if(REASHOOT_WITH_FFMPEG_DECODER AND (NOT DEFINED REASHOOT_FFMPEG_ROOT OR "${REASHOOT_FFMPEG_ROOT}" STREQUAL ""))
    file(GLOB REASHOOT_WINGET_FFMPEG_DIRS
      "$ENV{LOCALAPPDATA}/Microsoft/WinGet/Packages/Gyan.FFmpeg.Shared_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-*")
    list(SORT REASHOOT_WINGET_FFMPEG_DIRS)
    list(REVERSE REASHOOT_WINGET_FFMPEG_DIRS)
    if(REASHOOT_WINGET_FFMPEG_DIRS)
      list(GET REASHOOT_WINGET_FFMPEG_DIRS 0 REASHOOT_FFMPEG_ROOT)
    endif()
  endif()
  set(REASHOOT_FFMPEG_ROOT "${REASHOOT_FFMPEG_ROOT}" CACHE PATH "Optional shared FFmpeg root containing include, lib, and bin directories")

  add_library(reaper_reashoot SHARED
    "${REASHOOT_ROOT}/src/reaper/reaper_host.cpp"
    ${REASHOOT_WIN32_SOURCES}
    ${REASHOOT_FFMPEG_SOURCES}
    ${REASHOOT_FFMPEG_HEADERS}
    ${REASHOOT_SWELL_CPP_SOURCES}
  )
  target_link_libraries(reaper_reashoot
    PRIVATE
      reashoot_desktop_core
      user32
      gdi32
      shell32
      mf
      mfplat
      mfreadwrite
      mfuuid
      ole32
      ws2_32
      winhttp
      wmcodecdspuuid
  )
  target_include_directories(reaper_reashoot PRIVATE "${REASHOOT_ROOT}/src" "${REASHOOT_SDK_DIR}")
  target_compile_options(reaper_reashoot PRIVATE ${REASHOOT_WARNING_FLAGS})
  target_compile_definitions(reaper_reashoot PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  if(REASHOOT_WITH_FFMPEG_DECODER AND EXISTS "${REASHOOT_FFMPEG_ROOT}/include/libavcodec/avcodec.h" AND EXISTS "${REASHOOT_FFMPEG_ROOT}/lib/avcodec.lib")
    file(TO_CMAKE_PATH "${REASHOOT_FFMPEG_ROOT}/bin" REASHOOT_FFMPEG_BIN_DIR_DEFINE)
    target_compile_definitions(reaper_reashoot PRIVATE REASHOOT_WITH_FFMPEG_DECODER=1 REASHOOT_FFMPEG_BIN_DIR="${REASHOOT_FFMPEG_BIN_DIR_DEFINE}")
    target_include_directories(reaper_reashoot PRIVATE "${REASHOOT_FFMPEG_ROOT}/include")
  else()
    message(FATAL_ERROR "REASHOOT_WITH_FFMPEG_DECODER requires shared FFmpeg headers/libs. Install Gyan.FFmpeg.Shared or set REASHOOT_FFMPEG_ROOT.")
  endif()
  set_target_properties(reaper_reashoot PROPERTIES PREFIX "" SUFFIX ".dll" OUTPUT_NAME "reaper_reashoot")

  set(REAPER_WINDOWS_USERPLUGINS_DIR "$ENV{APPDATA}/REAPER/UserPlugins"
      CACHE PATH "Windows REAPER UserPlugins install directory")
  install(TARGETS reaper_reashoot reashoot_helper
          RUNTIME DESTINATION "${REAPER_WINDOWS_USERPLUGINS_DIR}"
          LIBRARY DESTINATION "${REAPER_WINDOWS_USERPLUGINS_DIR}")

  if(REASHOOT_BUILD_DESKTOP_WIN32)
    add_executable(reashoot_desktop_win32 WIN32
      "${REASHOOT_ROOT}/src/app/win32/ReaShootDesktopWin32.cpp"
      "${REASHOOT_ROOT}/src/app/win32/ReaShootWin32IntegrationServer.cpp"
      "${REASHOOT_ROOT}/src/app/win32/ReaShootWin32Support.cpp"
      "${REASHOOT_ROOT}/src/platform/win32/win32_helper_process.cpp"
      "${REASHOOT_ROOT}/src/platform/win32/win32_preview_stream_client.cpp"
      "${REASHOOT_ROOT}/src/platform/win32/win32_h264_preview_renderer.cpp"
    )
    target_link_libraries(reashoot_desktop_win32
      PRIVATE
        reashoot_desktop_core
        user32
        gdi32
        comctl32
        dwmapi
        uxtheme
        shell32
        ole32
        ws2_32
        winhttp
        mf
        mfplat
        mfreadwrite
        mfuuid
        wmcodecdspuuid
    )
    target_include_directories(reashoot_desktop_win32 PRIVATE "${REASHOOT_ROOT}/src" "${REASHOOT_SDK_DIR}")
    target_compile_options(reashoot_desktop_win32 PRIVATE ${REASHOOT_WARNING_FLAGS})
    target_compile_definitions(reashoot_desktop_win32 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
    set_target_properties(reashoot_desktop_win32 PROPERTIES OUTPUT_NAME "ReaShoot")

    if(REASHOOT_WITH_FFMPEG_DECODER AND EXISTS "${REASHOOT_FFMPEG_ROOT}/include/libavcodec/avcodec.h" AND EXISTS "${REASHOOT_FFMPEG_ROOT}/lib/avcodec.lib")
      target_compile_definitions(reashoot_desktop_win32 PRIVATE REASHOOT_WITH_FFMPEG_DECODER=1 REASHOOT_FFMPEG_BIN_DIR="${REASHOOT_FFMPEG_BIN_DIR_DEFINE}")
      target_include_directories(reashoot_desktop_win32 PRIVATE "${REASHOOT_FFMPEG_ROOT}/include")
      target_link_libraries(reashoot_desktop_win32 PRIVATE "${REASHOOT_FFMPEG_ROOT}/lib/avcodec.lib" "${REASHOOT_FFMPEG_ROOT}/lib/avutil.lib")
    else()
      message(FATAL_ERROR "reashoot_desktop_win32 requires shared FFmpeg headers/libs. Install Gyan.FFmpeg.Shared or set REASHOOT_FFMPEG_ROOT.")
    endif()

    add_dependencies(reashoot_desktop_win32 reashoot_helper)
    add_custom_command(TARGET reashoot_desktop_win32 POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:reashoot_helper>" "$<TARGET_FILE_DIR:reashoot_desktop_win32>/reashoot-win.exe"
    )
    # Stage the shared FFmpeg runtime DLLs next to the app so live preview works.
    file(GLOB REASHOOT_FFMPEG_DLLS "${REASHOOT_FFMPEG_ROOT}/bin/*.dll")
    foreach(dll ${REASHOOT_FFMPEG_DLLS})
      add_custom_command(TARGET reashoot_desktop_win32 POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${dll}" "$<TARGET_FILE_DIR:reashoot_desktop_win32>"
      )
    endforeach()
  endif()
endif()
