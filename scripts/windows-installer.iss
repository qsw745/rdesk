; Requires Inno Setup 6.7+ (dark mode, WizardBackImageFile, windows11 style).
; Artwork: python3 design/generate_installer_art.py -> scripts/installer/.
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
AppVerName=RDesk {#AppVersion}
AppPublisher=QSW
AppPublisherURL=https://qisw.top/rdesk/
AppSupportURL=https://qisw.top/rdesk/
VersionInfoVersion={#AppVersion}
VersionInfoDescription=RDesk 安装程序
DefaultDirName={localappdata}\Programs\RDesk
DefaultGroupName=RDesk
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableDirPage=auto
DisableReadyPage=yes
UsePreviousTasks=no
ShowLanguageDialog=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=RDesk-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\flutter_client\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\rdesk.exe
UninstallDisplayName=RDesk
WizardStyle=modern dynamic windows11 hidebevels
WizardImageFile=installer\wizard-100.png,installer\wizard-150.png,installer\wizard-200.png
WizardImageFileDynamicDark=installer\wizard-100.png,installer\wizard-150.png,installer\wizard-200.png
WizardSmallImageFile=installer\small-100.png,installer\small-150.png,installer\small-200.png
WizardSmallImageFileDynamicDark=installer\small-100.png,installer\small-150.png,installer\small-200.png
WizardBackImageFile=installer\back-light-100.png,installer\back-light-150.png,installer\back-light-200.png
WizardBackImageFileDynamicDark=installer\back-dark-100.png,installer\back-dark-150.png,installer\back-dark-200.png
WizardBackColor=#FFFFFF
WizardBackColorDynamicDark=#15181F
[Languages]
Name: "zh"; MessagesFile: "compiler:Default.isl,installer\ChineseSimplified.isl"
[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\RDesk"; Filename: "{app}\rdesk.exe"
Name: "{autodesktop}\RDesk"; Filename: "{app}\rdesk.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"
Name: "autostart"; Description: "{cm:AutoStartProgramHint}"; Flags: unchecked
[Run]
Filename: "{app}\rdesk.exe"; Description: "{cm:LaunchProgram,RDesk}"; Flags: nowait postinstall skipifsilent
[Code]
{ Sign-in launch shares the current user's Run value with the in-app switch
  (LoginItemService): same name, same quoted path and --hidden (start in tray). The task starts from the
  real state, so an upgrade never silently turns it on or off. Windows
  "Startup apps" disables an entry via StartupApproved\Run (odd first byte). }
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  ApprovedKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  RunValue = 'RDesk';
var
  TasksPageShown: Boolean;

function AutoStartEnabled(): Boolean;
var
  Command: String;
  Flags: AnsiString;
begin
  Result := RegQueryStringValue(HKCU, RunKey, RunValue, Command) and (Command <> '');
  if Result and RegQueryBinaryValue(HKCU, ApprovedKey, RunValue, Flags) and (Length(Flags) > 0) then
    Result := (Ord(Flags[1]) mod 2) = 0;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpSelectTasks) and not TasksPageShown then
  begin
    TasksPageShown := True;
    if AutoStartEnabled() then
      WizardSelectTasks('autostart')
    else
      WizardSelectTasks('!autostart');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep <> ssPostInstall then
    Exit;
  if WizardIsTaskSelected('autostart') then
  begin
    RegWriteStringValue(HKCU, RunKey, RunValue, '"' + ExpandConstant('{app}\rdesk.exe') + '" --hidden');
    RegDeleteValue(HKCU, ApprovedKey, RunValue);
  end
  { A silent install never showed the choice, so leave the current setting. }
  else if TasksPageShown then
    RegDeleteValue(HKCU, RunKey, RunValue);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteValue(HKCU, RunKey, RunValue);
    RegDeleteValue(HKCU, ApprovedKey, RunValue);
  end;
end;
