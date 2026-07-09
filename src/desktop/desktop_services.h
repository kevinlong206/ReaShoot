#pragma once

#include "../core/platform_interfaces.h"

#include <chrono>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace reashoot::desktop {

class DesktopLogger {
public:
  virtual ~DesktopLogger() = default;
  virtual void log(const std::string &message) = 0;
};

class MainThreadDispatcher {
public:
  virtual ~MainThreadDispatcher() = default;
  virtual void post(std::function<void()> work) = 0;
  virtual void postDelayed(std::chrono::milliseconds delay, std::function<void()> work) = 0;
};

class SettingsStore {
public:
  virtual ~SettingsStore() = default;
  virtual std::string stringForKey(const std::string &key) const = 0;
  virtual void setString(const std::string &key, const std::string &value) = 0;
  virtual void removeKey(const std::string &key) = 0;
};

class FileDialogService {
public:
  virtual ~FileDialogService() = default;
  virtual std::string chooseDirectory(const std::string &currentDirectory) = 0;
};

class FileRevealService {
public:
  virtual ~FileRevealService() = default;
  virtual void revealFile(const std::string &path) = 0;
};

class ThumbnailLoader {
public:
  virtual ~ThumbnailLoader() = default;
  virtual void loadThumbnail(const std::string &url, std::function<void(std::vector<unsigned char>)> completion) = 0;
};

class DesktopPlatformServices {
public:
  virtual ~DesktopPlatformServices() = default;
  virtual DesktopLogger &logger() = 0;
  virtual MainThreadDispatcher &dispatcher() = 0;
  virtual SettingsStore &settingsStore() = 0;
  virtual FileDialogService &fileDialogs() = 0;
  virtual FileRevealService &fileReveal() = 0;
  virtual ThumbnailLoader &thumbnailLoader() = 0;
  virtual std::unique_ptr<core::PreviewStreamClient> createPreviewStreamClient() = 0;
  virtual std::unique_ptr<core::PreviewRenderer> createPreviewRenderer(core::VideoFrameCallback frameHandler,
                                                                        core::DecoderStatusCallback statusHandler) = 0;
};

} // namespace reashoot::desktop
