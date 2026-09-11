; Inno Setup script for the KHInsider Windows build.
; CI: choco install innosetup -y && iscc packaging/windows/khinsider.iss
; (the flutter build must have run first — files come from app\build\windows\x64\runner\Release)

#define AppName "KHInsider"
#define AppExe "khinsider.exe"
#define AppVersion GetEnv("APP_VERSION")

[Setup]
AppId={{7A3C2E91-4D8F-4B6A-9C1D-KHINSIDER64}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=khinsider
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..
OutputBaseFilename=khinsider-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
