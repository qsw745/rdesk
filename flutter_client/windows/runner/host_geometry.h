#ifndef RUNNER_HOST_GEOMETRY_H_
#define RUNNER_HOST_GEOMETRY_H_

#include <algorithm>
#include <cmath>
#include <vector>

// Arithmetic of the Windows host, kept free of Windows headers so it can be
// compiled and checked on any machine (see tests/host_geometry_test.cpp).
// All pixels are physical: the process is per-monitor DPI aware.
namespace host_geometry {

struct Rect {
  long left = 0;
  long top = 0;
  long right = 0;
  long bottom = 0;
  long width() const { return right - left; }
  long height() const { return bottom - top; }
};

struct Point {
  long x = 0;
  long y = 0;
};

struct Size {
  int width = 0;
  int height = 0;
};

// SendInput addresses the virtual desktop as 0..65535 on both axes.
constexpr long kAbsoluteMax = 65535;

// False for NaN, so a malformed request can never become a click.
inline bool IsNormalized(double value) { return value >= 0.0 && value <= 1.0; }

// Desktop pixel for a 0..1 position inside |monitor|. Out-of-range input is
// pinned to the monitor so it cannot reach a neighbouring display.
inline Point ToDesktopPixel(const Rect& monitor, double nx, double ny) {
  const auto along = [](long origin, long extent, double normalized) {
    if (extent <= 0 || !(normalized > 0.0)) return origin;
    const double clamped = std::min(normalized, 1.0);
    const long offset = static_cast<long>(clamped * static_cast<double>(extent));
    return origin + std::min(offset, extent - 1);
  };
  return Point{along(monitor.left, monitor.width(), nx),
               along(monitor.top, monitor.height(), ny)};
}

// SendInput absolute coordinate for a desktop pixel.
inline Point ToAbsolute(const Rect& virtual_desktop, Point pixel) {
  const auto along = [](long origin, long extent, long value) {
    if (extent <= 1) return 0L;
    const long offset = std::clamp(value - origin, 0L, extent - 1);
    return std::lround(static_cast<double>(offset) *
                       static_cast<double>(kAbsoluteMax) /
                       static_cast<double>(extent - 1));
  };
  return Point{
      along(virtual_desktop.left, virtual_desktop.width(), pixel.x),
      along(virtual_desktop.top, virtual_desktop.height(), pixel.y)};
}

// Largest size no bigger than |max_dimension| on either side that keeps the
// aspect ratio. Never enlarges; a non-positive limit means "no limit".
inline Size FitWithin(int width, int height, int max_dimension) {
  const int longest = std::max(width, height);
  if (max_dimension <= 0 || longest <= max_dimension) {
    return Size{width, height};
  }
  const double scale =
      static_cast<double>(max_dimension) / static_cast<double>(longest);
  const auto scaled = [scale](int value) {
    return std::max(1, static_cast<int>(std::lround(value * scale)));
  };
  return Size{scaled(width), scaled(height)};
}

// Intermediate pointer positions for a drag, ending exactly on |to|.
inline std::vector<Point> DragPath(Point from, Point to, int steps) {
  const int count = std::max(1, steps);
  std::vector<Point> path;
  path.reserve(static_cast<size_t>(count));
  for (int i = 1; i <= count; ++i) {
    const double t = static_cast<double>(i) / static_cast<double>(count);
    path.push_back(Point{
        from.x + std::lround(static_cast<double>(to.x - from.x) * t),
        from.y + std::lround(static_cast<double>(to.y - from.y) * t)});
  }
  return path;
}

// WIC accepts JPEG quality in 0..1; anything unusable falls back to 0.8.
inline float ClampQuality(double quality) {
  if (std::isnan(quality)) return 0.8f;
  return static_cast<float>(std::clamp(quality, 0.1, 1.0));
}

}  // namespace host_geometry

#endif  // RUNNER_HOST_GEOMETRY_H_
