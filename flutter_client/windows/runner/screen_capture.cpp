#include "screen_capture.h"

#include <windows.h>

#include <d3d11.h>
#include <dxgi1_2.h>
#include <objbase.h>
#include <ocidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstring>

#include "desktop_state.h"
#include "display_list.h"
#include "host_geometry.h"

using Microsoft::WRL::ComPtr;

namespace {

// How long a new duplication may wait for the desktop to present before the
// first picture is taken through GDI instead.
constexpr ULONGLONG kFirstFrameTimeoutMs = 200;
constexpr int kBytesPerPixel = 4;
constexpr float kSharpTextQuality = 0.75f;
// A display that could not be duplicated is tried again after this long:
// the cause may have been another program holding the duplication.
constexpr ULONGLONG kDuplicationRetryMs = 30000;

bool EncodeJpeg(IWICImagingFactory* wic, const std::vector<uint8_t>& pixels,
                int width, int height, host_geometry::Size target,
                float quality, std::vector<uint8_t>* jpeg) {
  const UINT stride = static_cast<UINT>(width * kBytesPerPixel);
  ComPtr<IWICBitmap> bitmap;
  // 32bppBGR: the fourth byte is padding. GDI leaves it zero, and treating
  // it as alpha would turn the whole frame transparent.
  if (FAILED(wic->CreateBitmapFromMemory(
          static_cast<UINT>(width), static_cast<UINT>(height),
          GUID_WICPixelFormat32bppBGR, stride,
          static_cast<UINT>(pixels.size()),
          const_cast<BYTE*>(pixels.data()), &bitmap))) {
    return false;
  }
  ComPtr<IWICBitmapSource> source = bitmap;
  if (target.width != width || target.height != height) {
    ComPtr<IWICBitmapScaler> scaler;
    if (FAILED(wic->CreateBitmapScaler(&scaler)) ||
        FAILED(scaler->Initialize(source.Get(),
                                  static_cast<UINT>(target.width),
                                  static_cast<UINT>(target.height),
                                  WICBitmapInterpolationModeFant))) {
      return false;
    }
    source = scaler;
  }
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(wic->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(source.Get(), GUID_WICPixelFormat24bppBGR,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return false;
  }

  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> options;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(wic->CreateEncoder(GUID_ContainerFormatJpeg, nullptr,
                                &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) ||
      FAILED(encoder->CreateNewFrame(&frame, &options))) {
    return false;
  }
  wchar_t quality_name[] = L"ImageQuality";
  wchar_t subsampling_name[] = L"JpegYCrCbSubsampling";
  PROPBAG2 option[2] = {};
  option[0].pstrName = quality_name;
  option[1].pstrName = subsampling_name;
  VARIANT value[2] = {};
  value[0].vt = VT_R4;
  value[0].fltVal = quality;
  // Full-resolution colour at normal quality and above: halved chroma is
  // what smears small coloured text. Low quality keeps the smaller default.
  value[1].vt = VT_UI1;
  value[1].bVal = static_cast<BYTE>(quality >= kSharpTextQuality
                                        ? WICJpegYCrCbSubsampling444
                                        : WICJpegYCrCbSubsampling420);
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  if (FAILED(options->Write(2, option, value)) ||
      FAILED(frame->Initialize(options.Get())) ||
      FAILED(frame->SetSize(static_cast<UINT>(target.width),
                            static_cast<UINT>(target.height))) ||
      FAILED(frame->SetPixelFormat(&format)) ||
      FAILED(frame->WriteSource(converter.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return false;
  }

  STATSTG stat{};
  LARGE_INTEGER start{};
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) ||
      stat.cbSize.QuadPart == 0 || stat.cbSize.HighPart != 0 ||
      FAILED(stream->Seek(start, STREAM_SEEK_SET, nullptr))) {
    return false;
  }
  jpeg->resize(stat.cbSize.LowPart);
  ULONG read = 0;
  return SUCCEEDED(stream->Read(jpeg->data(), stat.cbSize.LowPart, &read)) &&
         read == stat.cbSize.LowPart;
}

bool CaptureGdi(const DisplayInfo& display, std::vector<uint8_t>* pixels,
                int* width, int* height) {
  const int w = static_cast<int>(display.rect.width());
  const int h = static_cast<int>(display.rect.height());
  if (w <= 0 || h <= 0) return false;
  HDC screen = GetDC(nullptr);
  if (!screen) return false;
  HDC memory = CreateCompatibleDC(screen);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = w;
  info.bmiHeader.biHeight = -h;  // top-down rows, like the DXGI path
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  bool ok = false;
  if (memory && bitmap && bits) {
    HGDIOBJ previous = SelectObject(memory, bitmap);
    ok = BitBlt(memory, 0, 0, w, h, screen, display.rect.left,
                display.rect.top, SRCCOPY | CAPTUREBLT) != FALSE;
    GdiFlush();
    if (ok) {
      const auto* first = static_cast<const uint8_t*>(bits);
      const size_t size = static_cast<size_t>(w) * static_cast<size_t>(h) *
                          kBytesPerPixel;
      pixels->assign(first, first + size);
      *width = w;
      *height = h;
    }
    SelectObject(memory, previous);
  }
  if (bitmap) DeleteObject(bitmap);
  if (memory) DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return ok;
}

}  // namespace

struct ScreenCapture::Impl {
  enum class Dxgi { kNewFrame, kUnchanged, kLost, kUnsupported };

  bool allow_duplication = true;
  ComPtr<IWICImagingFactory> wic;
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<IDXGIOutputDuplication> duplication;
  ComPtr<ID3D11Texture2D> staging;
  HMONITOR duplicated = nullptr;
  // Duplication was not available for this display; do not retry every
  // frame, only after kDuplicationRetryMs.
  HMONITOR unsupported = nullptr;
  ULONGLONG unsupported_since = 0;

  // Last picture of |pixels_monitor|, kept so a still screen can be encoded
  // again when the viewer changes size or quality.
  std::vector<uint8_t> pixels;
  HMONITOR pixels_monitor = nullptr;
  int pixels_width = 0;
  int pixels_height = 0;

  Frame encoded;
  int64_t next_sequence = 1;
  bool encoded_valid = false;
  int encoded_max_dimension = 0;
  float encoded_quality = 0.0f;

  const char* backend = "none";

  void ResetDuplication() {
    duplication.Reset();
    staging.Reset();
    context.Reset();
    device.Reset();
    duplicated = nullptr;
  }

  void DropPicture() {
    std::vector<uint8_t>().swap(pixels);
    pixels_monitor = nullptr;
    pixels_width = 0;
    pixels_height = 0;
    encoded = Frame();
    encoded_valid = false;
  }

  HRESULT Duplicate(HMONITOR monitor) {
    ComPtr<IDXGIFactory1> factory;
    HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return hr;
    for (UINT a = 0;; ++a) {
      ComPtr<IDXGIAdapter1> adapter;
      if (FAILED(factory->EnumAdapters1(a, &adapter))) break;
      for (UINT o = 0;; ++o) {
        ComPtr<IDXGIOutput> output;
        if (FAILED(adapter->EnumOutputs(o, &output))) break;
        DXGI_OUTPUT_DESC desc{};
        if (FAILED(output->GetDesc(&desc)) || desc.Monitor != monitor) {
          continue;
        }
        // A rotated output is duplicated unrotated; GDI already delivers it
        // the way the user sees it.
        if (desc.Rotation != DXGI_MODE_ROTATION_IDENTITY &&
            desc.Rotation != DXGI_MODE_ROTATION_UNSPECIFIED) {
          return DXGI_ERROR_UNSUPPORTED;
        }
        D3D_FEATURE_LEVEL level = D3D_FEATURE_LEVEL_11_0;
        hr = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                               0, nullptr, 0, D3D11_SDK_VERSION, &device,
                               &level, &context);
        if (FAILED(hr)) return hr;
        ComPtr<IDXGIOutput1> output1;
        hr = output.As(&output1);
        if (FAILED(hr)) return hr;
        hr = output1->DuplicateOutput(device.Get(), &duplication);
        if (SUCCEEDED(hr)) duplicated = monitor;
        return hr;
      }
    }
    return DXGI_ERROR_NOT_FOUND;
  }

  Dxgi Acquire(const DisplayInfo& display) {
    if (!duplication || duplicated != display.monitor) {
      ResetDuplication();
      const HRESULT hr = Duplicate(display.monitor);
      if (FAILED(hr)) {
        ResetDuplication();
        // Denied means a secure desktop appeared meanwhile, which passes.
        return hr == E_ACCESSDENIED || hr == DXGI_ERROR_ACCESS_LOST ||
                       hr == DXGI_ERROR_SESSION_DISCONNECTED
                   ? Dxgi::kLost
                   : Dxgi::kUnsupported;
      }
    }
    const bool have_picture = pixels_monitor == display.monitor;
    const ULONGLONG deadline = GetTickCount64() + kFirstFrameTimeoutMs;
    ComPtr<IDXGIResource> resource;
    for (;;) {
      UINT timeout = 0;
      if (!have_picture) {
        const ULONGLONG now = GetTickCount64();
        if (now >= deadline) return Dxgi::kUnchanged;
        timeout = static_cast<UINT>(deadline - now);
      }
      DXGI_OUTDUPL_FRAME_INFO info{};
      resource.Reset();
      const HRESULT hr =
          duplication->AcquireNextFrame(timeout, &info, &resource);
      if (hr == DXGI_ERROR_WAIT_TIMEOUT) return Dxgi::kUnchanged;
      if (FAILED(hr)) {
        ResetDuplication();
        return Dxgi::kLost;
      }
      if (info.LastPresentTime.QuadPart != 0) break;
      // No desktop picture in this frame: either only the pointer moved, or
      // it is the blank frame a new duplication starts with on a still
      // screen. Using it would send the viewer a black image.
      duplication->ReleaseFrame();
      if (have_picture) return Dxgi::kUnchanged;
    }
    ComPtr<ID3D11Texture2D> texture;
    D3D11_TEXTURE2D_DESC desc{};
    if (SUCCEEDED(resource.As(&texture))) texture->GetDesc(&desc);
    if (!texture || desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) {
      duplication->ReleaseFrame();
      ResetDuplication();
      return Dxgi::kUnsupported;
    }
    D3D11_TEXTURE2D_DESC wanted = desc;
    wanted.MipLevels = 1;
    wanted.ArraySize = 1;
    wanted.SampleDesc.Count = 1;
    wanted.SampleDesc.Quality = 0;
    wanted.Usage = D3D11_USAGE_STAGING;
    wanted.BindFlags = 0;
    wanted.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    wanted.MiscFlags = 0;
    D3D11_TEXTURE2D_DESC current{};
    if (staging) staging->GetDesc(&current);
    if (!staging || current.Width != wanted.Width ||
        current.Height != wanted.Height) {
      staging.Reset();
      if (FAILED(device->CreateTexture2D(&wanted, nullptr, &staging))) {
        duplication->ReleaseFrame();
        ResetDuplication();
        return Dxgi::kLost;
      }
    }
    context->CopyResource(staging.Get(), texture.Get());
    duplication->ReleaseFrame();

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
      ResetDuplication();
      return Dxgi::kLost;
    }
    const size_t row = static_cast<size_t>(desc.Width) * kBytesPerPixel;
    // A presented frame is not necessarily a different picture: a window
    // that merely redraws itself presents too, and this application does so
    // whenever it learns of a new frame, which would keep itself busy. So
    // compare while copying, and only report what really changed.
    bool differs = !have_picture || pixels.size() != row * desc.Height;
    pixels.resize(row * desc.Height);
    const auto* from = static_cast<const uint8_t*>(mapped.pData);
    for (UINT y = 0; y < desc.Height; ++y) {
      uint8_t* to = pixels.data() + row * y;
      const uint8_t* line = from + mapped.RowPitch * y;
      if (!differs && std::memcmp(to, line, row) != 0) differs = true;
      if (differs) std::memcpy(to, line, row);
    }
    context->Unmap(staging.Get(), 0);
    pixels_monitor = display.monitor;
    pixels_width = static_cast<int>(desc.Width);
    pixels_height = static_cast<int>(desc.Height);
    return differs ? Dxgi::kNewFrame : Dxgi::kUnchanged;
  }

  // Refreshes |pixels| for |display|. False when no picture could be had.
  bool Refresh(const DisplayInfo& display, bool* changed) {
    *changed = false;
    if (unsupported == display.monitor &&
        GetTickCount64() - unsupported_since >= kDuplicationRetryMs) {
      unsupported = nullptr;
    }
    if (allow_duplication && unsupported != display.monitor) {
      // One retry: the first loss after a mode change or a returning
      // desktop is expected and a fresh duplication normally succeeds.
      for (int attempt = 0; attempt < 2; ++attempt) {
        const Dxgi result = Acquire(display);
        if (result == Dxgi::kNewFrame) {
          *changed = true;
          backend = "dxgi";
          return true;
        }
        if (result == Dxgi::kUnchanged) {
          if (pixels_monitor == display.monitor) return true;
          // A still screen presents nothing to a new duplication. Take the
          // first picture through GDI; duplication delivers later changes.
          break;
        }
        if (result == Dxgi::kUnsupported) {
          unsupported = display.monitor;
          unsupported_since = GetTickCount64();
          break;
        }
      }
    }
    int width = 0;
    int height = 0;
    std::vector<uint8_t> fresh;
    if (!CaptureGdi(display, &fresh, &width, &height)) return false;
    // GDI cannot say whether anything changed, so compare: an unchanged
    // picture is then neither encoded nor sent again.
    *changed = pixels_monitor != display.monitor || width != pixels_width ||
               height != pixels_height || fresh != pixels;
    if (*changed) pixels.swap(fresh);
    pixels_monitor = display.monitor;
    pixels_width = width;
    pixels_height = height;
    backend = "gdi";
    return true;
  }
};

ScreenCapture::ScreenCapture(bool allow_duplication)
    : impl_(std::make_unique<Impl>()) {
  impl_->allow_duplication = allow_duplication;
}

ScreenCapture::~ScreenCapture() = default;

const char* ScreenCapture::backend() const { return impl_->backend; }

void ScreenCapture::Release() {
  impl_->ResetDuplication();
  impl_->DropPicture();
  impl_->unsupported = nullptr;
  impl_->wic.Reset();
}

ScreenCapture::Status ScreenCapture::Capture(int display_index,
                                             int max_dimension, double quality,
                                             Frame* frame) {
  const DesktopState desktop = CurrentDesktopState();
  if (desktop != DesktopState::kDefault) {
    // Keep nothing from before the lock: the retained picture must not be
    // served again while the screen is supposed to be hidden.
    impl_->ResetDuplication();
    impl_->DropPicture();
    return desktop == DesktopState::kLocked ? Status::kSessionLocked
                                            : Status::kSecureDesktop;
  }
  DisplayInfo display;
  if (!DisplayAt(display_index, &display)) return Status::kFailed;
  // A picture of another display, or of this one before its resolution
  // changed, is not the current screen.
  if (impl_->pixels_monitor != display.monitor ||
      impl_->pixels_width != display.rect.width() ||
      impl_->pixels_height != display.rect.height()) {
    impl_->DropPicture();
  }

  bool changed = false;
  if (!impl_->Refresh(display, &changed)) {
    impl_->DropPicture();
    // The desktop may have been taken over while the capture was running.
    const DesktopState now = CurrentDesktopState();
    if (now == DesktopState::kLocked) return Status::kSessionLocked;
    if (now == DesktopState::kSecure) return Status::kSecureDesktop;
    return Status::kFailed;
  }

  // The desktop may have been taken over while the picture was taken.
  const DesktopState after = CurrentDesktopState();
  if (after != DesktopState::kDefault) {
    impl_->ResetDuplication();
    impl_->DropPicture();
    return after == DesktopState::kLocked ? Status::kSessionLocked
                                          : Status::kSecureDesktop;
  }

  const float jpeg_quality = host_geometry::ClampQuality(quality);
  const bool reusable = impl_->encoded_valid && !changed &&
                        impl_->encoded_max_dimension == max_dimension &&
                        impl_->encoded_quality == jpeg_quality;
  if (!reusable) {
    if (!impl_->wic &&
        FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&impl_->wic)))) {
      return Status::kFailed;
    }
    const host_geometry::Size target = host_geometry::FitWithin(
        impl_->pixels_width, impl_->pixels_height, max_dimension);
    impl_->encoded_valid = false;
    if (!EncodeJpeg(impl_->wic.Get(), impl_->pixels, impl_->pixels_width,
                    impl_->pixels_height, target, jpeg_quality,
                    &impl_->encoded.jpeg)) {
      return Status::kFailed;
    }
    impl_->encoded.width = target.width;
    impl_->encoded.height = target.height;
    impl_->encoded.sequence = impl_->next_sequence++;
    impl_->encoded_max_dimension = max_dimension;
    impl_->encoded_quality = jpeg_quality;
    impl_->encoded_valid = true;
  }
  *frame = impl_->encoded;
  return Status::kOk;
}
