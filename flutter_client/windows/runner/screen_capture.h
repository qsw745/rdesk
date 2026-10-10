#ifndef RUNNER_SCREEN_CAPTURE_H_
#define RUNNER_SCREEN_CAPTURE_H_

#include <cstdint>
#include <memory>
#include <vector>

// On-demand capture of one display as JPEG for the Windows host.
//
// DXGI desktop duplication is the normal path. GDI is used only where
// duplication is not offered (some virtual machines and remote sessions) or
// for a rotated display. Nothing is held between viewing sessions: Release()
// drops every graphics resource and the retained picture.
//
// An instance belongs to one thread, which must have initialised COM.
class ScreenCapture {
 public:
  enum class Status {
    kOk,
    // The workstation is locked; a user-session process cannot see it.
    kSessionLocked,
    // A UAC prompt or another secure desktop currently owns the screen.
    kSecureDesktop,
    kFailed,
  };

  struct Frame {
    std::vector<uint8_t> jpeg;
    int width = 0;
    int height = 0;
    // Changes only when the picture does. A caller that already has this
    // sequence holds the same bytes and need not send them again.
    int64_t sequence = 0;
  };

  // |allow_duplication| false keeps to the GDI path, which is how the
  // fallback is exercised on machines where duplication works.
  explicit ScreenCapture(bool allow_duplication = true);
  ~ScreenCapture();
  ScreenCapture(const ScreenCapture&) = delete;
  ScreenCapture& operator=(const ScreenCapture&) = delete;

  // A still screen yields the previous picture again rather than a failure:
  // "nothing changed" is not evidence that capture stopped working.
  Status Capture(int display_index, int max_dimension, double quality,
                 Frame* frame);

  void Release();

  // "dxgi", "gdi", or "none" before the first successful capture.
  const char* backend() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_SCREEN_CAPTURE_H_
