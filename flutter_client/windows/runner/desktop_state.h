#ifndef RUNNER_DESKTOP_STATE_H_
#define RUNNER_DESKTOP_STATE_H_

#include <windows.h>

// Which desktop currently receives input. The lock screen and UAC prompts
// live on desktops this process may not open, which is why neither capture
// nor input can reach them.
enum class DesktopState {
  kDefault,
  // The workstation is locked.
  kLocked,
  // A UAC prompt or another secure desktop owns the screen.
  kSecure,
};

DesktopState CurrentDesktopState();

// True when |window| belongs to a process running at a higher integrity
// level than this one (typically "run as administrator"). Windows drops
// input injected at such a window, and SendInput does not say so. False when
// the level cannot be determined, so an unknown is never reported as blocked.
bool RunsAboveThisProcess(HWND window);

#endif  // RUNNER_DESKTOP_STATE_H_
