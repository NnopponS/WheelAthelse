#ifndef MyAppVersion
#define MyAppVersion "1.8.0"
#endif
#define MyAppName "WheelAthlete"
#define MyAppPublisher "WheelAthlete"
#define MyAppExeName "WheelAthlete.exe"
#define WindowsAppRoot "..\.."
#define RepoRoot "..\..\..\.."

[Setup]
AppId={{cee1fcde-63fb-4f77-a747-6a86009db59a}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={userdocs}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableDirPage=no
DisableProgramGroupPage=yes
UsePreviousAppDir=no
PrivilegesRequired=lowest
OutputDir={#WindowsAppRoot}\release
OutputBaseFilename=WheelAthleteSetup-{#MyAppVersion}
SetupIconFile={#RepoRoot}\assets\wheelathlete-logo.ico
UninstallDisplayIcon={app}\Application\{#MyAppExeName}
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no
Uninstallable=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: checkedonce

[Dirs]
Name: "{app}\Application"
Name: "{app}\Model"; Flags: uninsneveruninstall
Name: "{app}\PC Sessions"; Flags: uninsneveruninstall
Name: "{app}\Logs"; Flags: uninsneveruninstall

[Files]
; Keep binaries isolated from research data under Documents\WheelAthlete.
Source: "{#WindowsAppRoot}\release\WheelAthlete\*"; DestDir: "{app}\Application"; Excludes: "Model\*"; Flags: ignoreversion recursesubdirs createallsubdirs
; Seed a user-visible model library. Custom files placed here are never removed as a directory.
Source: "{#WindowsAppRoot}\release\WheelAthlete\Model\*"; DestDir: "{app}\Model"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\Application\{#MyAppExeName}"; WorkingDir: "{app}\Application"; Tasks: desktopicon
Name: "{group}\{#MyAppName}"; Filename: "{app}\Application\{#MyAppExeName}"; WorkingDir: "{app}\Application"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\Application\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent; Check: not IsAutoUpdate
Filename: "{app}\Application\{#MyAppExeName}"; Flags: nowait; Check: IsAutoUpdate

[UninstallDelete]
; Delete only installed application binaries. Preserve Model, PC Sessions, Logs,
; custom models, and all other user research data under Documents\WheelAthlete.
Type: filesandordirs; Name: "{app}\Application"

[Code]
function IsAutoUpdate: Boolean;
var
  I: Integer;
  Value: String;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    Value := Uppercase(ParamStr(I));
    if (Value = '/AUTOUPDATE=1') or (Value = '/AUTOUPDATE') then
    begin
      Result := True;
      Exit;
    end;
  end;
end;
