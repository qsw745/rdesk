#ifndef RUNNER_INPUT_INJECTOR_H_
#define RUNNER_INPUT_INJECTOR_H_

#include <windows.h>

#include <string>
#include <utility>
#include <vector>

// Remote input for the Windows host, injected with SendInput.
//
// Every function reports whether the input can have reached its target, and
// callers must pass a failure on instead of claiming success. Nothing is sent
// on the lock screen or a UAC prompt. Windows silently drops input aimed at a
// window of a more privileged process ("run as administrator") while still
// reporting success, so that case is detected here and refused.
// The functions sleep between events, so call them off the platform thread.
namespace input_injector {

// Positions are 0..1 within the display at |display_index|.
bool Click(int display_index, double x, double y, bool right_button);
bool Drag(int display_index, double x, double y, double end_x, double end_y);

// A left-button drag that passes through every point of |path| in order.
bool DragThrough(int display_index,
                 const std::vector<std::pair<double, double>>& path);

// Positive scrolls up, in wheel notches, at the current pointer position.
bool Scroll(int notches);

// Types |text| as Unicode, independent of the host's keyboard layout.
bool TypeText(const std::wstring& text);

// Presses |virtual_key| with |modifiers| held, then releases everything.
bool KeyPress(WORD virtual_key, const std::vector<WORD>& modifiers);

// Turns a sleeping display back on.
bool WakeDisplay();

}  // namespace input_injector

#endif  // RUNNER_INPUT_INJECTOR_H_
