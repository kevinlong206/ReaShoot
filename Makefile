SDK_DIR := vendor/reaper-sdk/sdk
BUILD_DIR := build
TARGET := $(BUILD_DIR)/reaper_reashoot.dylib
HELPER_TARGET := $(BUILD_DIR)/reashoot-mac
SRC := src/reashoot.mm
CORE_SRC := $(wildcard src/core/*.cpp)
CORE_HEADERS := $(wildcard src/core/*.h)
MAC_SRC := $(filter-out src/platform/mac/mac_reashoot_panel.mm,$(wildcard src/platform/mac/*.mm))
MAC_HEADERS := $(filter-out src/platform/mac/mac_reashoot_panel.h,$(wildcard src/platform/mac/*.h))
FFMPEG_SRC := $(wildcard src/platform/ffmpeg/*.cpp)
FFMPEG_HEADERS := $(wildcard src/platform/ffmpeg/*.h)
SWELL_SRC := $(wildcard src/platform/swell/*.cpp) $(wildcard src/platform/swell/*.mm)
SWELL_HEADERS := $(wildcard src/platform/swell/*.h)
REAPER_SRC := $(wildcard src/reaper/*.cpp)
REAPER_HEADERS := $(wildcard src/reaper/*.h)
WIN32_STUB_SRC := src/platform/win32/win32_portability_stub.cpp
SWELL_PROBE_SRC := src/platform/swell/swell_panel_probe.cpp
HELPER_CPP_SRC := $(wildcard src/helper/*.cpp)
CORE_TEST_TARGET := $(BUILD_DIR)/core_tests
WIN32_STUB_TARGET := $(BUILD_DIR)/win32_portability_stub.o
SWELL_PROBE_TARGET := $(BUILD_DIR)/swell_panel_probe.o
SWIFT_GIT_ENV := GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

CXX ?= clang++
ARCH_FLAGS ?= -arch $(shell uname -m)
FFMPEG_ROOT_AUTO := $(shell for d in /opt/homebrew /usr/local; do if [ -f "$$d/include/libavcodec/avcodec.h" ] && [ -f "$$d/include/libavformat/avformat.h" ]; then echo $$d; break; fi; done)
override FFMPEG_ROOT := $(or $(FFMPEG_ROOT),$(REASHOOT_FFMPEG_ROOT),$(FFMPEG_ROOT_AUTO))
FFMPEG_CXXFLAGS := $(if $(FFMPEG_ROOT),-I$(FFMPEG_ROOT)/include,)
FFMPEG_LDFLAGS := $(if $(FFMPEG_ROOT),-L$(FFMPEG_ROOT)/lib -lavformat -lavcodec -lavutil -Wl,-rpath,$(FFMPEG_ROOT)/lib,)
CXXFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Isrc -isystem $(SDK_DIR) $(FFMPEG_CXXFLAGS) -F$(BUILD_DIR) $(ARCH_FLAGS)
CORE_TEST_CXXFLAGS := -std=c++17 -Wall -Wextra -Wno-unused-parameter -Isrc $(ARCH_FLAGS)
LDFLAGS := -dynamiclib -undefined dynamic_lookup $(ARCH_FLAGS) \
  -framework Cocoa \
  -framework AVFoundation \
  -framework QuartzCore \
  -framework VideoToolbox \
  $(FFMPEG_LDFLAGS) \
  -Wl,-rpath,@loader_path \
  -sectcreate __TEXT __info_plist Info.plist

.PHONY: all clean install check

all: $(TARGET) $(HELPER_TARGET)

$(TARGET): $(SRC) $(CORE_SRC) $(CORE_HEADERS) $(MAC_SRC) $(MAC_HEADERS) $(FFMPEG_SRC) $(FFMPEG_HEADERS) $(SWELL_SRC) $(SWELL_HEADERS) $(REAPER_SRC) $(REAPER_HEADERS) Info.plist $(SDK_DIR)/reaper_plugin.h $(SDK_DIR)/reaper_plugin_functions.h
	@if [ -z "$(FFMPEG_ROOT)" ]; then echo "FFmpeg not found. Install with 'brew install ffmpeg' or set FFMPEG_ROOT=/path/to/ffmpeg-prefix or REASHOOT_FFMPEG_ROOT=/path/to/ffmpeg-prefix."; exit 1; fi
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) $(CORE_SRC) $(MAC_SRC) $(FFMPEG_SRC) $(SWELL_SRC) $(REAPER_SRC) $(LDFLAGS) -o $(TARGET)

$(HELPER_TARGET): $(HELPER_CPP_SRC) $(CORE_SRC) $(CORE_HEADERS)
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CORE_TEST_CXXFLAGS) $(HELPER_CPP_SRC) $(CORE_SRC) -o $(HELPER_TARGET)

install: $(TARGET) $(HELPER_TARGET)
	mkdir -p "$(HOME)/Library/Application Support/REAPER/UserPlugins"
	rm -f "$(HOME)/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
	rm -f "$(HOME)/Library/Application Support/REAPER/UserPlugins/reashoot.dylib"
	rm -f "$(HOME)/Library/Application Support/REAPER/UserPlugins/video-sync-mac"
	cp $(TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"
	cp $(HELPER_TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/reashoot-mac"
	codesign --force --sign - "$(HOME)/Library/Application Support/REAPER/UserPlugins/reashoot-mac"
	codesign --force --sign - "$(HOME)/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"

check:
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CORE_TEST_CXXFLAGS) tests/core_tests.cpp $(CORE_SRC) -o $(CORE_TEST_TARGET)
	$(CORE_TEST_TARGET)
	$(CXX) $(CORE_TEST_CXXFLAGS) -c $(WIN32_STUB_SRC) -o $(WIN32_STUB_TARGET)
	$(CXX) $(CORE_TEST_CXXFLAGS) -isystem $(SDK_DIR) -c $(SWELL_PROBE_SRC) -o $(SWELL_PROBE_TARGET)
	$(CXX) $(CORE_TEST_CXXFLAGS) $(HELPER_CPP_SRC) $(CORE_SRC) -o $(HELPER_TARGET)
	$(SWIFT_GIT_ENV) swift test --package-path iphone

clean:
	rm -rf $(BUILD_DIR)
