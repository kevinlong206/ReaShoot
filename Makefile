SDK_DIR := vendor/reaper-sdk/sdk
BUILD_DIR := build
TARGET := $(BUILD_DIR)/reaper_reashoot.dylib
HELPER_PACKAGE := helper
HELPER_BUILD_DIR := $(BUILD_DIR)/helper-build
HELPER_TARGET := $(BUILD_DIR)/reashoot-mac
SRC := src/reashoot.mm
CORE_SRC := $(wildcard src/core/*.cpp)
CORE_HEADERS := $(wildcard src/core/*.h)
MAC_SRC := $(wildcard src/platform/mac/*.mm)
MAC_HEADERS := $(wildcard src/platform/mac/*.h)
SWELL_SRC := $(wildcard src/platform/swell/*.cpp) $(wildcard src/platform/swell/*.mm)
SWELL_HEADERS := $(wildcard src/platform/swell/*.h)
REAPER_SRC := $(wildcard src/reaper/*.cpp)
REAPER_HEADERS := $(wildcard src/reaper/*.h)
WIN32_STUB_SRC := src/platform/win32/win32_portability_stub.cpp
SWELL_PROBE_SRC := src/platform/swell/swell_panel_probe.cpp
CORE_TEST_TARGET := $(BUILD_DIR)/core_tests
WIN32_STUB_TARGET := $(BUILD_DIR)/win32_portability_stub.o
SWELL_PROBE_TARGET := $(BUILD_DIR)/swell_panel_probe.o
HELPER_SRC := $(shell find $(HELPER_PACKAGE) -type f -name '*.swift' -o -name 'Package.swift')
SWIFT_GIT_ENV := GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

CXX ?= clang++
ARCH_FLAGS ?= -arch $(shell uname -m)
CXXFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Isrc -isystem $(SDK_DIR) -F$(BUILD_DIR) $(ARCH_FLAGS)
CORE_TEST_CXXFLAGS := -std=c++17 -Wall -Wextra -Wno-unused-parameter -Isrc $(ARCH_FLAGS)
LDFLAGS := -dynamiclib -undefined dynamic_lookup $(ARCH_FLAGS) \
  -framework Cocoa \
  -framework AVFoundation \
  -framework QuartzCore \
  -framework VideoToolbox \
  -Wl,-rpath,@loader_path \
  -sectcreate __TEXT __info_plist Info.plist

.PHONY: all clean install check

all: $(TARGET) $(HELPER_TARGET)

$(TARGET): $(SRC) $(CORE_SRC) $(CORE_HEADERS) $(MAC_SRC) $(MAC_HEADERS) $(SWELL_SRC) $(SWELL_HEADERS) $(REAPER_SRC) $(REAPER_HEADERS) Info.plist $(SDK_DIR)/reaper_plugin.h $(SDK_DIR)/reaper_plugin_functions.h
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) $(CORE_SRC) $(MAC_SRC) $(SWELL_SRC) $(REAPER_SRC) $(LDFLAGS) -o $(TARGET)

$(HELPER_TARGET): $(HELPER_SRC)
	mkdir -p $(BUILD_DIR)
	$(SWIFT_GIT_ENV) swift build --package-path $(HELPER_PACKAGE) --configuration release --scratch-path $(HELPER_BUILD_DIR)
	cp $(HELPER_BUILD_DIR)/release/reashoot-mac $(HELPER_TARGET)

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
	./scripts/check_mirrored_swift.sh
	$(SWIFT_GIT_ENV) swift test --package-path iphone
	$(SWIFT_GIT_ENV) swift build --package-path helper

clean:
	rm -rf $(BUILD_DIR)
