SDK_DIR := vendor/reaper-sdk/sdk
BUILD_DIR := build
TARGET := $(BUILD_DIR)/reaper_video_recorder.dylib
HELPER_PACKAGE := helper
HELPER_BUILD_DIR := $(BUILD_DIR)/helper-build
HELPER_TARGET := $(BUILD_DIR)/video-sync-mac
WEBRTC_FRAMEWORK := $(BUILD_DIR)/LiveKitWebRTC.framework
SRC := src/reaper_video_recorder.mm
HELPER_SRC := $(shell find $(HELPER_PACKAGE) -type f -name '*.swift' -o -name 'Package.swift')
WEBRTC_FRAMEWORK_SRC := $(shell find $(HELPER_BUILD_DIR) -path '*macos*LiveKitWebRTC.framework' -type d 2>/dev/null | head -n 1)

CXX ?= clang++
ARCH_FLAGS ?= -arch $(shell uname -m)
CXXFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -isystem $(SDK_DIR) -F$(BUILD_DIR) $(ARCH_FLAGS)
LDFLAGS := -dynamiclib -undefined dynamic_lookup $(ARCH_FLAGS) \
  -framework Cocoa \
  -framework AVFoundation \
  -framework MetalKit \
  -framework LiveKitWebRTC \
  -framework QuartzCore \
  -Wl,-rpath,@loader_path \
  -sectcreate __TEXT __info_plist Info.plist

.PHONY: all clean install

all: $(TARGET) $(HELPER_TARGET) $(WEBRTC_FRAMEWORK)

$(TARGET): $(SRC) Info.plist $(SDK_DIR)/reaper_plugin.h $(SDK_DIR)/reaper_plugin_functions.h $(WEBRTC_FRAMEWORK)
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) $(LDFLAGS) -o $(TARGET)

$(HELPER_TARGET): $(HELPER_SRC)
	mkdir -p $(BUILD_DIR)
	swift build --package-path $(HELPER_PACKAGE) --configuration release --scratch-path $(HELPER_BUILD_DIR)
	cp $(HELPER_BUILD_DIR)/release/video-sync-mac $(HELPER_TARGET)

$(WEBRTC_FRAMEWORK): $(HELPER_SRC)
	mkdir -p $(BUILD_DIR)
	swift build --package-path $(HELPER_PACKAGE) --configuration release --scratch-path $(HELPER_BUILD_DIR) --target WebRTCDependency
	rm -rf $(WEBRTC_FRAMEWORK)
	cp -R "$$(find $(HELPER_BUILD_DIR) -path '*macos*LiveKitWebRTC.framework' -type d | head -n 1)" $(WEBRTC_FRAMEWORK)

install: $(TARGET) $(HELPER_TARGET) $(WEBRTC_FRAMEWORK)
	mkdir -p "$(HOME)/Library/Application Support/REAPER/UserPlugins"
	cp $(TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
	cp $(HELPER_TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/video-sync-mac"
	rm -rf "$(HOME)/Library/Application Support/REAPER/UserPlugins/LiveKitWebRTC.framework"
	cp -R $(WEBRTC_FRAMEWORK) "$(HOME)/Library/Application Support/REAPER/UserPlugins/LiveKitWebRTC.framework"

clean:
	rm -rf $(BUILD_DIR)
