#include "desktop_state.h"

#include <wtsapi32.h>

#include <cwchar>

namespace {

bool SessionLocked() {
  WTSINFOEXW* info = nullptr;
  DWORD bytes = 0;
  bool locked = false;
  if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE,
                                  WTS_CURRENT_SESSION, WTSSessionInfoEx,
                                  reinterpret_cast<LPWSTR*>(&info), &bytes) &&
      info) {
    locked = info->Level == 1 &&
             info->Data.WTSInfoExLevel1.SessionFlags == WTS_SESSIONSTATE_LOCK;
    WTSFreeMemory(info);
  }
  return locked;
}

// The mandatory integrity level of |process|, or false if it is not readable.
bool IntegrityLevel(HANDLE process, DWORD* level) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token)) return false;
  BYTE buffer[SECURITY_MAX_SID_SIZE + sizeof(TOKEN_MANDATORY_LABEL)] = {};
  DWORD size = 0;
  bool ok = false;
  if (GetTokenInformation(token, TokenIntegrityLevel, buffer, sizeof(buffer),
                          &size)) {
    const auto* label = reinterpret_cast<const TOKEN_MANDATORY_LABEL*>(buffer);
    const UCHAR count = *GetSidSubAuthorityCount(label->Label.Sid);
    if (count > 0) {
      *level = *GetSidSubAuthority(label->Label.Sid,
                                   static_cast<DWORD>(count - 1));
      ok = true;
    }
  }
  CloseHandle(token);
  return ok;
}

}  // namespace

DesktopState CurrentDesktopState() {
  HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  if (!desktop) {
    if (GetLastError() != ERROR_ACCESS_DENIED) return DesktopState::kDefault;
    return SessionLocked() ? DesktopState::kLocked : DesktopState::kSecure;
  }
  wchar_t name[64] = {};
  DWORD needed = 0;
  const bool named = GetUserObjectInformationW(desktop, UOI_NAME, name,
                                               sizeof(name), &needed) != FALSE;
  CloseDesktop(desktop);
  if (!named || _wcsicmp(name, L"Default") == 0) return DesktopState::kDefault;
  return SessionLocked() ? DesktopState::kLocked : DesktopState::kSecure;
}

bool RunsAboveThisProcess(HWND window) {
  if (!window) return false;
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0 || process_id == GetCurrentProcessId()) return false;
  DWORD own = 0;
  if (!IntegrityLevel(GetCurrentProcess(), &own)) return false;
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) return false;
  DWORD theirs = 0;
  const bool known = IntegrityLevel(process, &theirs);
  CloseHandle(process);
  return known && theirs > own;
}
