[Setup]
AppName=ACM Collection Logger
AppVersion=1.0.0
DefaultDirName={autopf}\ACMCollectionLogger
DefaultGroupName=ACM Collection Logger
OutputDir=..\build\windows\installer
OutputBaseFilename=Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
DisableDirPage=yes
DisableProgramGroupPage=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ACM Collection Logger"; Filename: "{app}\collection_logger.exe"
Name: "{autodesktop}\ACM Collection Logger"; Filename: "{app}\collection_logger.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\collection_logger.exe"; Description: "Launch ACM Collection Logger"; Flags: nowait postinstall skipifsilent
