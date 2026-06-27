SDK_DIR := vendor/reaper-sdk/sdk
BUILD_DIR := build
TARGET := $(BUILD_DIR)/reaper_video_recorder.dylib
SRC := src/reaper_video_recorder.mm

CXX ?= clang++
ARCH_FLAGS ?= -arch $(shell uname -m)
CXXFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -isystem $(SDK_DIR) $(ARCH_FLAGS)
LDFLAGS := -dynamiclib -undefined dynamic_lookup $(ARCH_FLAGS) \
  -framework Cocoa \
  -framework AVFoundation \
  -framework QuartzCore \
  -sectcreate __TEXT __info_plist Info.plist

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SRC) Info.plist $(SDK_DIR)/reaper_plugin.h $(SDK_DIR)/reaper_plugin_functions.h
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) $(LDFLAGS) -o $(TARGET)

install: $(TARGET)
	mkdir -p "$(HOME)/Library/Application Support/REAPER/UserPlugins"
	cp $(TARGET) "$(HOME)/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"

clean:
	rm -rf $(BUILD_DIR)
