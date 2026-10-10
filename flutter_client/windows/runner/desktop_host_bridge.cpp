#include "desktop_host_bridge.h"

#include <flutter/standard_method_codec.h>
#include <objbase.h>

#include <utility>
#include <vector>

#include "display_list.h"
#include "input_injector.h"

namespace {

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;

// Capture and input share one worker; beyond this the host is not keeping up.
constexpr size_t kMaxQueuedWork = 32;

const Value* Find(const Map& map, const char* key) {
  const auto it = map.find(Value(key));
  return it == map.end() ? nullptr : &it->second;
}

int64_t IntArg(const Map& map, const char* key, int64_t fallback) {
  const Value* value = Find(map, key);
  if (!value) return fallback;
  if (const auto* narrow = std::get_if<int32_t>(value)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(value)) return *wide;
  return fallback;
}

// Dart sends whole numbers as integers even where a double is meant.
bool DoubleArg(const Map& map, const char* key, double* out) {
  const Value* value = Find(map, key);
  if (!value) return false;
  if (const auto* real = std::get_if<double>(value)) {
    *out = *real;
    return true;
  }
  if (const auto* narrow = std::get_if<int32_t>(value)) {
    *out = static_cast<double>(*narrow);
    return true;
  }
  if (const auto* wide = std::get_if<int64_t>(value)) {
    *out = static_cast<double>(*wide);
    return true;
  }
  return false;
}

std::string StringArg(const Map& map, const char* key) {
  const Value* value = Find(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : std::string();
}

std::wstring Utf16(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       utf8.data(),
                                       static_cast<int>(utf8.size()), nullptr,
                                       0);
  if (size <= 0) return std::wstring();
  std::wstring text(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                      static_cast<int>(utf8.size()), text.data(), size);
  return text;
}

bool ModifierKey(const std::string& name, WORD* key) {
  // Left-hand keys: a real keyboard never reports a side-less modifier.
  if (name == "control") {
    *key = VK_LCONTROL;
  } else if (name == "shift") {
    *key = VK_LSHIFT;
  } else if (name == "alt") {
    *key = VK_LMENU;
  } else if (name == "win") {
    *key = VK_LWIN;
  } else {
    return false;
  }
  return true;
}

Value PermissionState() {
  // Windows asks for no capture or input permission; consent is the in-app
  // hosting switch, which is off until the user turns it on.
  return Value(Map{{Value("screenRecordingGranted"), Value(true)},
                   {Value("accessibilityGranted"), Value(true)}});
}

Value DisplayList() {
  List list;
  int index = 0;
  for (const DisplayInfo& display : EnumerateDisplays()) {
    const int width = static_cast<int>(display.rect.width());
    const int height = static_cast<int>(display.rect.height());
    const std::string label =
        display.primary ? "主显示器" : "显示器 " + std::to_string(index + 1);
    list.emplace_back(Map{
        {Value("index"), Value(index)},
        {Value("name"), Value(label + " (" + std::to_string(width) + "×" +
                              std::to_string(height) + ")")},
        {Value("width"), Value(width)},
        {Value("height"), Value(height)},
        {Value("isMain"), Value(display.primary)}});
    ++index;
  }
  return Value(list);
}

}  // namespace

DesktopHostBridge::DesktopHostBridge(flutter::BinaryMessenger* messenger,
                                     HWND window)
    : window_(window) {
  worker_ = std::thread([this]() { Run(); });
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "com.qsw.rdesk/desktop_host",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call,
             std::unique_ptr<flutter::MethodResult<Value>> result) {
        Handle(call, Result(std::move(result)));
      });
}

DesktopHostBridge::~DesktopHostBridge() {
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
  }
  wake_.notify_all();
  if (worker_.joinable()) worker_.join();
}

bool DesktopHostBridge::Post(Work work, bool always) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!always && queue_.size() >= kMaxQueuedWork) return false;
    queue_.push_back(std::move(work));
  }
  wake_.notify_one();
  return true;
}

void DesktopHostBridge::PostInput(Result result, std::function<bool()> action) {
  const bool queued = Post([result, action](ScreenCapture&) -> Completion {
    const bool ok = action();
    return [result, ok]() { result->Success(Value(ok)); };
  });
  // Input that would run long after it was sent is worse than none.
  if (!queued) result->Success(Value(false));
}

void DesktopHostBridge::Run() {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    // Scoped so every COM object is gone before COM is.
    ScreenCapture capture;
    for (;;) {
      Work work;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        wake_.wait(lock, [this]() { return stopping_ || !queue_.empty(); });
        if (stopping_) break;
        work = std::move(queue_.front());
        queue_.pop_front();
      }
      Completion done = work(capture);
      // Drop the worker's reference first, so the reply object is always
      // destroyed on the platform thread.
      work = nullptr;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        finished_.push_back(std::move(done));
      }
      PostMessageW(window_, kResultMessage, 0, 0);
    }
    capture.Release();
  }
  if (SUCCEEDED(com)) CoUninitialize();
}

void DesktopHostBridge::Drain() {
  std::deque<Completion> finished;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    finished.swap(finished_);
  }
  for (Completion& done : finished) {
    if (done) done();
  }
}

void DesktopHostBridge::Handle(const flutter::MethodCall<Value>& call,
                               Result result) {
  // Deliver anything already finished first. Normally kResultMessage does
  // this; should a post ever be lost, the next call still unblocks capture.
  Drain();
  const std::string& method = call.method_name();
  static const Map kNoArgs;
  const Map* given = call.arguments() ? std::get_if<Map>(call.arguments())
                                      : nullptr;
  const Map& args = given ? *given : kNoArgs;

  if (method == "getPermissionState" || method == "requestPermissionPrompts") {
    result->Success(PermissionState());
  } else if (method == "setCaptureEnabled") {
    SetCaptureEnabled(args);
    result->Success();
  } else if (method == "captureScreen") {
    CaptureScreen(args, std::move(result));
  } else if (method == "captureDiagnostics") {
    result->Success(Value(Map{{Value("enabled"), Value(capture_enabled_)},
                              {Value("pending"), Value(capture_pending_)},
                              {Value("requests"), Value(capture_requests_)},
                              {Value("encoded"), Value(encoded_frames_)},
                              {Value("backend"), Value(backend_)}}));
  } else if (method == "listDisplays") {
    result->Success(DisplayList());
  } else if (method == "switchDisplay") {
    selected_display_ = static_cast<int>(IntArg(args, "index", 0));
    result->Success(Value(true));
  } else if (method == "performMouse") {
    PerformMouse(args, std::move(result));
  } else if (method == "performKeyPress") {
    PerformKeyPress(args, std::move(result));
  } else if (method == "typeText") {
    const std::wstring text = Utf16(StringArg(args, "text"));
    PostInput(std::move(result),
              [text]() { return input_injector::TypeText(text); });
  } else if (method == "wakeDisplay") {
    PostInput(std::move(result),
              []() { return input_injector::WakeDisplay(); });
  } else if (method == "resetPermissionDenied" || method == "activateApp" ||
             method == "openScreenRecordingSettings" ||
             method == "openAccessibilitySettings") {
    // macOS-only concerns; accepted so shared Dart code needs no branches.
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void DesktopHostBridge::SetCaptureEnabled(const Map& args) {
  const int64_t generation = IntArg(args, "generation", 0);
  // A late reply to an older request must not undo a newer decision.
  if (generation < capture_generation_) return;
  capture_generation_ = generation;
  const Value* enabled = Find(args, "enabled");
  const auto* flag = enabled ? std::get_if<bool>(enabled) : nullptr;
  capture_enabled_ = flag && *flag;
  if (!capture_enabled_) {
    Post(
        [](ScreenCapture& capture) -> Completion {
          capture.Release();
          return Completion();
        },
        /*always=*/true);
  }
}

void DesktopHostBridge::CaptureScreen(const Map& args, Result result) {
  const int64_t generation = IntArg(args, "generation", -1);
  if (!capture_enabled_ || generation != capture_generation_ ||
      capture_pending_) {
    result->Success();
    return;
  }
  const int max_dimension = static_cast<int>(IntArg(args, "maxDimension", 1920));
  double quality = 0.8;
  DoubleArg(args, "quality", &quality);
  const int display = selected_display_;
  ++capture_requests_;
  capture_pending_ = Post([this, result, generation, max_dimension, quality,
                           display](ScreenCapture& capture) -> Completion {
    auto frame = std::make_shared<ScreenCapture::Frame>();
    const ScreenCapture::Status status =
        capture.Capture(display, max_dimension, quality, frame.get());
    const std::string backend = capture.backend();
    return [this, result, generation, frame, status, backend]() {
      capture_pending_ = false;
      backend_ = backend;
      // Disabled or superseded while it ran: the picture must not leave.
      if (!capture_enabled_ || generation != capture_generation_) {
        result->Success();
        return;
      }
      switch (status) {
        case ScreenCapture::Status::kOk:
          ++encoded_frames_;
          result->Success(Value(Map{
              {Value("bytes"), Value(std::move(frame->jpeg))},
              {Value("width"), Value(frame->width)},
              {Value("height"), Value(frame->height)}}));
          break;
        case ScreenCapture::Status::kSessionLocked:
          result->Error("SESSION_LOCKED", "workstation is locked");
          break;
        case ScreenCapture::Status::kSecureDesktop:
          result->Error("SECURE_DESKTOP", "a secure desktop owns the screen");
          break;
        case ScreenCapture::Status::kFailed:
          result->Error("CAPTURE_FAILED");
          break;
      }
    };
  });
  if (!capture_pending_) result->Success();
}

void DesktopHostBridge::PerformMouse(const Map& args, Result result) {
  const std::string kind = StringArg(args, "kind");
  const int display = selected_display_;
  if (kind == "scroll") {
    const int notches = static_cast<int>(IntArg(args, "amount", 0));
    PostInput(std::move(result),
              [notches]() { return input_injector::Scroll(notches); });
    return;
  }
  if (kind == "dragPath") {
    std::vector<std::pair<double, double>> path;
    const Value* raw = Find(args, "points");
    const auto* list = raw ? std::get_if<List>(raw) : nullptr;
    bool valid = list != nullptr;
    for (size_t i = 0; valid && i < list->size(); ++i) {
      const auto* point = std::get_if<List>(&(*list)[i]);
      const auto* px = point && point->size() == 2
                           ? std::get_if<double>(&(*point)[0])
                           : nullptr;
      const auto* py = px ? std::get_if<double>(&(*point)[1]) : nullptr;
      valid = px && py;
      if (valid) path.emplace_back(*px, *py);
    }
    if (!valid) {
      result->Success(Value(false));
      return;
    }
    PostInput(std::move(result), [display, path]() {
      return input_injector::DragThrough(display, path);
    });
    return;
  }
  double x = 0;
  double y = 0;
  if (!DoubleArg(args, "x", &x) || !DoubleArg(args, "y", &y)) {
    result->Success(Value(false));
    return;
  }
  if (kind == "click" || kind == "rightClick") {
    const bool right = kind == "rightClick";
    PostInput(std::move(result), [display, x, y, right]() {
      return input_injector::Click(display, x, y, right);
    });
    return;
  }
  double end_x = 0;
  double end_y = 0;
  if (kind != "drag" || !DoubleArg(args, "endX", &end_x) ||
      !DoubleArg(args, "endY", &end_y)) {
    result->Success(Value(false));
    return;
  }
  PostInput(std::move(result), [display, x, y, end_x, end_y]() {
    return input_injector::Drag(display, x, y, end_x, end_y);
  });
}

void DesktopHostBridge::PerformKeyPress(const Map& args, Result result) {
  const int64_t key_code = IntArg(args, "keyCode", 0);
  std::vector<WORD> modifiers;
  bool valid = key_code > 0 && key_code <= 0xFE;
  const Value* names = Find(args, "modifiers");
  if (const auto* list = names ? std::get_if<List>(names) : nullptr) {
    for (const Value& entry : *list) {
      const auto* name = std::get_if<std::string>(&entry);
      WORD key = 0;
      if (!name || !ModifierKey(*name, &key)) {
        valid = false;
        break;
      }
      modifiers.push_back(key);
    }
  }
  if (!valid) {
    result->Success(Value(false));
    return;
  }
  const WORD key = static_cast<WORD>(key_code);
  PostInput(std::move(result), [key, modifiers]() {
    return input_injector::KeyPress(key, modifiers);
  });
}
