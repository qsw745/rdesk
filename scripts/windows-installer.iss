#ifndef AppVersion
#define AppVersion "2.1.1"
#endif
#ifndef BundleDir
#define BundleDir "..\flutter_client\build\windows\x64\runner\Release"
#endif
[Setup]
AppId={{A8973743-17FC-476A-B6F0-52B1C3D50AD7}
AppName=RDesk
AppVersion={#AppVersion}
AppPublisher=QSW
AppPublisherURL=https://qisw.top/rdesk/
DefaultDirName={localappdata}\Programs\RDesk
DefaultGroupName=RDesk
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=RDesk-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\rdesk.exe
[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\RDesk"; Filename: "{app}\rdesk.exe"
Name: "{autodesktop}\RDesk"; Filename: "{app}\rdesk.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\rdesk.exe"; Description: "Launch RDesk"; Flags: nowait postinstall skipifsilent
