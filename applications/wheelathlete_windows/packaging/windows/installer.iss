#ifndef MyAppVersion
#define MyAppVersion "1.8.2"
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
Source: "{#WindowsAppRoot}\packaging\windows\stop_installed_daemon.ps1"; Flags: dontcopy
; Keep binaries isolated from research data under Documents\WheelAthlete.
Source: "{#WindowsAppRoot}\release\WheelAthlete\*"; DestDir: "{app}\Application"; Excludes: "Model\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#WindowsAppRoot}\packaging\windows\stop_installed_daemon.ps1"; DestDir: "{app}\Application"; Flags: ignoreversion
; Seed a user-visible model library. Existing and seeded files survive uninstall.
Source: "{#WindowsAppRoot}\release\WheelAthlete\Model\*"; DestDir: "{app}\Model"; Flags: ignoreversion onlyifdoesntexist recursesubdirs createallsubdirs uninsneveruninstall

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
function RunDaemonStop(const ScriptPath: String): String;
var
  ExitCode: Integer;
  Parameters: String;
begin
  Result := '';
  if not FileExists(ScriptPath) then
    Exit;
  Parameters := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ScriptPath + '" -InstallRoot "' + ExpandConstant('{app}') + '"';
  if (not Exec('powershell.exe', Parameters, '', SW_HIDE,
      ewWaitUntilTerminated, ExitCode)) or (ExitCode <> 0) then
    Result := 'WheelAthlete could not stop its installed acquisition daemon safely. ' +
      'Close WheelAthlete, wait for any recording to finish, and try again.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  ExtractTemporaryFile('stop_installed_daemon.ps1');
  Result := RunDaemonStop(ExpandConstant('{tmp}\stop_installed_daemon.ps1'));
end;

function InitializeUninstall(): Boolean;
var
  ErrorMessage: String;
begin
  ErrorMessage := RunDaemonStop(
    ExpandConstant('{app}\Application\stop_installed_daemon.ps1'));
  Result := ErrorMessage = '';
  if not Result then
    MsgBox(ErrorMessage, mbError, MB_OK);
end;

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
