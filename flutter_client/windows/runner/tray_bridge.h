#ifndef RUNNER_TRAY_BRIDGE_H_
#define RUNNER_TRAY_BRIDGE_H_
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>
#include <memory>

// Keeps RDesk running in the notification area when its window is closed, so
// a PC woken remotely stays online. Channel com.qsw.rdesk/window:
//   setCloseToTray(bool)  user preference, default on until Dart reports it
//   isHidden() -> bool    whether the window currently lives only in the tray
//   setViewerActive(bool) someone is viewing this PC: say so in the tray and
//                         offer "disconnect" and "stop being controlled",
//                         which call Dart's disconnectViewers() and
//                         stopHosting()
// A second launch broadcasts kShowMessage and exits; this instance then shows.
class TrayBridge {
 public:
  static constexpr UINT kTrayMessage = WM_APP + 0x58;
  static const wchar_t kShowMessageName[];
  TrayBridge(flutter::BinaryMessenger* messenger, HWND window, bool start_hidden);
  ~TrayBridge();
  // Returns true when the message was consumed; *result is then the reply.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result);
  // The first frame is ready; show the window unless it started in the tray.
  void OnFirstFrame();

 private:
  void ShowMainWindow();
  void HideToTray();
  void AddIcon();
  void RemoveIcon();
  void ShowMenu();
  void SetViewerActive(bool active);
  void Quit();
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  UINT show_message_;
  UINT taskbar_created_;
  NOTIFYICONDATAW icon_{};
  bool close_to_tray_ = true;
  bool hidden_;
  bool icon_added_ = false;
  bool hint_shown_ = false;
  bool quitting_ = false;
  bool viewer_active_ = false;
};
#endif
