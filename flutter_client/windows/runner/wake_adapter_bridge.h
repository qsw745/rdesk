#ifndef RUNNER_WAKE_ADAPTER_BRIDGE_H_
#define RUNNER_WAKE_ADAPTER_BRIDGE_H_
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <winsock2.h>
#include <windows.h>
#include <memory>
#include <mutex>
#include <thread>

class WakeAdapterBridge {
 public:
  static constexpr UINT kResultMessage = WM_APP + 0x57;
  WakeAdapterBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~WakeAdapterBridge();
  void Complete();
 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  std::thread worker_;
  std::mutex mutex_;
  flutter::EncodableValue payload_;
  bool failed_ = false;
};
#endif
