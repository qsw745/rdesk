#ifndef RUNNER_DESKTOP_HOST_BRIDGE_H_
#define RUNNER_DESKTOP_HOST_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "screen_capture.h"

// Windows side of the desktop host: lets this PC be viewed and controlled.
// Channel com.qsw.rdesk/desktop_host, same contract as the macOS plugin:
//   setCaptureEnabled{enabled, generation}
//   captureScreen{generation, maxDimension, quality} -> {bytes, width, height}
//       errors SESSION_LOCKED, SECURE_DESKTOP, CAPTURE_FAILED
//   captureDiagnostics, listDisplays, switchDisplay{index}
//   performMouse{kind, x, y, endX, endY, amount} -> bool
//   performKeyPress{keyCode, modifiers} -> bool
//   typeText{text} -> bool, wakeDisplay -> bool
// Capture and input run on one worker thread; replies return to the platform
// thread through kResultMessage. While capture is disabled no graphics
// resource or picture of the screen is kept.
class DesktopHostBridge {
 public:
  static constexpr UINT kResultMessage = WM_APP + 0x59;
  DesktopHostBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~DesktopHostBridge();
  // Platform thread: deliver the replies of finished work.
  void Drain();

 private:
  using Value = flutter::EncodableValue;
  using Result = std::shared_ptr<flutter::MethodResult<Value>>;
  // Runs on the platform thread once the work is done.
  using Completion = std::function<void()>;
  using Work = std::function<Completion(ScreenCapture&)>;

  void Handle(const flutter::MethodCall<Value>& call, Result result);
  void SetCaptureEnabled(const flutter::EncodableMap& args);
  void CaptureScreen(const flutter::EncodableMap& args, Result result);
  void PerformMouse(const flutter::EncodableMap& args, Result result);
  void PerformKeyPress(const flutter::EncodableMap& args, Result result);
  // False when too much work is already waiting; the caller replies itself.
  // |always| is for work that must not be skipped, such as releasing the
  // screen picture.
  bool Post(Work work, bool always = false);
  // Queues input work and replies false right away if it cannot be queued.
  void PostInput(Result result, std::function<bool()> action);
  void Run();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;

  // Platform thread only.
  bool capture_enabled_ = false;
  bool capture_pending_ = false;
  int64_t capture_generation_ = 0;
  int64_t capture_requests_ = 0;
  int64_t encoded_frames_ = 0;
  int selected_display_ = 0;
  std::string backend_ = "none";

  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<Work> queue_;
  std::deque<Completion> finished_;
  bool stopping_ = false;
  std::thread worker_;
};

#endif  // RUNNER_DESKTOP_HOST_BRIDGE_H_
