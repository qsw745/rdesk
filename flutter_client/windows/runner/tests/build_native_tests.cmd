@echo off
rem Builds the Windows host's native checks next to this file. Local only:
rem run it on a Windows PC or local VM with Visual Studio 2022 C++ tools.
rem   host_geometry_test.exe  pure arithmetic, runs anywhere
rem   host_smoke.exe          needs an unlocked, signed-in desktop session
setlocal
cd /d "%~dp0"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
"%VSWHERE%" -latest -version [17.0,18.0) -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%TEMP%\rdesk_vs_path.txt"
set /p VS=<"%TEMP%\rdesk_vs_path.txt"
del "%TEMP%\rdesk_vs_path.txt"
if not defined VS (echo Visual Studio 2022 C++ tools not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "FLAGS=/nologo /std:c++17 /EHsc /W4 /WX /utf-8 /O2 /DUNICODE /D_UNICODE /DNOMINMAX /DWIN32_LEAN_AND_MEAN /D_HAS_EXCEPTIONS=0 /I.."
cl %FLAGS% host_geometry_test.cpp /Fe:host_geometry_test.exe || exit /b 1
cl %FLAGS% host_smoke.cpp ..\screen_capture.cpp ..\display_list.cpp ..\input_injector.cpp ..\desktop_state.cpp /Fe:host_smoke.exe /link d3d11.lib dxgi.lib windowscodecs.lib wtsapi32.lib user32.lib gdi32.lib ole32.lib advapi32.lib || exit /b 1
del /q *.obj 2>nul
host_geometry_test.exe || exit /b 1
echo Built. Run host_smoke.exe in the signed-in user's session.
