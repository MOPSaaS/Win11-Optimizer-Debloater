; installer.iss - Inno Setup script for Win11 Performance Optimizer
; Build with: iscc installer.iss
; Requires Inno Setup 6+ : https://jrsoftware.org/isdl.php

#define AppName        "Win11 Performance Optimizer"
#define AppVersion     "1.0.0"
#define AppPublisher   "Local"
#define AppExeName     "Win11Optimizer.exe"

[Setup]
AppId={{8F2E1A7B-9C4D-4E6F-9A2B-5D7E8F1A2C3D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Win11Optimizer
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename=Win11Optimizer-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts"; Flags: checkedonce
Name: "autorunadmin"; Description: "Always run as Administrator (recommended)"; GroupDescription: "Behaviour"; Flags: checkedonce

[Files]
; Built EXE + companion files - point Source at the dist folder produced by Build-Exe.ps1
Source: "..\dist\Win11Optimizer.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\MainWindow.xaml";   DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\Modules\*";         DestDir: "{app}\Modules"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\Launch.bat";              DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Logs and backups are intentionally preserved under ProgramData so the user can revert
; after uninstall if needed. Delete manually from C:\ProgramData\Win11Optimizer if desired.
