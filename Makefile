SDK_DIR := vendor/reaper-sdk/sdk
BUILD_DIR := build
TARGET := $(BUILD_DIR)/reaper_video_recorder.dylib
HELPER_PACKAGE := helper
HELPER_BUILD_DIR := $(BUILD_DIR)/helper-build
HELPER_TARGET := $(BUILD_DIR)/video-sync-mac
SRC := src/reaper_video_recorder.mm
HELPER_SRC := $(shell find $(HELPER_PACKAGE) -type f -name '*.swift' -o -name 'Package.swift')

CXX ?= clang++
ARCH_FLAGS ?= -arch $(shell uname -m)
CXXFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -isystem $(SDK_DIR) $(ARCH_FLAGS)
LDFLAGS := -dynamiclib -undefined dynamic_lookup $(ARCH_FLAGS) \
  -framework Cocoa \
  -framework AVFoundation \
  -framework QuartzCore \
  -sectcreate __TEXT __info_plist Info.plist

.PHONY: all clean install

all: $(TARGET) $(HELPER_TARGET)

$(TARGET): $(SRC) Info.plist $(SDK_DIR)/reaper_plugin.h $(SDK_DIR)/reaper_plugin_functions.h
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) $(LDFLAGS) -o $(TARGET)

$(HELPER_TARGET): $(HELPER_SRC)
	mkdir -p $(BUILD_DIR)
	swift build --package-path $(HELPER_PACKAGE) --configuration release --scratch-path $(HELPER_BUILD_DIR)
	cp $(HELPER_BUILD_DIR)/release/video-sync-mac $(HELPER_TARGET)

install: $(TARGET) $(HELPER_TARGET)
	mkdir -p "$(HOME)/Library/Application Support/REAPER/UserPlugins"
	cp $(TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
	cp $(HELPER_TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/video-sync-mac"

clean:
	rm -rf $(BUILD_DIR)
