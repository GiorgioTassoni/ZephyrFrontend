; Zephyr Music Client - Windows installer script (Inno Setup)
;
; Compile it with ISCC from the desktop app folder:
;   ISCC.exe windows/installer/ZephyrInstaller.iss /DMyAppVersion=1.1.1 /DMyAppChannel=Preview
;
; All relative paths resolve against the folder containing this file
; (apps/zephyr_desktop/windows/installer/), except the Flutter release
; bundle which is expected at apps/zephyr_desktop/build/windows/x64/runner/Release/.

#ifndef MyAppVersion
  #define MyAppVersion "1.1.1"
#endif
#ifndef MyAppChannel
  #define MyAppChannel "Preview"
#endif

[Setup]
AppId={{7A5C9F3E-2B41-4D8E-9C63-0F1D2A6B4E88}
AppName=Zephyr Music Client
AppVersion={#MyAppVersion}
AppVerName=Zephyr Music Client {#MyAppVersion} ({#MyAppChannel})
AppPublisher=Giorgio Tassoni
AppPublisherURL=https://github.com/GiorgioTassoni/ZephyrFrontend
DefaultDirName={autopf}\ZephyrMusicClient
DefaultGroupName=Zephyr
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\frontend.exe
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\build\installer
OutputBaseFilename=Zephyr-Setup-{#MyAppVersion}-{#MyAppChannel}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763.0
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Zephyr"; Filename: "{app}\frontend.exe"
Name: "{autodesktop}\Zephyr"; Filename: "{app}\frontend.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\frontend.exe"; Description: "{cm:LaunchProgram,Zephyr Music Client}"; Flags: nowait postinstall skipifsilent