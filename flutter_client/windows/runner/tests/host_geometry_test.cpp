// Plain C++17, no Windows headers: build and run it on any host, e.g.
//   clang++ -std=c++17 -I.. host_geometry_test.cpp -o host_geometry_test
#include <cstdio>
#include <cstdlib>

#include "host_geometry.h"

namespace {
using host_geometry::Point;
using host_geometry::Rect;
using host_geometry::Size;

int failures = 0;

void Check(bool ok, const char* what, int line) {
  if (ok) return;
  std::fprintf(stderr, "FAILED line %d: %s\n", line, what);
  ++failures;
}
#define CHECK(condition) Check((condition), #condition, __LINE__)

bool Same(Point a, long x, long y) { return a.x == x && a.y == y; }

void NormalizedPositionsStayInsideTheMonitor() {
  const Rect monitor{0, 0, 1920, 1080};
  CHECK(Same(host_geometry::ToDesktopPixel(monitor, 0.0, 0.0), 0, 0));
  CHECK(Same(host_geometry::ToDesktopPixel(monitor, 0.5, 0.5), 960, 540));
  // 1.0 is the far edge of the picture, which is the last pixel, not one past.
  CHECK(Same(host_geometry::ToDesktopPixel(monitor, 1.0, 1.0), 1919, 1079));
  CHECK(Same(host_geometry::ToDesktopPixel(monitor, -3.0, 9.0), 0, 1079));
}

void SecondaryMonitorLeftOfPrimaryUsesNegativeDesktopPixels() {
  const Rect left{-2560, -200, 0, 1240};
  CHECK(Same(host_geometry::ToDesktopPixel(left, 0.0, 0.0), -2560, -200));
  CHECK(Same(host_geometry::ToDesktopPixel(left, 0.5, 0.5), -1280, 520));
}

void AbsoluteCoordinatesSpanTheWholeVirtualDesktop() {
  const Rect desktop{-2560, -200, 1920, 1240};
  CHECK(Same(host_geometry::ToAbsolute(desktop, Point{-2560, -200}), 0, 0));
  CHECK(Same(host_geometry::ToAbsolute(desktop, Point{1919, 1239}), 65535,
             65535));
  // The primary monitor's origin sits 2560 px into a 4480 px wide desktop.
  const Point origin = host_geometry::ToAbsolute(desktop, Point{0, 0});
  CHECK(origin.x == 37457);
  CHECK(origin.y == 9108);
}

void AbsoluteCoordinatesNeverLeaveTheValidRange() {
  const Rect desktop{0, 0, 1920, 1080};
  CHECK(Same(host_geometry::ToAbsolute(desktop, Point{-50, 5000}), 0, 65535));
  const Rect degenerate{0, 0, 1, 1};
  CHECK(Same(host_geometry::ToAbsolute(degenerate, Point{0, 0}), 0, 0));
}

void OnlyFiniteValuesInsideThePictureAreNormalized() {
  CHECK(host_geometry::IsNormalized(0.0));
  CHECK(host_geometry::IsNormalized(1.0));
  CHECK(!host_geometry::IsNormalized(-0.01));
  CHECK(!host_geometry::IsNormalized(1.01));
  CHECK(!host_geometry::IsNormalized(std::nan("")));
}

void FramesShrinkToTheLimitAndKeepTheirShape() {
  Size size = host_geometry::FitWithin(3840, 2160, 1920);
  CHECK(size.width == 1920 && size.height == 1080);
  size = host_geometry::FitWithin(1080, 1920, 1280);
  CHECK(size.width == 720 && size.height == 1280);
  // Never enlarge, and never produce an empty frame.
  size = host_geometry::FitWithin(1280, 720, 1920);
  CHECK(size.width == 1280 && size.height == 720);
  size = host_geometry::FitWithin(8000, 2, 100);
  CHECK(size.width == 100 && size.height == 1);
  size = host_geometry::FitWithin(1920, 1080, 0);
  CHECK(size.width == 1920 && size.height == 1080);
}

void DragPathEndsExactlyOnTheTarget() {
  const auto path = host_geometry::DragPath(Point{0, 0}, Point{100, 50}, 10);
  CHECK(path.size() == 10);
  CHECK(Same(path.front(), 10, 5));
  CHECK(Same(path.back(), 100, 50));
  CHECK(host_geometry::DragPath(Point{0, 0}, Point{9, 9}, 0).size() == 1);
}

void JpegQualityIsClampedToTheEncoderRange() {
  CHECK(host_geometry::ClampQuality(0.8) > 0.79f);
  CHECK(host_geometry::ClampQuality(7.0) == 1.0f);
  CHECK(host_geometry::ClampQuality(-1.0) == 0.1f);
  CHECK(host_geometry::ClampQuality(std::nan("")) == 0.8f);
}
}  // namespace

int main() {
  NormalizedPositionsStayInsideTheMonitor();
  SecondaryMonitorLeftOfPrimaryUsesNegativeDesktopPixels();
  AbsoluteCoordinatesSpanTheWholeVirtualDesktop();
  AbsoluteCoordinatesNeverLeaveTheValidRange();
  OnlyFiniteValuesInsideThePictureAreNormalized();
  FramesShrinkToTheLimitAndKeepTheirShape();
  DragPathEndsExactlyOnTheTarget();
  JpegQualityIsClampedToTheEncoderRange();
  if (failures != 0) return EXIT_FAILURE;
  std::puts("host_geometry: all checks passed");
  return EXIT_SUCCESS;
}
