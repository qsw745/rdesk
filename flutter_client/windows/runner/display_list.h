#ifndef RUNNER_DISPLAY_LIST_H_
#define RUNNER_DISPLAY_LIST_H_

#include <windows.h>

#include <vector>

#include "host_geometry.h"

struct DisplayInfo {
  HMONITOR monitor = nullptr;
  host_geometry::Rect rect;
  bool primary = false;
};

// Primary display first, then left to right and top to bottom, so the index a
// viewer picked keeps meaning the same display between calls.
std::vector<DisplayInfo> EnumerateDisplays();

// The display at |index|; a stale or negative index falls back to the
// primary display. False only when Windows reports no display at all.
bool DisplayAt(int index, DisplayInfo* display);

host_geometry::Rect VirtualDesktopRect();

#endif  // RUNNER_DISPLAY_LIST_H_
