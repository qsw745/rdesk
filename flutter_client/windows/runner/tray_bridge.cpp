#include "tray_bridge.h"

#include <flutter/standard_method_codec.h>
#include <strsafe.h>

#include "resource.h"

namespace {
using Value = flutter::EncodableValue;
constexpr UINT kIconId = 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;
constexpr UINT kMenuDisconnect = 3;
constexpr UINT kMenuStopHosting = 4;
}  // namespace

const wchar_t TrayBridge::kShowMessageName[] = L"RDesk.ShowMainWindow";

TrayBridge::TrayBridge(flutter::BinaryMessenger* messenger, HWND window,
                       bool start_hidden)
    : window_(window),
      show_message_(RegisterWindowMessageW(kShowMessageName)),
      taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")),
      hidden_(start_hidden) {
  // Let a second, non-elevated launch reach an elevated instance.
  ChangeWindowMessageFilterEx(window_, show_message_, MSGFLT_ALLOW, nullptr);
  ChangeWindowMessageFilterEx(window_, taskbar_created_, MSGFLT_ALLOW, nullptr);
  icon_.cbSize = sizeof(icon_);
  icon_.hWnd = window_;
  icon_.uID = kIconId;
  icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  icon_.uCallbackMessage = kTrayMessage;
  icon_.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  StringCchCopyW(icon_.szTip, ARRAYSIZE(icon_.szTip), L"随控");
  AddIcon();

  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "com.qsw.rdesk/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setCloseToTray") {
      const auto* enabled = std::get_if<bool>(call.arguments());
      if (!enabled) {
        result->Error("bad_args", "expected bool");
        return;
      }
      close_to_tray_ = *enabled;
      if (close_to_tray_) {
        AddIcon();
      } else {
        // Without a tray icon a hidden window could never come back.
        if (hidden_) ShowMainWindow();
        if (!viewer_active_) RemoveIcon();
      }
      result->Success();
    } else if (call.method_name() == "setViewerActive") {
      const auto* active = std::get_if<bool>(call.arguments());
      if (!active) {
        result->Error("bad_args", "expected bool");
        return;
      }
      SetViewerActive(*active);
      result->Success();
    } else if (call.method_name() == "isHidden") {
      result->Success(Value(hidden_));
    } else {
      result->NotImplemented();
    }
  });
}

TrayBridge::~TrayBridge() {
  channel_->SetMethodCallHandler(nullptr);
  RemoveIcon();
  if (icon_.hIcon) DestroyIcon(icon_.hIcon);
}

void TrayBridge::OnFirstFrame() {
  if (hidden_ && close_to_tray_) return;
  ShowMainWindow();
}

bool TrayBridge::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                               LRESULT* result) {
  if (message == show_message_) {
    ShowMainWindow();
    *result = 0;
    return true;
  }
  if (message == taskbar_created_) {
    // Explorer restarted and dropped every notification icon.
    icon_added_ = false;
    if (close_to_tray_ || viewer_active_) AddIcon();
    return false;
  }
  switch (message) {
    case WM_CLOSE:
      if (close_to_tray_ && !quitting_) {
        HideToTray();
        *result = 0;
        return true;
      }
      return false;
    case WM_ENDSESSION:
      // Sign-out, shutdown, or an installer's Restart Manager asking RDesk to
      // close for an update: really exit instead of hiding.
      if (wparam) {
        quitting_ = true;
        RemoveIcon();
        DestroyWindow(window_);
      }
      *result = 0;
      return true;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
          ShowMainWindow();
          break;
        case WM_CONTEXTMENU:
          ShowMenu();
          break;
      }
      *result = 0;
      return true;
    case WM_COMMAND:
      if (LOWORD(wparam) == kMenuOpen) {
        ShowMainWindow();
        *result = 0;
        return true;
      }
      if (LOWORD(wparam) == kMenuQuit) {
        Quit();
        *result = 0;
        return true;
      }
      if (LOWORD(wparam) == kMenuDisconnect) {
        channel_->InvokeMethod("disconnectViewers", std::make_unique<Value>());
        *result = 0;
        return true;
      }
      if (LOWORD(wparam) == kMenuStopHosting) {
        channel_->InvokeMethod("stopHosting", std::make_unique<Value>());
        *result = 0;
        return true;
      }
      return false;
  }
  return false;
}

void TrayBridge::ShowMainWindow() {
  hidden_ = false;
  if (IsIconic(window_)) {
    ShowWindow(window_, SW_RESTORE);
  } else {
    ShowWindow(window_, SW_SHOW);
  }
  SetForegroundWindow(window_);
}

void TrayBridge::HideToTray() {
  AddIcon();
  ShowWindow(window_, SW_HIDE);
  hidden_ = true;
  if (hint_shown_ || !icon_added_) return;
  hint_shown_ = true;
  NOTIFYICONDATAW hint = icon_;
  hint.uFlags = NIF_INFO;
  hint.dwInfoFlags = NIIF_USER | NIIF_NOSOUND;
  StringCchCopyW(hint.szInfoTitle, ARRAYSIZE(hint.szInfoTitle),
                 L"随控仍在后台运行");
  StringCchCopyW(hint.szInfo, ARRAYSIZE(hint.szInfo),
                 L"电脑会保持在线。点这里的图标打开，右键可以退出。");
  Shell_NotifyIconW(NIM_MODIFY, &hint);
}

void TrayBridge::AddIcon() {
  if (icon_added_) return;
  if (Shell_NotifyIconW(NIM_ADD, &icon_)) {
    icon_added_ = true;
    NOTIFYICONDATAW version = icon_;
    version.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &version);
  }
}

void TrayBridge::RemoveIcon() {
  if (!icon_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &icon_);
  icon_added_ = false;
}

void TrayBridge::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  if (viewer_active_) {
    AppendMenuW(menu, MF_STRING, kMenuDisconnect, L"断开远程查看");
    AppendMenuW(menu, MF_STRING, kMenuStopHosting, L"停止被远程控制");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  }
  AppendMenuW(menu, MF_STRING, kMenuOpen, L"打开随控");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"退出随控");
  SetMenuDefaultItem(menu, kMenuOpen, FALSE);
  POINT cursor;
  GetCursorPos(&cursor);
  // Required so the menu closes when the user clicks elsewhere.
  SetForegroundWindow(window_);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, cursor.x, cursor.y,
                 0, window_, nullptr);
  PostMessageW(window_, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void TrayBridge::SetViewerActive(bool active) {
  if (viewer_active_ == active) return;
  viewer_active_ = active;
  StringCchCopyW(icon_.szTip, ARRAYSIZE(icon_.szTip),
                 active ? L"随控 · 正在被远程查看" : L"随控");
  if (active) {
    // Windows shows no indicator of its own, so this one must be visible
    // even when the user turned "close to tray" off.
    AddIcon();
  } else if (!close_to_tray_) {
    RemoveIcon();
    return;
  }
  if (!icon_added_) return;
  NOTIFYICONDATAW update = icon_;
  if (active) {
    update.uFlags |= NIF_INFO;
    update.dwInfoFlags = NIIF_USER | NIIF_NOSOUND;
    StringCchCopyW(update.szInfoTitle, ARRAYSIZE(update.szInfoTitle),
                   L"这台电脑正在被远程查看");
    StringCchCopyW(update.szInfo, ARRAYSIZE(update.szInfo),
                   L"右键通知区域的随控图标，可以断开或停止被控。");
  }
  Shell_NotifyIconW(NIM_MODIFY, &update);
}

void TrayBridge::Quit() {
  quitting_ = true;
  RemoveIcon();
  PostMessageW(window_, WM_CLOSE, 0, 0);
}
