#include "input_injector.h"

#include <algorithm>

#include "desktop_state.h"
#include "display_list.h"
#include "host_geometry.h"

namespace input_injector {
namespace {

constexpr DWORD kSettleMs = 15;
constexpr DWORD kPressMs = 30;
constexpr DWORD kDragStepMs = 12;
constexpr int kDragSteps = 12;
constexpr size_t kMaxTextLength = 4096;
// Keystrokes per SendInput call: small enough to notice a rejection early.
constexpr size_t kTextBatch = 32;

bool Send(std::vector<INPUT>* inputs) {
  if (inputs->empty()) return true;
  const UINT count = static_cast<UINT>(inputs->size());
  return SendInput(count, inputs->data(), sizeof(INPUT)) == count;
}

bool SendOne(INPUT input) {
  std::vector<INPUT> inputs{input};
  return Send(&inputs);
}

// A button or key left down would hijack the host, so a release that was
// refused (another injector, a desktop switch) is tried again.
bool SendRelease(INPUT input) {
  for (int attempt = 0; attempt < 3; ++attempt) {
    if (SendOne(input)) return true;
    Sleep(20);
  }
  return false;
}

bool DesktopReady() { return CurrentDesktopState() == DesktopState::kDefault; }

// Keyboard input goes to the foreground window.
bool KeyboardReachable() {
  return DesktopReady() && !RunsAboveThisProcess(GetForegroundWindow());
}

INPUT MouseAt(host_geometry::Point absolute, DWORD flags) {
  INPUT input{};
  input.type = INPUT_MOUSE;
  input.mi.dx = absolute.x;
  input.mi.dy = absolute.y;
  // Every event carries the position, button events too: someone moving
  // the real mouse in between must not shift where the press lands.
  input.mi.dwFlags = flags | MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE |
                     MOUSEEVENTF_VIRTUALDESK;
  return input;
}

INPUT Key(WORD virtual_key, bool down) {
  INPUT input{};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = virtual_key;
  // Send the scan code a keyboard would. Native controls only look at the
  // virtual key, but Flutter identifies keys by scan code: without it a
  // held Control is not seen as a modifier and Ctrl+A arrives as a plain A.
  input.ki.wScan =
      static_cast<WORD>(MapVirtualKeyW(virtual_key, MAPVK_VK_TO_VSC));
  input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
  // Without the flag the arrow keys arrive as their numeric-keypad twins.
  const bool extended = (virtual_key >= VK_PRIOR && virtual_key <= VK_DOWN) ||
                        virtual_key == VK_INSERT || virtual_key == VK_DELETE ||
                        virtual_key == VK_LWIN || virtual_key == VK_RWIN;
  if (extended) input.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
  return input;
}

INPUT UnicodeKey(wchar_t unit, bool down) {
  INPUT input{};
  input.type = INPUT_KEYBOARD;
  input.ki.wScan = static_cast<WORD>(unit);
  input.ki.dwFlags = KEYEVENTF_UNICODE | (down ? 0 : KEYEVENTF_KEYUP);
  return input;
}

// Resolves a position for a pointer action. False when it is out of range,
// or when the window there would not receive the input.
bool Resolve(int display_index, double x, double y,
             host_geometry::Point* absolute) {
  if (!host_geometry::IsNormalized(x) || !host_geometry::IsNormalized(y)) {
    return false;
  }
  DisplayInfo display;
  if (!DisplayAt(display_index, &display)) return false;
  const host_geometry::Point pixel =
      host_geometry::ToDesktopPixel(display.rect, x, y);
  if (RunsAboveThisProcess(WindowFromPoint(POINT{pixel.x, pixel.y}))) {
    return false;
  }
  *absolute = host_geometry::ToAbsolute(VirtualDesktopRect(), pixel);
  return true;
}

}  // namespace

bool Click(int display_index, double x, double y, bool right_button) {
  host_geometry::Point at;
  if (!DesktopReady() || !Resolve(display_index, x, y, &at)) return false;
  const DWORD down = right_button ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
  const DWORD up = right_button ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP;
  if (!SendOne(MouseAt(at, MOUSEEVENTF_MOVE))) return false;
  Sleep(kSettleMs);
  if (!SendOne(MouseAt(at, down))) return false;
  Sleep(kPressMs);
  return SendRelease(MouseAt(at, up));
}

bool Drag(int display_index, double x, double y, double end_x, double end_y) {
  host_geometry::Point from;
  host_geometry::Point to;
  if (!DesktopReady() || !Resolve(display_index, x, y, &from) ||
      !Resolve(display_index, end_x, end_y, &to)) {
    return false;
  }
  if (!SendOne(MouseAt(from, MOUSEEVENTF_MOVE))) return false;
  Sleep(kSettleMs);
  if (!SendOne(MouseAt(from, MOUSEEVENTF_LEFTDOWN))) return false;
  Sleep(kPressMs);
  bool ok = true;
  for (const host_geometry::Point& step :
       host_geometry::DragPath(from, to, kDragSteps)) {
    ok = SendOne(MouseAt(step, MOUSEEVENTF_MOVE));
    if (!ok) break;
    Sleep(kDragStepMs);
  }
  // Release even after a failed move: a held button would hijack the host.
  const bool released = SendRelease(MouseAt(to, MOUSEEVENTF_LEFTUP));
  return ok && released;
}

bool Scroll(int notches) {
  if (notches == 0) return true;
  POINT cursor{};
  if (!DesktopReady() ||
      (GetCursorPos(&cursor) && RunsAboveThisProcess(WindowFromPoint(cursor)))) {
    return false;
  }
  INPUT input{};
  input.type = INPUT_MOUSE;
  input.mi.dwFlags = MOUSEEVENTF_WHEEL;
  input.mi.mouseData =
      static_cast<DWORD>(std::clamp(notches, -20, 20) * WHEEL_DELTA);
  return SendOne(input);
}

bool TypeText(const std::wstring& text) {
  if (text.empty() || text.size() > kMaxTextLength) return false;
  if (!KeyboardReachable()) return false;
  std::vector<INPUT> batch;
  batch.reserve(kTextBatch * 2);
  for (const wchar_t unit : text) {
    if (unit == L'\r') continue;
    if (unit == L'\n' || unit == L'\t') {
      // Applications act on the real keys, not on the control characters.
      const WORD key = unit == L'\n' ? VK_RETURN : VK_TAB;
      batch.push_back(Key(key, true));
      batch.push_back(Key(key, false));
    } else {
      batch.push_back(UnicodeKey(unit, true));
      batch.push_back(UnicodeKey(unit, false));
    }
    // Never part a surrogate pair: input from elsewhere could slip between.
    const bool high_surrogate = unit >= 0xD800 && unit <= 0xDBFF;
    if (batch.size() >= kTextBatch * 2 && !high_surrogate) {
      if (!Send(&batch)) return false;
      batch.clear();
    }
  }
  return Send(&batch);
}

bool KeyPress(WORD virtual_key, const std::vector<WORD>& modifiers) {
  if (virtual_key == 0 || virtual_key > 0xFE) return false;
  if (!KeyboardReachable()) return false;
  std::vector<INPUT> inputs;
  inputs.reserve(modifiers.size() * 2 + 2);
  for (const WORD modifier : modifiers) inputs.push_back(Key(modifier, true));
  inputs.push_back(Key(virtual_key, true));
  inputs.push_back(Key(virtual_key, false));
  for (auto it = modifiers.rbegin(); it != modifiers.rend(); ++it) {
    inputs.push_back(Key(*it, false));
  }
  if (Send(&inputs)) return true;
  // A partly inserted batch may have left keys down; let them all go.
  SendRelease(Key(virtual_key, false));
  for (auto it = modifiers.rbegin(); it != modifiers.rend(); ++it) {
    SendRelease(Key(*it, false));
  }
  return false;
}

bool WakeDisplay() {
  SetThreadExecutionState(ES_DISPLAY_REQUIRED);
  // A monitor in standby wakes on pointer movement. Back and forth, so the
  // pointer ends where it was, give or take a pixel of acceleration.
  std::vector<INPUT> nudge(2);
  nudge[0].type = INPUT_MOUSE;
  nudge[0].mi.dx = 1;
  nudge[0].mi.dwFlags = MOUSEEVENTF_MOVE;
  nudge[1].type = INPUT_MOUSE;
  nudge[1].mi.dx = -1;
  nudge[1].mi.dwFlags = MOUSEEVENTF_MOVE;
  return Send(&nudge);
}

}  // namespace input_injector
