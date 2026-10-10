// Local check of the Windows host's capture and input code against a real
// desktop. It needs an unlocked, signed-in session: run it as the logged-in
// user, never as a service. Build with tests\build_native_tests.cmd.
//
//   host_smoke displays
//   host_smoke capture <out.jpg> [max_dimension] [gdi]
//   host_smoke input
//   host_smoke click <x> <y>     left click at a 0..1 position (primary)
//   host_smoke cursor            print the pointer position
//
// The console a command is started from is a window too and can cover the
// spot being clicked; the click then reaches the terminal, not the target.
// Start `click` minimised:  start "" /min host_smoke.exe click 0.5 0.5
//
// `capture` shows a coloured window on the primary display and looks for
// that colour in the decoded result, so a blank frame cannot pass. `input`
// opens its own small window, drives it through input_injector and reads
// back what arrived. Neither touches any other application.
#include <windows.h>

#include <objbase.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "display_list.h"
#include "host_geometry.h"
#include "input_injector.h"
#include "screen_capture.h"

namespace {

int failures = 0;

void Check(bool ok, const char* what) {
  std::printf("%s  %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) ++failures;
}

int Displays() {
  int index = 0;
  for (const DisplayInfo& display : EnumerateDisplays()) {
    std::printf("%d: %ldx%ld at (%ld,%ld)%s\n", index++, display.rect.width(),
                display.rect.height(), display.rect.left, display.rect.top,
                display.primary ? " primary" : "");
  }
  const host_geometry::Rect desktop = VirtualDesktopRect();
  std::printf("virtual desktop %ldx%ld at (%ld,%ld)\n", desktop.width(),
              desktop.height(), desktop.left, desktop.top);
  return index > 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

const char* Name(ScreenCapture::Status status) {
  switch (status) {
    case ScreenCapture::Status::kOk:
      return "ok";
    case ScreenCapture::Status::kSessionLocked:
      return "session locked";
    case ScreenCapture::Status::kSecureDesktop:
      return "secure desktop";
    case ScreenCapture::Status::kFailed:
      return "failed";
  }
  return "unknown";
}

// --- capture -------------------------------------------------------------

constexpr wchar_t kSwatchClass[] = L"RDeskHostSmokeSwatch";
constexpr int kSwatchLeft = 200;
constexpr int kSwatchTop = 200;
constexpr int kSwatchWidth = 480;
constexpr int kSwatchHeight = 320;
COLORREF g_swatch_colour = RGB(255, 0, 128);

LRESULT CALLBACK SwatchProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  if (message == WM_ERASEBKGND) {
    RECT client{};
    GetClientRect(window, &client);
    HBRUSH brush = CreateSolidBrush(g_swatch_colour);
    FillRect(reinterpret_cast<HDC>(wparam), &client, brush);
    DeleteObject(brush);
    return 1;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void PumpFor(DWORD milliseconds) {
  const ULONGLONG until = GetTickCount64() + milliseconds;
  while (GetTickCount64() < until) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    Sleep(10);
  }
}

void Paint(HWND swatch, COLORREF colour) {
  g_swatch_colour = colour;
  RedrawWindow(swatch, nullptr, nullptr,
               RDW_ERASE | RDW_INVALIDATE | RDW_UPDATENOW);
  PumpFor(400);
}

// Decodes |frame| and reads the pixel that shows desktop pixel (x, y) of
// |display|. A capture that "succeeds" with a blank image fails here.
bool PixelAt(const ScreenCapture::Frame& frame, const DisplayInfo& display,
             long x, long y, COLORREF* colour) {
  Microsoft::WRL::ComPtr<IWICImagingFactory> wic;
  Microsoft::WRL::ComPtr<IStream> stream;
  Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder;
  Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> decoded;
  Microsoft::WRL::ComPtr<IWICFormatConverter> converter;
  UINT width = 0;
  UINT height = 0;
  if (frame.jpeg.empty() ||
      FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic))) ||
      FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(stream->Write(frame.jpeg.data(),
                           static_cast<ULONG>(frame.jpeg.size()), nullptr))) {
    return false;
  }
  LARGE_INTEGER start{};
  if (FAILED(stream->Seek(start, STREAM_SEEK_SET, nullptr)) ||
      FAILED(wic->CreateDecoderFromStream(stream.Get(), nullptr,
                                          WICDecodeMetadataCacheOnDemand,
                                          &decoder)) ||
      FAILED(decoder->GetFrame(0, &decoded)) ||
      FAILED(wic->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(decoded.Get(), GUID_WICPixelFormat32bppBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom)) ||
      FAILED(converter->GetSize(&width, &height)) ||
      static_cast<int>(width) != frame.width ||
      static_cast<int>(height) != frame.height) {
    return false;
  }
  const double scale_x =
      static_cast<double>(width) / static_cast<double>(display.rect.width());
  const double scale_y =
      static_cast<double>(height) / static_cast<double>(display.rect.height());
  WICRect at{};
  at.X = static_cast<INT>(static_cast<double>(x - display.rect.left) * scale_x);
  at.Y = static_cast<INT>(static_cast<double>(y - display.rect.top) * scale_y);
  at.Width = 1;
  at.Height = 1;
  BYTE bgra[4] = {};
  if (FAILED(converter->CopyPixels(&at, 4, sizeof(bgra), bgra))) return false;
  *colour = RGB(bgra[2], bgra[1], bgra[0]);
  return true;
}

bool Near(COLORREF actual, COLORREF expected) {
  const auto close = [](int a, int b) { return std::abs(a - b) <= 40; };
  return close(GetRValue(actual), GetRValue(expected)) &&
         close(GetGValue(actual), GetGValue(expected)) &&
         close(GetBValue(actual), GetBValue(expected));
}

// Captures and checks that the swatch shows |expected| in the result.
bool Shows(ScreenCapture* capture, const DisplayInfo& display,
           int max_dimension, COLORREF expected, const char* what,
           ScreenCapture::Frame* frame) {
  const ScreenCapture::Status status =
      capture->Capture(0, max_dimension, 0.8, frame);
  COLORREF seen = 0;
  const bool decoded =
      status == ScreenCapture::Status::kOk &&
      PixelAt(*frame, display, kSwatchLeft + kSwatchWidth / 2,
              kSwatchTop + kSwatchHeight / 2, &seen);
  std::printf("%s: %s, backend %s, %dx%d, %zu bytes, swatch #%02X%02X%02X\n",
              what, Name(status), capture->backend(), frame->width,
              frame->height, frame->jpeg.size(), GetRValue(seen),
              GetGValue(seen), GetBValue(seen));
  const bool ok = decoded && Near(seen, expected);
  Check(ok, what);
  return ok;
}

int Capture(const char* path, int max_dimension, bool allow_duplication) {
  DisplayInfo display;
  if (!DisplayAt(0, &display)) return EXIT_FAILURE;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = SwatchProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = kSwatchClass;
  RegisterClassW(&window_class);
  HWND swatch = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, kSwatchClass, L"",
      WS_POPUP | WS_VISIBLE, static_cast<int>(display.rect.left) + kSwatchLeft,
      static_cast<int>(display.rect.top) + kSwatchTop, kSwatchWidth,
      kSwatchHeight, nullptr, nullptr, window_class.hInstance, nullptr);
  if (!swatch) return EXIT_FAILURE;
  const COLORREF magenta = RGB(255, 0, 128);
  const COLORREF green = RGB(0, 200, 80);
  Paint(swatch, magenta);
  // Let the screen settle, so the first capture meets a desktop that is not
  // presenting anything: that is when a new duplication hands out a blank.
  PumpFor(1500);

  ScreenCapture capture(allow_duplication);
  ScreenCapture::Frame first;
  Shows(&capture, display, max_dimension, magenta,
        "first capture of a still screen shows the real desktop", &first);

  Paint(swatch, green);
  ScreenCapture::Frame changed;
  Shows(&capture, display, max_dimension, green,
        "a change on screen appears in the next capture", &changed);

  // A screen that did not change must keep answering with the picture.
  bool still_ok = true;
  for (int i = 0; i < 5; ++i) {
    PumpFor(100);
    ScreenCapture::Frame again;
    COLORREF seen = 0;
    still_ok = still_ok &&
               capture.Capture(0, max_dimension, 0.8, &again) ==
                   ScreenCapture::Status::kOk &&
               PixelAt(again, display, kSwatchLeft + kSwatchWidth / 2,
                       kSwatchTop + kSwatchHeight / 2, &seen) &&
               Near(seen, green);
  }
  Check(still_ok, "repeated captures of a still screen keep the picture");

  // A viewer changing size must be served even when nothing moved.
  ScreenCapture::Frame smaller;
  Shows(&capture, display, 640, green,
        "a new size is honoured without waiting for a screen change",
        &smaller);
  Check(std::max(smaller.width, smaller.height) <= 640,
        "the smaller size is respected");

  capture.Release();
  ScreenCapture::Frame after;
  Shows(&capture, display, max_dimension, green,
        "capture works again after Release", &after);

  DestroyWindow(swatch);
  FILE* file = nullptr;
  if (fopen_s(&file, path, "wb") != 0 || !file) return EXIT_FAILURE;
  std::fwrite(changed.jpeg.data(), 1, changed.jpeg.size(), file);
  std::fclose(file);
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

// --- input ---------------------------------------------------------------

constexpr wchar_t kWindowClass[] = L"RDeskHostSmoke";
HWND g_edit = nullptr;
WNDPROC g_edit_proc = nullptr;
std::atomic<int> g_wheel{0};
std::atomic<int> g_right_clicks{0};
std::atomic<int> g_select_all{0};
std::atomic<int> g_keys_without_scan_code{0};

LRESULT CALLBACK EditProc(HWND window, UINT message, WPARAM wparam,
                          LPARAM lparam) {
  if (message == WM_MOUSEWHEEL) ++g_wheel;
  if (message == WM_RBUTTONUP) ++g_right_clicks;
  // The edit control's own menu would swallow the rest of the test.
  if (message == WM_CONTEXTMENU) return 0;
  // A multiline edit control has no Ctrl+A of its own, so provide one. The
  // key must arrive as an A with Control really held.
  // Flutter tells keys apart by scan code, so every key must carry one.
  // (Typed text arrives as VK_PACKET, which has no key to identify.)
  if (message == WM_KEYDOWN && wparam != VK_PACKET &&
      ((lparam >> 16) & 0xFF) == 0) {
    ++g_keys_without_scan_code;
  }
  if (message == WM_KEYDOWN && wparam == 'A' &&
      (GetKeyState(VK_CONTROL) & 0x8000) != 0) {
    ++g_select_all;
    SendMessageW(window, EM_SETSEL, 0, -1);
    return 0;
  }
  if (message == WM_CHAR && wparam == 1) return 0;
  return CallWindowProcW(g_edit_proc, window, message, wparam, lparam);
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

std::wstring EditText() {
  wchar_t buffer[256] = {};
  SendMessageW(g_edit, WM_GETTEXT, ARRAYSIZE(buffer),
               reinterpret_cast<LPARAM>(buffer));
  return buffer;
}

void Selection(DWORD* start, DWORD* end) {
  SendMessageW(g_edit, EM_GETSEL, reinterpret_cast<WPARAM>(start),
               reinterpret_cast<LPARAM>(end));
}

// Normalised position on the primary display of a point in the edit control.
void Normalised(const DisplayInfo& display, int client_x, int client_y,
                double* x, double* y, POINT* screen) {
  *screen = POINT{client_x, client_y};
  ClientToScreen(g_edit, screen);
  *x = (static_cast<double>(screen->x - display.rect.left) + 0.5) /
       static_cast<double>(display.rect.width());
  *y = (static_cast<double>(screen->y - display.rect.top) + 0.5) /
       static_cast<double>(display.rect.height());
}

void DriveInput(HWND window) {
  DisplayInfo display;
  DisplayAt(0, &display);
  RECT client{};
  GetClientRect(g_edit, &client);
  double x = 0;
  double y = 0;
  POINT target{};

  Normalised(display, client.right / 2, client.bottom / 2, &x, &y, &target);
  Check(input_injector::Click(0, x, y, false), "left click is accepted");
  Sleep(300);
  POINT cursor{};
  GetCursorPos(&cursor);
  std::printf("click target (%ld,%ld), pointer at (%ld,%ld)\n", target.x,
              target.y, cursor.x, cursor.y);
  Check(std::abs(cursor.x - target.x) <= 1 && std::abs(cursor.y - target.y) <= 1,
        "pointer lands on the requested pixel");
  Check(GetForegroundWindow() == window, "the click activates the window");

  const std::wstring text = L"Hello 你好 \U0001F600";
  Check(input_injector::TypeText(text), "text is accepted");
  Sleep(300);
  Check(EditText() == text, "typed text arrives intact, including non-BMP");

  Check(input_injector::KeyPress('A', {VK_LCONTROL}), "Ctrl+A is accepted");
  Sleep(200);
  DWORD start = 1;
  DWORD end = 0;
  Selection(&start, &end);
  Check(g_select_all.load() == 1, "A arrives once with Control held");
  Check(start == 0 && end == text.size(), "Ctrl+A selects everything");
  Check((GetAsyncKeyState(VK_CONTROL) & 0x8000) == 0,
        "no modifier is left held down");

  Check(input_injector::KeyPress(VK_BACK, {}), "Backspace is accepted");
  Sleep(200);
  Check(EditText().empty(), "Backspace deletes the selection");

  Check(input_injector::TypeText(L"abcdefgh"), "more text is accepted");
  Sleep(200);
  Check(input_injector::KeyPress(VK_LEFT, {}), "Left arrow is accepted");
  Sleep(200);
  Selection(&start, &end);
  Check(start == 7 && end == 7, "Left arrow moves the caret one position");

  // Dragging across the first line selects text in an edit control.
  double end_x = 0;
  double end_y = 0;
  POINT drag_end{};
  Normalised(display, 2, 10, &x, &y, &target);
  Normalised(display, client.right - 10, 10, &end_x, &end_y, &drag_end);
  Check(input_injector::Drag(0, x, y, end_x, end_y), "drag is accepted");
  Sleep(300);
  Selection(&start, &end);
  Check(end > start, "drag selects text");
  Check((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0,
        "the mouse button is released after the drag");

  Check(input_injector::Scroll(3), "scroll is accepted");
  Sleep(200);
  Check(g_wheel.load() > 0, "the wheel event reaches the window");

  Normalised(display, client.right / 2, client.bottom / 2, &x, &y, &target);
  Check(input_injector::Click(0, x, y, true), "right click is accepted");
  Sleep(300);
  Check(g_right_clicks.load() == 1, "exactly one right click arrives");

  Check(g_keys_without_scan_code.load() == 0,
        "every key press carries a hardware scan code");
  Check(!input_injector::Click(0, 1.5, 0.5, false),
        "a position outside the display is refused");
  Check(!input_injector::KeyPress(0, {}), "an invalid key is refused");

  PostMessageW(window, WM_CLOSE, 0, 0);
}

int Input() {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = kWindowClass;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);
  HWND window = CreateWindowExW(
      WS_EX_TOPMOST, kWindowClass, L"RDesk host smoke test",
      WS_POPUP | WS_VISIBLE | WS_BORDER, 120, 120, 640, 240, nullptr, nullptr,
      window_class.hInstance, nullptr);
  if (!window) return EXIT_FAILURE;
  RECT client{};
  GetClientRect(window, &client);
  g_edit = CreateWindowExW(0, L"EDIT", L"",
                           WS_CHILD | WS_VISIBLE | ES_MULTILINE, 0, 0,
                           client.right, client.bottom, window, nullptr,
                           window_class.hInstance, nullptr);
  if (!g_edit) return EXIT_FAILURE;
  g_edit_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
      g_edit, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(EditProc)));
  SetFocus(g_edit);

  std::thread driver([window]() {
    Sleep(500);
    DriveInput(window);
  });
  MSG message;
  while (GetMessageW(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  driver.join();
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

}  // namespace

int main(int argc, char** argv) {
  // Same DPI mode as the application, so pixels mean the same thing.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const std::string mode = argc > 1 ? argv[1] : "";
  int code = EXIT_FAILURE;
  if (mode == "displays") {
    code = Displays();
  } else if (mode == "capture" && argc > 2) {
    const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    code = Capture(argv[2], argc > 3 ? std::atoi(argv[3]) : 1920,
                   !(argc > 4 && std::string(argv[4]) == "gdi"));
    if (SUCCEEDED(com)) CoUninitialize();
  } else if (mode == "input") {
    code = Input();
  } else if (mode == "click" && argc > 3) {
    code = input_injector::Click(0, std::atof(argv[2]), std::atof(argv[3]),
                                 false)
               ? EXIT_SUCCESS
               : EXIT_FAILURE;
  } else if (mode == "cursor") {
    POINT cursor{};
    GetCursorPos(&cursor);
    std::printf("cursor %ld %ld\n", cursor.x, cursor.y);
    code = EXIT_SUCCESS;
  } else {
    std::puts("usage: host_smoke displays | capture <out.jpg> "
              "[max_dimension] [gdi] | input | click <x> <y> | cursor");
  }
  std::printf("%s\n", code == EXIT_SUCCESS ? "PASSED" : "FAILED");
  return code;
}
