#include "display_list.h"

#include <algorithm>

namespace {

BOOL CALLBACK Collect(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* displays = reinterpret_cast<std::vector<DisplayInfo>*>(data);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) return TRUE;
  DisplayInfo display;
  display.monitor = monitor;
  display.rect = host_geometry::Rect{info.rcMonitor.left, info.rcMonitor.top,
                                     info.rcMonitor.right,
                                     info.rcMonitor.bottom};
  display.primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  displays->push_back(display);
  return TRUE;
}

}  // namespace

std::vector<DisplayInfo> EnumerateDisplays() {
  std::vector<DisplayInfo> displays;
  EnumDisplayMonitors(nullptr, nullptr, Collect,
                      reinterpret_cast<LPARAM>(&displays));
  std::sort(displays.begin(), displays.end(),
            [](const DisplayInfo& a, const DisplayInfo& b) {
              if (a.primary != b.primary) return a.primary;
              if (a.rect.left != b.rect.left) return a.rect.left < b.rect.left;
              return a.rect.top < b.rect.top;
            });
  return displays;
}

bool DisplayAt(int index, DisplayInfo* display) {
  const std::vector<DisplayInfo> displays = EnumerateDisplays();
  if (displays.empty()) return false;
  const bool valid =
      index >= 0 && static_cast<size_t>(index) < displays.size();
  *display = displays[valid ? static_cast<size_t>(index) : 0];
  return true;
}

host_geometry::Rect VirtualDesktopRect() {
  const long left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const long top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  return host_geometry::Rect{left, top,
                             left + GetSystemMetrics(SM_CXVIRTUALSCREEN),
                             top + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
}
