#define MyAppName      "Baseline"
#define MyAppVersion   "1.0.0"
#define MyAppChannel   "Stable"
#define MyAppChannelToken "stable"
#define MyAppPublisher "sdmanson8"
#define MyAppExeName   "Baseline.exe"
#define MyAppId        "{{D5A779F1-8936-4E66-A24D-9A4E43A2A4D9}}"
#define MySetupMutex   "Baseline-Setup-D5A779F1-8936-4E66-A24D-9A4E43A2A4D9"
#if MyAppChannelToken == "stable"
#define MySetupBaseFilename "Baseline-" + MyAppVersion + "-setup"
#else
#define MySetupBaseFilename "Baseline-" + MyAppVersion + "-" + MyAppChannelToken + "-setup"
#endif

; MySourceRoot and MyOutputDir are injected by New-InstallerPackage.ps1 at build time
#define MySourceRoot "."
#define MyOutputDir  "."

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
SetupMutex={#MySetupMutex}
AppPublisherURL=https://github.com/sdmanson8/Baseline
AppSupportURL=https://github.com/sdmanson8/Baseline/issues

ShowLanguageDialog=no

; Install mode defaults to Program Files (all users / elevated).
; Portable mode extracts to {localappdata}\Baseline and needs no elevation.
; The scope page lets the user override to current-user (LocalAppData\Programs)
; for machines where they lack admin rights.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline dialog
UsePreviousPrivileges=no

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

OutputDir={#MyOutputDir}
OutputBaseFilename={#MySetupBaseFilename}
SetupIconFile={#MySourceRoot}\Assets\baseline-setup.ico
Uninstallable=IsInstallMode
CreateUninstallRegKey=IsInstallMode
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes

WizardStyle=modern
WizardSizePercent=110
DisableWelcomePage=yes
DisableDirPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes

ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
; Install mode — placed into {app} by the standard installer
Source: "{#MySourceRoot}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
; All other payload files (install mode)
Source: "{#MySourceRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "{#MyAppExeName},.git\*,.github\*"; Check: IsInstallMode
; Portable mode — extracted to the selected portable target
Source: "{#MySourceRoot}\{#MyAppExeName}"; DestDir: "{code:GetPortableTargetDir}"; Flags: ignoreversion; Check: IsPortableMode
Source: "{#MySourceRoot}\*"; DestDir: "{code:GetPortableTargetDir}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "{#MyAppExeName},.git\*,.github\*"; Check: IsPortableMode

[Icons]
Name: "{group}\{#MyAppName}";         Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Check: IsInstallMode and IsStartMenuChecked
Name: "{autodesktop}\{#MyAppName}";   Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Check: IsInstallMode and IsDesktopChecked

[Registry]
; Register in Programs and Features for the active install mode.
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: string; ValueName: "DisplayName";     ValueData: "{#MyAppName}"; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: string; ValueName: "DisplayVersion";  ValueData: "{#MyAppVersion}"; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: string; ValueName: "Publisher";       ValueData: "{#MyAppPublisher}"; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: string; ValueName: "InstallLocation"; ValueData: "{app}"; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: string; ValueName: "DisplayIcon";     ValueData: "{app}\{#MyAppExeName}"; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: string; ValueName: "UninstallString"; ValueData: """{uninstallexe}"""; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: dword;  ValueName: "NoModify";        ValueData: 1; Check: IsInstallMode
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}"; \
  ValueType: dword;  ValueName: "NoRepair";        ValueData: 1; Check: IsInstallMode

[Code]

// ─────────────────────────────────────────────────────────────────────────────
// Locale list — matches Localizations/**/*.json files embedded in Baseline.exe
// Format: "English Name|Native Name|locale-code"
// ─────────────────────────────────────────────────────────────────────────────

const
  LocaleCount = 124;

// ─────────────────────────────────────────────────────────────────────────────
// Global state
// ─────────────────────────────────────────────────────────────────────────────

var
  LocaleEntries: array of String;
  LangVisibleEntries: array of String;

  // Pages
  PageLanguage:   TWizardPage;
  PageMode:       TWizardPage;
  PageScope:      TWizardPage;
  PageLocation:   TWizardPage;
  PageShortcuts:  TWizardPage;
  PageFinish:     TWizardPage;

  // Language page controls
  LangSearchEdit: TNewEdit;
  LangList:       TNewListBox;
  LangNoResults:  TNewStaticText;
  LblLangSearch:  TNewStaticText;
  LblLangDisplay: TNewStaticText;
  LblLangHelp:    TNewStaticText;
  LangVisibleCount: Integer;

  // Mode page controls
  RbInstall:      TNewRadioButton;
  RbPortable:     TNewRadioButton;

  // Install scope controls (install only)
  RbCurrentUser:  TNewRadioButton;
  RbAllUsers:     TNewRadioButton;

  // Location page controls (install)
  DirEdit:        TNewEdit;
  BtnBrowse:      TNewButton;

  // Shortcuts page controls (install)
  CbDesktop:      TNewCheckBox;
  CbStartMenu:    TNewCheckBox;

  // Finish page controls
  CbLaunch:       TNewCheckBox;

  // Translatable labels (updated when language is confirmed)
  LblModeTitle:        TNewStaticText;
  LblModeDesc:         TNewStaticText;
  LblModeAction:       TNewStaticText;
  LblModeInstallDesc:  TNewStaticText;
  LblModePortableDesc: TNewStaticText;
  LblScopeTitle:       TNewStaticText;
  LblScopeDesc:        TNewStaticText;
  LblScopeHeading:     TNewStaticText;
  LblScopeCurrentDesc: TNewStaticText;
  LblScopeAllDesc:     TNewStaticText;
  LblLocTitle:         TNewStaticText;
  LblLocDesc:          TNewStaticText;
  LblLocHeading:       TNewStaticText;
  LblLocNote:          TNewStaticText;
  LblShortTitle:       TNewStaticText;
  LblShortDesc:        TNewStaticText;
  LblShortHeading:     TNewStaticText;
  LblFinishTitle:      TNewStaticText;
  LblFinishDesc:       TNewStaticText;

  // Runtime flags
  GInstallMode:      Boolean;
  GInstallScopeAllUsers: Boolean;
  GDesktop:          Boolean;
  GStartMenu:        Boolean;
  GPortablePath:     String;
  GInstallPath:      String;
  GLocaleCode:       String;   // chosen Baseline locale code e.g. "fr", "zh-Hans"
  GSetupCompleted:   Boolean;  // True only after ssPostInstall succeeds
  GResumeInstallFlow: Boolean;
  GProgrammaticClose: Boolean;
  GUpdateFlow:       Boolean;
  GUpdateRelaunchPath: String;
  GUpdateTargetDir: String;

// ─────────────────────────────────────────────────────────────────────────────
// Check functions referenced in [Files] / [Icons] / [Registry] / [Run]
// ─────────────────────────────────────────────────────────────────────────────

function IsInstallMode: Boolean;
begin
  Result := GInstallMode;
end;

function IsPortableMode: Boolean;
begin
  Result := not GInstallMode;
end;

function GetPortableTargetDir(Param: String): String;
begin
  if GPortablePath <> '' then
    Result := GPortablePath
  else
    Result := ExpandConstant('{localappdata}') + '\Baseline';
end;

function IsDesktopChecked: Boolean;
begin
  Result := GDesktop;
end;

function IsStartMenuChecked: Boolean;
begin
  Result := GStartMenu;
end;

function IsLaunchChecked: Boolean;
begin
  Result := CbLaunch.Checked;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Helper: extract locale fields from an "English Name|Native Name|code" entry
// ─────────────────────────────────────────────────────────────────────────────

function LocaleFirstSeparatorPos(Entry: String): Integer;
var
  Pos: Integer;
begin
  Pos := 1;
  while (Pos <= Length(Entry)) and (Entry[Pos] <> '|') do
    Pos := Pos + 1;
  if Pos <= Length(Entry) then
    Result := Pos
  else
    Result := 0;
end;

function LocaleLastSeparatorPos(Entry: String): Integer;
var
  Pos: Integer;
begin
  Pos := Length(Entry);
  while (Pos > 0) and (Entry[Pos] <> '|') do
    Pos := Pos - 1;
  Result := Pos;
end;

function LocaleCode(Entry: String): String;
var
  SeparatorPos: Integer;
begin
  SeparatorPos := LocaleLastSeparatorPos(Entry);
  if SeparatorPos > 0 then
    Result := Copy(Entry, SeparatorPos + 1, Length(Entry) - SeparatorPos)
  else
    Result := Entry;
end;

function LocaleEnglishName(Entry: String): String;
var
  SeparatorPos: Integer;
begin
  SeparatorPos := LocaleFirstSeparatorPos(Entry);
  if SeparatorPos > 0 then
    Result := Copy(Entry, 1, SeparatorPos - 1)
  else
    Result := Entry;
end;

function LocaleNativeName(Entry: String): String;
var
  FirstSeparatorPos, LastSeparatorPos: Integer;
begin
  FirstSeparatorPos := LocaleFirstSeparatorPos(Entry);
  LastSeparatorPos  := LocaleLastSeparatorPos(Entry);
  if (FirstSeparatorPos > 0) and (LastSeparatorPos > FirstSeparatorPos) then
    Result := Copy(Entry, FirstSeparatorPos + 1, LastSeparatorPos - FirstSeparatorPos - 1)
  else if FirstSeparatorPos > 0 then
    Result := Copy(Entry, FirstSeparatorPos + 1, Length(Entry) - FirstSeparatorPos)
  else
    Result := '';
end;

function LocaleDisplayName(Entry: String): String;
var
  NativeName: String;
begin
  NativeName := LocaleNativeName(Entry);
  if NativeName <> '' then
    Result := LocaleEnglishName(Entry) + ' | ' + NativeName
  else
    Result := LocaleEnglishName(Entry);
end;

// ─────────────────────────────────────────────────────────────────────────────
// Setup-page translations
// Each entry: "locale-code|key=value" — key matches the constant used below.
// Only installer-specific strings are needed here; Baseline's own UI strings
// are loaded from the JSON files embedded in Baseline.exe at runtime.
// ─────────────────────────────────────────────────────────────────────────────

function GetSetupString(Key: String): String;
// Looks up a translated installer string for the active locale (GLocaleCode).
// Falls back to the bare language code (strips region suffix), then English.
// Inno Setup Pascal does not support nested types, procedures, or records inside
// functions, so we use a flat if/else chain keyed on "locale|key".
var
  Lang, LK: String;
begin
  Lang := GLocaleCode;
  // Strip region suffix: "zh-Hans" → "zh", "fr-CA" → "fr", "pt-BR" → "pt", etc.
  if Pos('-', Lang) > 0 then
    Lang := Copy(Lang, 1, Pos('-', Lang) - 1);

  // Match on the base language code only
  LK := Lang + '|' + Key;

  // ── German (de) ─────────────────────────────────────────────────────────────
  if      LK = 'de|ModePage.Title'        then begin Result := 'Installationstyp'; Exit; end
  else if LK = 'de|ModePage.Desc'         then begin Result := 'Legen Sie fest, ob Sie Baseline installieren oder portabel nutzen möchten.'; Exit; end
  else if LK = 'de|ModePage.Action'       then begin Result := 'Aktion auswählen:'; Exit; end
  else if LK = 'de|RbInstall.Caption'     then begin Result := 'Für diesen PC installieren'; Exit; end
  else if LK = 'de|RbInstall.Desc'        then begin Result := 'Baseline wird installiert und in Programme und Features registriert.'; Exit; end
  else if LK = 'de|RbPortable.Caption'    then begin Result := 'Portabel'; Exit; end
  else if LK = 'de|RbPortable.Desc'       then begin Result := 'Portable Version ausführen (keine Installation erforderlich).'; Exit; end
  else if LK = 'de|ScopePage.Title'       then begin Result := 'Installationsbereich'; Exit; end
  else if LK = 'de|ScopePage.Desc'        then begin Result := 'Wählen Sie, wer Baseline verwenden kann.'; Exit; end
  else if LK = 'de|ScopePage.Heading'     then begin Result := 'Installationsbereich auswählen:'; Exit; end
  else if LK = 'de|RbCurrentUser.Caption' then begin Result := 'Nur für mich installieren (empfohlen)'; Exit; end
  else if LK = 'de|RbCurrentUser.Desc'    then begin Result := 'Baseline wird nur für das aktuelle Windows-Konto installiert.'; Exit; end
  else if LK = 'de|RbAllUsers.Caption'    then begin Result := 'Für alle Benutzer installieren'; Exit; end
  else if LK = 'de|RbAllUsers.Desc'       then begin Result := 'Installiert Baseline für alle Konten auf diesem PC und startet Setup mit Administratorrechten neu, falls erforderlich.'; Exit; end
  else if LK = 'de|LocPage.Title'         then begin Result := 'Installationsort'; Exit; end
  else if LK = 'de|LocPage.Desc'          then begin Result := 'Wählen Sie, wo Baseline installiert werden soll.'; Exit; end
  else if LK = 'de|LocPage.Heading'       then begin Result := 'Installationsort:'; Exit; end
  else if LK = 'de|BtnBrowse.Caption'     then begin Result := 'Durchsuchen...'; Exit; end
  else if LK = 'de|LocPage.Note'          then begin Result := 'Baseline wird in Windows registriert und kann über die Einstellungen deinstalliert werden.'; Exit; end
  else if LK = 'de|ShortPage.Title'       then begin Result := 'Verknüpfungen'; Exit; end
  else if LK = 'de|ShortPage.Desc'        then begin Result := 'Wählen Sie, welche Verknüpfungen für Baseline erstellt werden sollen.'; Exit; end
  else if LK = 'de|ShortPage.Heading'     then begin Result := 'Diese Verknüpfungen erstellen:'; Exit; end
  else if LK = 'de|CbDesktop.Caption'     then begin Result := 'Desktop-Verknüpfung'; Exit; end
  else if LK = 'de|CbStartMenu.Caption'   then begin Result := 'Startmenü-Verknüpfung'; Exit; end
  else if LK = 'de|FinishPage.Title'      then begin Result := 'Setup abgeschlossen'; Exit; end
  else if LK = 'de|FinishPage.Desc'       then begin Result := 'Baseline ist einsatzbereit.'; Exit; end
  else if LK = 'de|CbLaunch.Caption'      then begin Result := 'Baseline jetzt starten'; Exit; end
  else if LK = 'de|Btn.Next'              then begin Result := 'Weiter >'; Exit; end
  else if LK = 'de|Btn.Install'           then begin Result := 'Installieren'; Exit; end
  else if LK = 'de|Btn.Extract'           then begin Result := 'Extrahieren'; Exit; end
  else if LK = 'de|Btn.Finish'            then begin Result := 'Fertig'; Exit; end

  // ── French (fr) ─────────────────────────────────────────────────────────────
  else if LK = 'fr|ModePage.Title'        then begin Result := 'Type d''installation'; Exit; end
  else if LK = 'fr|ModePage.Desc'         then begin Result := 'Choisissez si vous souhaitez installer Baseline ou l''utiliser en mode portable.'; Exit; end
  else if LK = 'fr|ModePage.Action'       then begin Result := 'Sélectionner une action :'; Exit; end
  else if LK = 'fr|RbInstall.Caption'     then begin Result := 'Installer sur ce PC'; Exit; end
  else if LK = 'fr|RbInstall.Desc'        then begin Result := 'Baseline sera installé et enregistré dans Programmes et fonctionnalités.'; Exit; end
  else if LK = 'fr|RbPortable.Caption'    then begin Result := 'Portable'; Exit; end
  else if LK = 'fr|RbPortable.Desc'       then begin Result := 'Exécuter la version portable (aucune installation requise).'; Exit; end
  else if LK = 'fr|ScopePage.Title'       then begin Result := 'Portée de l''installation'; Exit; end
  else if LK = 'fr|ScopePage.Desc'        then begin Result := 'Choisissez qui peut utiliser Baseline.'; Exit; end
  else if LK = 'fr|ScopePage.Heading'     then begin Result := 'Sélectionner la portée :'; Exit; end
  else if LK = 'fr|RbCurrentUser.Caption' then begin Result := 'Installer pour moi uniquement (recommandé)'; Exit; end
  else if LK = 'fr|RbCurrentUser.Desc'    then begin Result := 'Installe Baseline uniquement pour le compte Windows actuel.'; Exit; end
  else if LK = 'fr|RbAllUsers.Caption'    then begin Result := 'Installer pour tous les utilisateurs'; Exit; end
  else if LK = 'fr|RbAllUsers.Desc'       then begin Result := 'Installe Baseline pour tous les comptes sur ce PC et redémarre le programme d''installation avec des privilèges administrateur si nécessaire.'; Exit; end
  else if LK = 'fr|LocPage.Title'         then begin Result := 'Emplacement d''installation'; Exit; end
  else if LK = 'fr|LocPage.Desc'          then begin Result := 'Choisissez où Baseline doit être installé.'; Exit; end
  else if LK = 'fr|LocPage.Heading'       then begin Result := 'Emplacement :'; Exit; end
  else if LK = 'fr|BtnBrowse.Caption'     then begin Result := 'Parcourir...'; Exit; end
  else if LK = 'fr|LocPage.Note'          then begin Result := 'Baseline sera enregistré dans Windows et peut être désinstallé depuis les Paramètres.'; Exit; end
  else if LK = 'fr|ShortPage.Title'       then begin Result := 'Raccourcis'; Exit; end
  else if LK = 'fr|ShortPage.Desc'        then begin Result := 'Choisissez les raccourcis à créer pour Baseline.'; Exit; end
  else if LK = 'fr|ShortPage.Heading'     then begin Result := 'Créer ces raccourcis :'; Exit; end
  else if LK = 'fr|CbDesktop.Caption'     then begin Result := 'Raccourci sur le bureau'; Exit; end
  else if LK = 'fr|CbStartMenu.Caption'   then begin Result := 'Raccourci dans le menu Démarrer'; Exit; end
  else if LK = 'fr|FinishPage.Title'      then begin Result := 'Installation terminée'; Exit; end
  else if LK = 'fr|FinishPage.Desc'       then begin Result := 'Baseline est prêt à l''emploi.'; Exit; end
  else if LK = 'fr|CbLaunch.Caption'      then begin Result := 'Lancer Baseline maintenant'; Exit; end
  else if LK = 'fr|Btn.Next'              then begin Result := 'Suivant >'; Exit; end
  else if LK = 'fr|Btn.Install'           then begin Result := 'Installer'; Exit; end
  else if LK = 'fr|Btn.Extract'           then begin Result := 'Extraire'; Exit; end
  else if LK = 'fr|Btn.Finish'            then begin Result := 'Terminer'; Exit; end

  // ── Spanish (es) ────────────────────────────────────────────────────────────
  else if LK = 'es|ModePage.Title'        then begin Result := 'Tipo de instalación'; Exit; end
  else if LK = 'es|ModePage.Desc'         then begin Result := 'Especifique si desea instalar Baseline o ejecutarlo como aplicación portátil.'; Exit; end
  else if LK = 'es|ModePage.Action'       then begin Result := 'Seleccionar acción:'; Exit; end
  else if LK = 'es|RbInstall.Caption'     then begin Result := 'Instalar en este equipo'; Exit; end
  else if LK = 'es|RbInstall.Desc'        then begin Result := 'Baseline se instalará y registrará en Programas y características.'; Exit; end
  else if LK = 'es|RbPortable.Caption'    then begin Result := 'Portátil'; Exit; end
  else if LK = 'es|RbPortable.Desc'       then begin Result := 'Ejecutar versión portátil (sin instalación).'; Exit; end
  else if LK = 'es|ScopePage.Title'       then begin Result := 'Ámbito de instalación'; Exit; end
  else if LK = 'es|ScopePage.Desc'        then begin Result := 'Elija quién puede usar Baseline.'; Exit; end
  else if LK = 'es|ScopePage.Heading'     then begin Result := 'Seleccionar ámbito:'; Exit; end
  else if LK = 'es|RbCurrentUser.Caption' then begin Result := 'Instalar solo para mí (recomendado)'; Exit; end
  else if LK = 'es|RbCurrentUser.Desc'    then begin Result := 'Instala Baseline solo para la cuenta de Windows actual.'; Exit; end
  else if LK = 'es|RbAllUsers.Caption'    then begin Result := 'Instalar para todos los usuarios'; Exit; end
  else if LK = 'es|RbAllUsers.Desc'       then begin Result := 'Instala Baseline para todas las cuentas en este equipo y reinicia la instalación con privilegios de administrador si es necesario.'; Exit; end
  else if LK = 'es|LocPage.Title'         then begin Result := 'Ubicación de instalación'; Exit; end
  else if LK = 'es|LocPage.Desc'          then begin Result := 'Elija dónde instalar Baseline.'; Exit; end
  else if LK = 'es|LocPage.Heading'       then begin Result := 'Ubicación de instalación:'; Exit; end
  else if LK = 'es|BtnBrowse.Caption'     then begin Result := 'Examinar...'; Exit; end
  else if LK = 'es|LocPage.Note'          then begin Result := 'Baseline se registrará en Windows y podrá desinstalarse desde Configuración.'; Exit; end
  else if LK = 'es|ShortPage.Title'       then begin Result := 'Accesos directos'; Exit; end
  else if LK = 'es|ShortPage.Desc'        then begin Result := 'Elija qué accesos directos crear para Baseline.'; Exit; end
  else if LK = 'es|ShortPage.Heading'     then begin Result := 'Crear estos accesos directos:'; Exit; end
  else if LK = 'es|CbDesktop.Caption'     then begin Result := 'Acceso directo en el escritorio'; Exit; end
  else if LK = 'es|CbStartMenu.Caption'   then begin Result := 'Acceso directo en el menú Inicio'; Exit; end
  else if LK = 'es|FinishPage.Title'      then begin Result := 'Instalación completada'; Exit; end
  else if LK = 'es|FinishPage.Desc'       then begin Result := 'Baseline está listo para usar.'; Exit; end
  else if LK = 'es|CbLaunch.Caption'      then begin Result := 'Iniciar Baseline ahora'; Exit; end
  else if LK = 'es|Btn.Next'              then begin Result := 'Siguiente >'; Exit; end
  else if LK = 'es|Btn.Install'           then begin Result := 'Instalar'; Exit; end
  else if LK = 'es|Btn.Extract'           then begin Result := 'Extraer'; Exit; end
  else if LK = 'es|Btn.Finish'            then begin Result := 'Finalizar'; Exit; end

  // ── Portuguese (pt) ─────────────────────────────────────────────────────────
  else if LK = 'pt|ModePage.Title'        then begin Result := 'Tipo de instalação'; Exit; end
  else if LK = 'pt|ModePage.Desc'         then begin Result := 'Especifique se deseja instalar o Baseline ou executá-lo como aplicativo portátil.'; Exit; end
  else if LK = 'pt|ModePage.Action'       then begin Result := 'Selecionar ação:'; Exit; end
  else if LK = 'pt|RbInstall.Caption'     then begin Result := 'Instalar neste PC'; Exit; end
  else if LK = 'pt|RbInstall.Desc'        then begin Result := 'O Baseline será instalado e registrado em Programas e Recursos.'; Exit; end
  else if LK = 'pt|RbPortable.Caption'    then begin Result := 'Portátil'; Exit; end
  else if LK = 'pt|RbPortable.Desc'       then begin Result := 'Executar versão portátil (sem instalação necessária).'; Exit; end
  else if LK = 'pt|ScopePage.Title'       then begin Result := 'Escopo de instalação'; Exit; end
  else if LK = 'pt|ScopePage.Desc'        then begin Result := 'Escolha quem pode usar o Baseline.'; Exit; end
  else if LK = 'pt|ScopePage.Heading'     then begin Result := 'Selecionar escopo:'; Exit; end
  else if LK = 'pt|RbCurrentUser.Caption' then begin Result := 'Instalar apenas para mim (recomendado)'; Exit; end
  else if LK = 'pt|RbCurrentUser.Desc'    then begin Result := 'Instala o Baseline apenas para a conta atual do Windows.'; Exit; end
  else if LK = 'pt|RbAllUsers.Caption'    then begin Result := 'Instalar para todos os usuários'; Exit; end
  else if LK = 'pt|RbAllUsers.Desc'       then begin Result := 'Instala o Baseline para todas as contas neste PC e reinicia a Instalação com privilégios de administrador se necessário.'; Exit; end
  else if LK = 'pt|LocPage.Title'         then begin Result := 'Local de instalação'; Exit; end
  else if LK = 'pt|LocPage.Desc'          then begin Result := 'Escolha onde o Baseline deve ser instalado.'; Exit; end
  else if LK = 'pt|LocPage.Heading'       then begin Result := 'Local de instalação:'; Exit; end
  else if LK = 'pt|BtnBrowse.Caption'     then begin Result := 'Procurar...'; Exit; end
  else if LK = 'pt|LocPage.Note'          then begin Result := 'O Baseline será registrado no Windows e pode ser desinstalado em Configurações.'; Exit; end
  else if LK = 'pt|ShortPage.Title'       then begin Result := 'Atalhos'; Exit; end
  else if LK = 'pt|ShortPage.Desc'        then begin Result := 'Escolha quais atalhos criar para o Baseline.'; Exit; end
  else if LK = 'pt|ShortPage.Heading'     then begin Result := 'Criar estes atalhos:'; Exit; end
  else if LK = 'pt|CbDesktop.Caption'     then begin Result := 'Atalho na área de trabalho'; Exit; end
  else if LK = 'pt|CbStartMenu.Caption'   then begin Result := 'Atalho no menu Iniciar'; Exit; end
  else if LK = 'pt|FinishPage.Title'      then begin Result := 'Instalação concluída'; Exit; end
  else if LK = 'pt|FinishPage.Desc'       then begin Result := 'O Baseline está pronto para uso.'; Exit; end
  else if LK = 'pt|CbLaunch.Caption'      then begin Result := 'Iniciar o Baseline agora'; Exit; end
  else if LK = 'pt|Btn.Next'              then begin Result := 'Próximo >'; Exit; end
  else if LK = 'pt|Btn.Install'           then begin Result := 'Instalar'; Exit; end
  else if LK = 'pt|Btn.Extract'           then begin Result := 'Extrair'; Exit; end
  else if LK = 'pt|Btn.Finish'            then begin Result := 'Concluir'; Exit; end

  // ── Italian (it) ────────────────────────────────────────────────────────────
  else if LK = 'it|ModePage.Title'        then begin Result := 'Tipo di installazione'; Exit; end
  else if LK = 'it|ModePage.Desc'         then begin Result := 'Specifica se vuoi installare Baseline o eseguirlo come app portatile.'; Exit; end
  else if LK = 'it|ModePage.Action'       then begin Result := 'Seleziona azione:'; Exit; end
  else if LK = 'it|RbInstall.Caption'     then begin Result := 'Installa su questo PC'; Exit; end
  else if LK = 'it|RbInstall.Desc'        then begin Result := 'Baseline verrà installato e registrato in Programmi e funzionalità.'; Exit; end
  else if LK = 'it|RbPortable.Caption'    then begin Result := 'Portatile'; Exit; end
  else if LK = 'it|RbPortable.Desc'       then begin Result := 'Esegui versione portatile (nessuna installazione richiesta).'; Exit; end
  else if LK = 'it|ScopePage.Title'       then begin Result := 'Ambito di installazione'; Exit; end
  else if LK = 'it|ScopePage.Desc'        then begin Result := 'Scegli chi può usare Baseline.'; Exit; end
  else if LK = 'it|ScopePage.Heading'     then begin Result := 'Seleziona ambito:'; Exit; end
  else if LK = 'it|RbCurrentUser.Caption' then begin Result := 'Installa solo per me (consigliato)'; Exit; end
  else if LK = 'it|RbCurrentUser.Desc'    then begin Result := 'Installa Baseline solo per l''account Windows corrente.'; Exit; end
  else if LK = 'it|RbAllUsers.Caption'    then begin Result := 'Installa per tutti gli utenti'; Exit; end
  else if LK = 'it|RbAllUsers.Desc'       then begin Result := 'Installa Baseline per tutti gli account su questo PC e riavvia il programma di installazione con privilegi di amministratore se necessario.'; Exit; end
  else if LK = 'it|LocPage.Title'         then begin Result := 'Percorso di installazione'; Exit; end
  else if LK = 'it|LocPage.Desc'          then begin Result := 'Scegli dove installare Baseline.'; Exit; end
  else if LK = 'it|LocPage.Heading'       then begin Result := 'Percorso di installazione:'; Exit; end
  else if LK = 'it|BtnBrowse.Caption'     then begin Result := 'Sfoglia...'; Exit; end
  else if LK = 'it|LocPage.Note'          then begin Result := 'Baseline verrà registrato in Windows e può essere disinstallato dalle Impostazioni.'; Exit; end
  else if LK = 'it|ShortPage.Title'       then begin Result := 'Collegamenti'; Exit; end
  else if LK = 'it|ShortPage.Desc'        then begin Result := 'Scegli quali collegamenti creare per Baseline.'; Exit; end
  else if LK = 'it|ShortPage.Heading'     then begin Result := 'Crea questi collegamenti:'; Exit; end
  else if LK = 'it|CbDesktop.Caption'     then begin Result := 'Collegamento sul desktop'; Exit; end
  else if LK = 'it|CbStartMenu.Caption'   then begin Result := 'Collegamento nel menu Start'; Exit; end
  else if LK = 'it|FinishPage.Title'      then begin Result := 'Installazione completata'; Exit; end
  else if LK = 'it|FinishPage.Desc'       then begin Result := 'Baseline è pronto all''uso.'; Exit; end
  else if LK = 'it|CbLaunch.Caption'      then begin Result := 'Avvia Baseline ora'; Exit; end
  else if LK = 'it|Btn.Next'              then begin Result := 'Avanti >'; Exit; end
  else if LK = 'it|Btn.Install'           then begin Result := 'Installa'; Exit; end
  else if LK = 'it|Btn.Extract'           then begin Result := 'Estrai'; Exit; end
  else if LK = 'it|Btn.Finish'            then begin Result := 'Fine'; Exit; end

  // ── Dutch (nl) ──────────────────────────────────────────────────────────────
  else if LK = 'nl|ModePage.Title'        then begin Result := 'Installatietype'; Exit; end
  else if LK = 'nl|ModePage.Desc'         then begin Result := 'Geef aan of u Baseline wilt installeren of als draagbare app wilt uitvoeren.'; Exit; end
  else if LK = 'nl|ModePage.Action'       then begin Result := 'Actie selecteren:'; Exit; end
  else if LK = 'nl|RbInstall.Caption'     then begin Result := 'Installeren op deze pc'; Exit; end
  else if LK = 'nl|RbInstall.Desc'        then begin Result := 'Baseline wordt geïnstalleerd en geregistreerd in Programma''s en onderdelen.'; Exit; end
  else if LK = 'nl|RbPortable.Caption'    then begin Result := 'Draagbaar'; Exit; end
  else if LK = 'nl|RbPortable.Desc'       then begin Result := 'Draagbare versie uitvoeren (geen installatie vereist).'; Exit; end
  else if LK = 'nl|ScopePage.Title'       then begin Result := 'Installatiebereik'; Exit; end
  else if LK = 'nl|ScopePage.Desc'        then begin Result := 'Kies wie Baseline mag gebruiken.'; Exit; end
  else if LK = 'nl|ScopePage.Heading'     then begin Result := 'Installatiebereik selecteren:'; Exit; end
  else if LK = 'nl|RbCurrentUser.Caption' then begin Result := 'Alleen voor mij installeren (aanbevolen)'; Exit; end
  else if LK = 'nl|RbCurrentUser.Desc'    then begin Result := 'Installeert Baseline alleen voor het huidige Windows-account.'; Exit; end
  else if LK = 'nl|RbAllUsers.Caption'    then begin Result := 'Installeren voor alle gebruikers'; Exit; end
  else if LK = 'nl|RbAllUsers.Desc'       then begin Result := 'Installeert Baseline voor alle accounts op deze pc en herstart Setup met beheerdersrechten indien nodig.'; Exit; end
  else if LK = 'nl|LocPage.Title'         then begin Result := 'Installatielocatie'; Exit; end
  else if LK = 'nl|LocPage.Desc'          then begin Result := 'Kies waar Baseline moet worden geïnstalleerd.'; Exit; end
  else if LK = 'nl|LocPage.Heading'       then begin Result := 'Installatielocatie:'; Exit; end
  else if LK = 'nl|BtnBrowse.Caption'     then begin Result := 'Bladeren...'; Exit; end
  else if LK = 'nl|LocPage.Note'          then begin Result := 'Baseline wordt geregistreerd bij Windows en kan worden verwijderd via Instellingen.'; Exit; end
  else if LK = 'nl|ShortPage.Title'       then begin Result := 'Snelkoppelingen'; Exit; end
  else if LK = 'nl|ShortPage.Desc'        then begin Result := 'Kies welke snelkoppelingen voor Baseline worden gemaakt.'; Exit; end
  else if LK = 'nl|ShortPage.Heading'     then begin Result := 'Deze snelkoppelingen maken:'; Exit; end
  else if LK = 'nl|CbDesktop.Caption'     then begin Result := 'Bureaubladsnelkoppeling'; Exit; end
  else if LK = 'nl|CbStartMenu.Caption'   then begin Result := 'Snelkoppeling in Startmenu'; Exit; end
  else if LK = 'nl|FinishPage.Title'      then begin Result := 'Setup voltooid'; Exit; end
  else if LK = 'nl|FinishPage.Desc'       then begin Result := 'Baseline is klaar voor gebruik.'; Exit; end
  else if LK = 'nl|CbLaunch.Caption'      then begin Result := 'Baseline nu starten'; Exit; end
  else if LK = 'nl|Btn.Next'              then begin Result := 'Volgende >'; Exit; end
  else if LK = 'nl|Btn.Install'           then begin Result := 'Installeren'; Exit; end
  else if LK = 'nl|Btn.Extract'           then begin Result := 'Uitpakken'; Exit; end
  else if LK = 'nl|Btn.Finish'            then begin Result := 'Voltooien'; Exit; end

  // ── Russian (ru) ────────────────────────────────────────────────────────────
  else if LK = 'ru|ModePage.Title'        then begin Result := 'Тип установки'; Exit; end
  else if LK = 'ru|ModePage.Desc'         then begin Result := 'Укажите, хотите ли вы установить Baseline или использовать его как портативное приложение.'; Exit; end
  else if LK = 'ru|ModePage.Action'       then begin Result := 'Выберите действие:'; Exit; end
  else if LK = 'ru|RbInstall.Caption'     then begin Result := 'Установить на этот компьютер'; Exit; end
  else if LK = 'ru|RbInstall.Desc'        then begin Result := 'Baseline будет установлен и зарегистрирован в разделе «Программы и компоненты».'; Exit; end
  else if LK = 'ru|RbPortable.Caption'    then begin Result := 'Портативный'; Exit; end
  else if LK = 'ru|RbPortable.Desc'       then begin Result := 'Запустить портативную версию (установка не требуется).'; Exit; end
  else if LK = 'ru|ScopePage.Title'       then begin Result := 'Область установки'; Exit; end
  else if LK = 'ru|ScopePage.Desc'        then begin Result := 'Выберите, кто может использовать Baseline.'; Exit; end
  else if LK = 'ru|ScopePage.Heading'     then begin Result := 'Выберите область установки:'; Exit; end
  else if LK = 'ru|RbCurrentUser.Caption' then begin Result := 'Установить только для меня (рекомендуется)'; Exit; end
  else if LK = 'ru|RbCurrentUser.Desc'    then begin Result := 'Устанавливает Baseline только для текущей учётной записи Windows.'; Exit; end
  else if LK = 'ru|RbAllUsers.Caption'    then begin Result := 'Установить для всех пользователей'; Exit; end
  else if LK = 'ru|RbAllUsers.Desc'       then begin Result := 'Устанавливает Baseline для всех учётных записей на этом компьютере и при необходимости перезапускает установку с правами администратора.'; Exit; end
  else if LK = 'ru|LocPage.Title'         then begin Result := 'Папка установки'; Exit; end
  else if LK = 'ru|LocPage.Desc'          then begin Result := 'Выберите, куда установить Baseline.'; Exit; end
  else if LK = 'ru|LocPage.Heading'       then begin Result := 'Папка установки:'; Exit; end
  else if LK = 'ru|BtnBrowse.Caption'     then begin Result := 'Обзор...'; Exit; end
  else if LK = 'ru|LocPage.Note'          then begin Result := 'Baseline будет зарегистрирован в Windows и может быть удалён через «Параметры».'; Exit; end
  else if LK = 'ru|ShortPage.Title'       then begin Result := 'Ярлыки'; Exit; end
  else if LK = 'ru|ShortPage.Desc'        then begin Result := 'Выберите, какие ярлыки создать для Baseline.'; Exit; end
  else if LK = 'ru|ShortPage.Heading'     then begin Result := 'Создать следующие ярлыки:'; Exit; end
  else if LK = 'ru|CbDesktop.Caption'     then begin Result := 'Ярлык на рабочем столе'; Exit; end
  else if LK = 'ru|CbStartMenu.Caption'   then begin Result := 'Ярлык в меню «Пуск»'; Exit; end
  else if LK = 'ru|FinishPage.Title'      then begin Result := 'Установка завершена'; Exit; end
  else if LK = 'ru|FinishPage.Desc'       then begin Result := 'Baseline готов к использованию.'; Exit; end
  else if LK = 'ru|CbLaunch.Caption'      then begin Result := 'Запустить Baseline сейчас'; Exit; end
  else if LK = 'ru|Btn.Next'              then begin Result := 'Далее >'; Exit; end
  else if LK = 'ru|Btn.Install'           then begin Result := 'Установить'; Exit; end
  else if LK = 'ru|Btn.Extract'           then begin Result := 'Извлечь'; Exit; end
  else if LK = 'ru|Btn.Finish'            then begin Result := 'Готово'; Exit; end

  // ── Japanese (ja) ───────────────────────────────────────────────────────────
  else if LK = 'ja|ModePage.Title'        then begin Result := 'インストールの種類'; Exit; end
  else if LK = 'ja|ModePage.Desc'         then begin Result := 'Baseline をインストールするか、ポータブルアプリとして実行するかを選択してください。'; Exit; end
  else if LK = 'ja|ModePage.Action'       then begin Result := 'アクションを選択:'; Exit; end
  else if LK = 'ja|RbInstall.Caption'     then begin Result := 'この PC にインストール'; Exit; end
  else if LK = 'ja|RbInstall.Desc'        then begin Result := 'Baseline がインストールされ、プログラムと機能に登録されます。'; Exit; end
  else if LK = 'ja|RbPortable.Caption'    then begin Result := 'ポータブル'; Exit; end
  else if LK = 'ja|RbPortable.Desc'       then begin Result := 'ポータブル版を実行します（インストール不要）。'; Exit; end
  else if LK = 'ja|ScopePage.Title'       then begin Result := 'インストール範囲'; Exit; end
  else if LK = 'ja|ScopePage.Desc'        then begin Result := 'Baseline を使用できるユーザーを選択してください。'; Exit; end
  else if LK = 'ja|ScopePage.Heading'     then begin Result := 'インストール範囲を選択:'; Exit; end
  else if LK = 'ja|RbCurrentUser.Caption' then begin Result := '自分のみにインストール（推奨）'; Exit; end
  else if LK = 'ja|RbCurrentUser.Desc'    then begin Result := '現在の Windows アカウントのみに Baseline をインストールします。'; Exit; end
  else if LK = 'ja|RbAllUsers.Caption'    then begin Result := 'すべてのユーザーにインストール'; Exit; end
  else if LK = 'ja|RbAllUsers.Desc'       then begin Result := 'この PC のすべてのアカウントに Baseline をインストールし、必要に応じて管理者権限でセットアップを再起動します。'; Exit; end
  else if LK = 'ja|LocPage.Title'         then begin Result := 'インストール場所'; Exit; end
  else if LK = 'ja|LocPage.Desc'          then begin Result := 'Baseline のインストール先を選択してください。'; Exit; end
  else if LK = 'ja|LocPage.Heading'       then begin Result := 'インストール場所:'; Exit; end
  else if LK = 'ja|BtnBrowse.Caption'     then begin Result := '参照...'; Exit; end
  else if LK = 'ja|LocPage.Note'          then begin Result := 'Baseline は Windows に登録され、設定からアンインストールできます。'; Exit; end
  else if LK = 'ja|ShortPage.Title'       then begin Result := 'ショートカット'; Exit; end
  else if LK = 'ja|ShortPage.Desc'        then begin Result := 'Baseline 用に作成するショートカットを選択してください。'; Exit; end
  else if LK = 'ja|ShortPage.Heading'     then begin Result := '作成するショートカット:'; Exit; end
  else if LK = 'ja|CbDesktop.Caption'     then begin Result := 'デスクトップショートカット'; Exit; end
  else if LK = 'ja|CbStartMenu.Caption'   then begin Result := 'スタートメニューショートカット'; Exit; end
  else if LK = 'ja|FinishPage.Title'      then begin Result := 'セットアップ完了'; Exit; end
  else if LK = 'ja|FinishPage.Desc'       then begin Result := 'Baseline は使用可能な状態になりました。'; Exit; end
  else if LK = 'ja|CbLaunch.Caption'      then begin Result := '今すぐ Baseline を起動'; Exit; end
  else if LK = 'ja|Btn.Next'              then begin Result := '次へ >'; Exit; end
  else if LK = 'ja|Btn.Install'           then begin Result := 'インストール'; Exit; end
  else if LK = 'ja|Btn.Extract'           then begin Result := '展開'; Exit; end
  else if LK = 'ja|Btn.Finish'            then begin Result := '完了'; Exit; end

  // ── Korean (ko) ─────────────────────────────────────────────────────────────
  else if LK = 'ko|ModePage.Title'        then begin Result := '설치 유형'; Exit; end
  else if LK = 'ko|ModePage.Desc'         then begin Result := 'Baseline을 설치할지 또는 포터블 앱으로 실행할지 선택하세요.'; Exit; end
  else if LK = 'ko|ModePage.Action'       then begin Result := '작업 선택:'; Exit; end
  else if LK = 'ko|RbInstall.Caption'     then begin Result := '이 PC에 설치'; Exit; end
  else if LK = 'ko|RbInstall.Desc'        then begin Result := 'Baseline이 설치되고 프로그램 및 기능에 등록됩니다.'; Exit; end
  else if LK = 'ko|RbPortable.Caption'    then begin Result := '포터블'; Exit; end
  else if LK = 'ko|RbPortable.Desc'       then begin Result := '포터블 버전 실행 (설치 불필요).'; Exit; end
  else if LK = 'ko|ScopePage.Title'       then begin Result := '설치 범위'; Exit; end
  else if LK = 'ko|ScopePage.Desc'        then begin Result := 'Baseline을 사용할 수 있는 사용자를 선택하세요.'; Exit; end
  else if LK = 'ko|ScopePage.Heading'     then begin Result := '설치 범위 선택:'; Exit; end
  else if LK = 'ko|RbCurrentUser.Caption' then begin Result := '나만 설치 (권장)'; Exit; end
  else if LK = 'ko|RbCurrentUser.Desc'    then begin Result := '현재 Windows 계정에만 Baseline을 설치합니다.'; Exit; end
  else if LK = 'ko|RbAllUsers.Caption'    then begin Result := '모든 사용자에게 설치'; Exit; end
  else if LK = 'ko|RbAllUsers.Desc'       then begin Result := '이 PC의 모든 계정에 Baseline을 설치하고 필요한 경우 관리자 권한으로 설치를 다시 시작합니다.'; Exit; end
  else if LK = 'ko|LocPage.Title'         then begin Result := '설치 위치'; Exit; end
  else if LK = 'ko|LocPage.Desc'          then begin Result := 'Baseline을 설치할 위치를 선택하세요.'; Exit; end
  else if LK = 'ko|LocPage.Heading'       then begin Result := '설치 위치:'; Exit; end
  else if LK = 'ko|BtnBrowse.Caption'     then begin Result := '찾아보기...'; Exit; end
  else if LK = 'ko|LocPage.Note'          then begin Result := 'Baseline은 Windows에 등록되며 설정에서 제거할 수 있습니다.'; Exit; end
  else if LK = 'ko|ShortPage.Title'       then begin Result := '바로 가기'; Exit; end
  else if LK = 'ko|ShortPage.Desc'        then begin Result := 'Baseline에 대해 만들 바로 가기를 선택하세요.'; Exit; end
  else if LK = 'ko|ShortPage.Heading'     then begin Result := '이 바로 가기 만들기:'; Exit; end
  else if LK = 'ko|CbDesktop.Caption'     then begin Result := '바탕 화면 바로 가기'; Exit; end
  else if LK = 'ko|CbStartMenu.Caption'   then begin Result := '시작 메뉴 바로 가기'; Exit; end
  else if LK = 'ko|FinishPage.Title'      then begin Result := '설치 완료'; Exit; end
  else if LK = 'ko|FinishPage.Desc'       then begin Result := 'Baseline을 사용할 준비가 되었습니다.'; Exit; end
  else if LK = 'ko|CbLaunch.Caption'      then begin Result := '지금 Baseline 시작'; Exit; end
  else if LK = 'ko|Btn.Next'              then begin Result := '다음 >'; Exit; end
  else if LK = 'ko|Btn.Install'           then begin Result := '설치'; Exit; end
  else if LK = 'ko|Btn.Extract'           then begin Result := '압축 해제'; Exit; end
  else if LK = 'ko|Btn.Finish'            then begin Result := '완료'; Exit; end

  // ── Chinese Simplified (zh-Hans → normalised to zh) ─────────────────────────
  else if LK = 'zh|ModePage.Title'        then begin Result := '安装类型'; Exit; end
  else if LK = 'zh|ModePage.Desc'         then begin Result := '指定您是要安装 Baseline 还是将其作为便携式应用运行。'; Exit; end
  else if LK = 'zh|ModePage.Action'       then begin Result := '选择操作：'; Exit; end
  else if LK = 'zh|RbInstall.Caption'     then begin Result := '安装到此电脑'; Exit; end
  else if LK = 'zh|RbInstall.Desc'        then begin Result := 'Baseline 将被安装并在程序和功能中注册。'; Exit; end
  else if LK = 'zh|RbPortable.Caption'    then begin Result := '便携版'; Exit; end
  else if LK = 'zh|RbPortable.Desc'       then begin Result := '运行便携版（无需安装）。'; Exit; end
  else if LK = 'zh|ScopePage.Title'       then begin Result := '安装范围'; Exit; end
  else if LK = 'zh|ScopePage.Desc'        then begin Result := '选择哪些用户可以使用 Baseline。'; Exit; end
  else if LK = 'zh|ScopePage.Heading'     then begin Result := '选择安装范围：'; Exit; end
  else if LK = 'zh|RbCurrentUser.Caption' then begin Result := '仅为我安装（推荐）'; Exit; end
  else if LK = 'zh|RbCurrentUser.Desc'    then begin Result := '仅为当前 Windows 账户安装 Baseline。'; Exit; end
  else if LK = 'zh|RbAllUsers.Caption'    then begin Result := '为所有用户安装'; Exit; end
  else if LK = 'zh|RbAllUsers.Desc'       then begin Result := '为此电脑上的所有账户安装 Baseline，如有需要将以管理员权限重启安装程序。'; Exit; end
  else if LK = 'zh|LocPage.Title'         then begin Result := '安装位置'; Exit; end
  else if LK = 'zh|LocPage.Desc'          then begin Result := '选择 Baseline 的安装位置。'; Exit; end
  else if LK = 'zh|LocPage.Heading'       then begin Result := '安装位置：'; Exit; end
  else if LK = 'zh|BtnBrowse.Caption'     then begin Result := '浏览...'; Exit; end
  else if LK = 'zh|LocPage.Note'          then begin Result := 'Baseline 将在 Windows 中注册，可通过"设置"卸载。'; Exit; end
  else if LK = 'zh|ShortPage.Title'       then begin Result := '快捷方式'; Exit; end
  else if LK = 'zh|ShortPage.Desc'        then begin Result := '选择要为 Baseline 创建的快捷方式。'; Exit; end
  else if LK = 'zh|ShortPage.Heading'     then begin Result := '创建以下快捷方式：'; Exit; end
  else if LK = 'zh|CbDesktop.Caption'     then begin Result := '桌面快捷方式'; Exit; end
  else if LK = 'zh|CbStartMenu.Caption'   then begin Result := '开始菜单快捷方式'; Exit; end
  else if LK = 'zh|FinishPage.Title'      then begin Result := '安装完成'; Exit; end
  else if LK = 'zh|FinishPage.Desc'       then begin Result := 'Baseline 已准备好使用。'; Exit; end
  else if LK = 'zh|CbLaunch.Caption'      then begin Result := '立即启动 Baseline'; Exit; end
  else if LK = 'zh|Btn.Next'              then begin Result := '下一步 >'; Exit; end
  else if LK = 'zh|Btn.Install'           then begin Result := '安装'; Exit; end
  else if LK = 'zh|Btn.Extract'           then begin Result := '提取'; Exit; end
  else if LK = 'zh|Btn.Finish'            then begin Result := '完成'; Exit; end;

  // Use the active Inno Setup language pack for any key we do not translate
  // manually above. This keeps the later wizard pages localized even when a
  // locale does not have a Baseline-specific override here.
  if Result = '' then
  begin
    if      Key = 'ModePage.Title'        then Result := SetupMessage(msgPrivilegesRequiredOverrideTitle)
    else if Key = 'ModePage.Desc'         then Result := SetupMessage(msgPrivilegesRequiredOverrideInstruction)
    else if Key = 'ModePage.Action'       then Result := SetupMessage(msgPrivilegesRequiredOverrideInstruction)
    else if Key = 'RbInstall.Caption'     then Result := SetupMessage(msgFullInstallation)
    else if Key = 'RbInstall.Desc'        then Result := ''
    else if Key = 'RbInstall.DisabledHint' then Result := 'Choose "Install for all users" setup mode to enable Install.'
    else if Key = 'RbPortable.Caption'    then Result := SetupMessage(msgCustomInstallation)
    else if Key = 'RbPortable.Desc'       then Result := ''
    else if Key = 'RbPortable.DisabledHint' then Result := 'Choose "Only me" setup mode to enable Portable.'
    else if Key = 'ScopePage.Title'       then Result := SetupMessage(msgPrivilegesRequiredOverrideTitle)
    else if Key = 'ScopePage.Desc'        then Result := Format(SetupMessage(msgPrivilegesRequiredOverrideText2), [ExpandConstant('{#MyAppName}')])
    else if Key = 'ScopePage.Heading'     then Result := SetupMessage(msgPrivilegesRequiredOverrideInstruction)
    else if Key = 'RbCurrentUser.Caption' then Result := SetupMessage(msgPrivilegesRequiredOverrideCurrentUserRecommended)
    else if Key = 'RbCurrentUser.Desc'    then Result := ''
    else if Key = 'RbAllUsers.Caption'    then Result := SetupMessage(msgPrivilegesRequiredOverrideAllUsersRecommended)
    else if Key = 'RbAllUsers.Desc'       then Result := ''
    else if Key = 'LocPage.Title'         then Result := SetupMessage(msgWizardSelectDir)
    else if Key = 'LocPage.Desc'          then Result := SetupMessage(msgSelectDirDesc)
    else if Key = 'LocPage.Heading'       then Result := SetupMessage(msgSelectDirLabel3)
    else if Key = 'BtnBrowse.Caption'     then Result := SetupMessage(msgButtonBrowse)
    else if Key = 'LocPage.Note'          then Result := SetupMessage(msgSelectDirBrowseLabel)
    else if Key = 'ShortPage.Title'       then Result := SetupMessage(msgWizardSelectTasks)
    else if Key = 'ShortPage.Desc'        then Result := SetupMessage(msgSelectTasksDesc)
    else if Key = 'ShortPage.Heading'     then Result := CustomMessage('AdditionalIcons')
    else if Key = 'CbDesktop.Caption'     then Result := CustomMessage('CreateDesktopIcon')
    else if Key = 'CbStartMenu.Caption'   then Result := CustomMessage('NoProgramGroupCheck2')
    else if Key = 'FinishPage.Title'      then Result := SetupMessage(msgFinishedHeadingLabel)
    else if Key = 'FinishPage.Desc'       then Result := SetupMessage(msgFinishedLabelNoIcons)
    else if Key = 'CbLaunch.Caption'      then Result := Format(CustomMessage('LaunchProgram'), [ExpandConstant('{#MyAppName}')])
    else if Key = 'Btn.Next'              then Result := SetupMessage(msgButtonNext)
    else if Key = 'Btn.Install'           then Result := SetupMessage(msgButtonInstall)
    else if Key = 'Btn.Extract'           then Result := 'Extract'
    else if Key = 'Btn.Finish'            then Result := SetupMessage(msgButtonFinish)
    else if Key = 'LangPage.Title'        then Result := 'Choose Language'
    else if Key = 'LangPage.Desc'         then Result := 'Choose the display language for Baseline.'
    else if Key = 'LangPage.Search'       then Result := 'Search languages:'
    else if Key = 'LangPage.Display'      then Result := 'Display language:'
    else if Key = 'LangPage.NoResults'    then Result := 'No matching languages found.'
    else if Key = 'LangPage.Help'         then Result := 'Search by English or native language name. You can change this later in Baseline.'
    else if Key = 'WizardTitle.Default'   then Result := 'Baseline Setup'
    else if Key = 'WizardTitle.Install'   then Result := 'Baseline Setup - Install'
    else if Key = 'WizardTitle.Portable'  then Result := 'Baseline Setup - Portable'
    else if Key = 'PortableMode.AllUsersError' then Result := 'Portable mode writes to the current user''s profile and cannot be installed in all-users setup mode. Restart Setup and choose "Current user" on the install scope page, or rerun Setup with /CURRENTUSER.'
    else if Key = 'RestartAdminError'     then Result := 'Setup could not be restarted with administrative privileges.'
    else if Key = 'InstallFolderDialog.Title' then Result := 'Select installation folder'
    else if Key = 'InstallPath.EmptyError' then Result := 'Please choose an installation folder.'
    else if Key = 'FinishMsg.Install'     then Result := 'Baseline has been installed to:'
    else if Key = 'FinishMsg.Portable'    then Result := 'Baseline is ready in:'
    else if Key = 'FinishMsg.PortableShortcut' then Result := 'A desktop shortcut has been created.'
    else Result := Key;
  end;
end;

// Apply translated strings to all wizard pages after language is confirmed.
procedure ApplyPageTranslations;
begin
  if Assigned(PageMode) then
  begin
    // Mode page
    PageMode.Caption     := GetSetupString('ModePage.Title');
    PageMode.Description := GetSetupString('ModePage.Desc');
    if Assigned(LblModeAction) then LblModeAction.Caption := GetSetupString('ModePage.Action');
    if Assigned(RbInstall) then RbInstall.Caption := GetSetupString('RbInstall.Caption');
    if Assigned(LblModeInstallDesc) then LblModeInstallDesc.Caption := GetSetupString('RbInstall.Desc');
    if Assigned(RbPortable) then RbPortable.Caption := GetSetupString('RbPortable.Caption');
    if Assigned(LblModePortableDesc) then LblModePortableDesc.Caption := GetSetupString('RbPortable.Desc');
  end;

  if Assigned(PageScope) then
  begin
    // Scope page
    PageScope.Caption     := GetSetupString('ScopePage.Title');
    PageScope.Description := GetSetupString('ScopePage.Desc');
    if Assigned(LblScopeHeading) then LblScopeHeading.Caption := GetSetupString('ScopePage.Heading');
    if Assigned(RbCurrentUser) then RbCurrentUser.Caption := GetSetupString('RbCurrentUser.Caption');
    if Assigned(LblScopeCurrentDesc) then LblScopeCurrentDesc.Caption := GetSetupString('RbCurrentUser.Desc');
    if Assigned(RbAllUsers) then RbAllUsers.Caption := GetSetupString('RbAllUsers.Caption');
    if Assigned(LblScopeAllDesc) then LblScopeAllDesc.Caption := GetSetupString('RbAllUsers.Desc');
  end;

  if Assigned(PageLocation) then
  begin
    // Location page
    PageLocation.Caption     := GetSetupString('LocPage.Title');
    PageLocation.Description := GetSetupString('LocPage.Desc');
    if Assigned(LblLocHeading) then LblLocHeading.Caption := GetSetupString('LocPage.Heading');
    if Assigned(BtnBrowse) then BtnBrowse.Caption := GetSetupString('BtnBrowse.Caption');
    if Assigned(LblLocNote) then LblLocNote.Caption := GetSetupString('LocPage.Note');
  end;

  if Assigned(PageShortcuts) then
  begin
    // Shortcuts page
    PageShortcuts.Caption     := GetSetupString('ShortPage.Title');
    PageShortcuts.Description := GetSetupString('ShortPage.Desc');
    if Assigned(LblShortHeading) then LblShortHeading.Caption := GetSetupString('ShortPage.Heading');
    if Assigned(CbDesktop) then CbDesktop.Caption := GetSetupString('CbDesktop.Caption');
    if Assigned(CbStartMenu) then CbStartMenu.Caption := GetSetupString('CbStartMenu.Caption');
  end;

  if Assigned(PageFinish) then
  begin
    // Finish page
    PageFinish.Caption     := GetSetupString('FinishPage.Title');
    PageFinish.Description := GetSetupString('FinishPage.Desc');
    if Assigned(CbLaunch) then CbLaunch.Caption := GetSetupString('CbLaunch.Caption');
  end;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Helper: write the Baseline session JSON to seed the chosen locale
// ─────────────────────────────────────────────────────────────────────────────

procedure WriteLocaleToSession(SessionPath: String; LocaleCode: String);
var
  Dir, Json: String;
begin
  Dir := ExtractFileDir(SessionPath);
  ForceDirectories(Dir);
  Json :=
    '{' + #13#10 +
    '  "Schema": "Baseline.GuiSettings",' + #13#10 +
    '  "SchemaVersion": 12,' + #13#10 +
    '  "Language": "' + LocaleCode + '"' + #13#10 +
    '}';
  SaveStringToFile(SessionPath, Json, False);
end;

function GetCommandLineSwitchValue(SwitchName: String): String;
var
  I: Integer;
  Param, Prefix, Value: String;
begin
  Result := '';
  Prefix := '/' + Uppercase(SwitchName) + '=';

  for I := 1 to ParamCount do
  begin
    Param := Trim(ParamStr(I));
    if Uppercase(Copy(Param, 1, Length(Prefix))) = Prefix then
    begin
      Value := Trim(Copy(Param, Length(Prefix) + 1, Length(Param) - Length(Prefix)));
      if (Length(Value) >= 2) and
         (((Value[1] = '"') and (Value[Length(Value)] = '"')) or ((Value[1] = '''') and (Value[Length(Value)] = ''''))) then
        Value := Copy(Value, 2, Length(Value) - 2);
      Result := Value;
      Exit;
    end;
  end;
end;

procedure SaveInstallResumeState(StatePath: String);
var
  StateDir, StateText: String;
begin
  StateDir := ExtractFileDir(StatePath);
  ForceDirectories(StateDir);

  StateText :=
    'Locale=' + GLocaleCode + #13#10 +
    'InstallMode=Install' + #13#10 +
    'InstallScope=AllUsers' + #13#10;

  SaveStringToFile(StatePath, StateText, False);
end;

function LoadInstallResumeState(StatePath: String): Boolean;
var
  Lines: TArrayOfString;
  I, SeparatorPos: Integer;
  Line, Key, Value: String;
begin
  Result := False;
  if not LoadStringsFromFile(StatePath, Lines) then
    Exit;

  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Trim(Lines[I]);
    if (Line = '') or (Copy(Line, 1, 1) = '#') then
      Continue;

    SeparatorPos := Pos('=', Line);
    if SeparatorPos <= 0 then
      Continue;

    Key := Uppercase(Trim(Copy(Line, 1, SeparatorPos - 1)));
    Value := Trim(Copy(Line, SeparatorPos + 1, Length(Line) - SeparatorPos));

    if Key = 'LOCALE' then
      GLocaleCode := Value
    else if Key = 'INSTALLMODE' then
      GInstallMode := Uppercase(Value) = 'INSTALL'
    else if Key = 'INSTALLSCOPE' then
      GInstallScopeAllUsers := Uppercase(Value) = 'ALLUSERS';
  end;

  Result := True;
end;

procedure LoadUpdateFlowState;
var
  UpdateMode, RelaunchDir: String;
begin
  GUpdateFlow := GetCommandLineSwitchValue('BASELINEUPDATE') <> '';
  if not GUpdateFlow then
    Exit;

  GUpdateRelaunchPath := GetCommandLineSwitchValue('RELAUNCH');
  GUpdateTargetDir := GetCommandLineSwitchValue('BASELINEUPDATETARGETDIR');
  UpdateMode := Uppercase(GetCommandLineSwitchValue('BASELINEUPDATEMODE'));
  RelaunchDir := ExtractFileDir(GUpdateRelaunchPath);
  if GUpdateTargetDir = '' then
    GUpdateTargetDir := RelaunchDir;

  GDesktop := False;
  GStartMenu := False;

  if UpdateMode = 'PORTABLE' then
  begin
    GInstallMode := False;
    if GUpdateTargetDir <> '' then
      GPortablePath := GUpdateTargetDir
    else
      GPortablePath := ExpandConstant('{localappdata}') + '\Baseline';
  end
  else
  begin
    GInstallMode := True;
    if GUpdateTargetDir <> '' then
      GInstallPath := GUpdateTargetDir;
  end;
end;

function GetSetupFreshnessChannel: String;
begin
  Result := '{#MyAppChannel}';
end;

function GetSetupFreshnessApiUrl: String;
begin
  if Uppercase(GetSetupFreshnessChannel) = 'BETA' then
    Result := 'https://api.github.com/repos/sdmanson8/Baseline/releases'
  else
    Result := 'https://api.github.com/repos/sdmanson8/Baseline/releases';
end;

function GetSetupFreshnessScript: String;
begin
  Result :=
    'param([string]$ApiUrl,[string]$CurrentVersion,[string]$Channel,[string]$OutPath)' + #13#10 +
    '$ErrorActionPreference = ''Stop''' + #13#10 +
    'function Write-State([hashtable]$State) {' + #13#10 +
    '  $order = @(''Status'',''CurrentDisplayVersion'',''LatestDisplayVersion'',''ReleaseUrl'')' + #13#10 +
    '  $lines = foreach ($key in $order) { if ($State.ContainsKey($key)) { "{0}={1}" -f $key, ([string]$State[$key]) } }' + #13#10 +
    '  $encoding = New-Object System.Text.UTF8Encoding($false)' + #13#10 +
    '  [System.IO.File]::WriteAllLines($OutPath, [string[]]$lines, $encoding)' + #13#10 +
    '}' + #13#10 +
    'function Convert-SetupVersion([string]$Version) {' + #13#10 +
    '  if ([string]::IsNullOrWhiteSpace($Version)) { return $null }' + #13#10 +
    '  $match = [regex]::Match($Version.Trim(), ''(?i)(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)'')' + #13#10 +
    '  if (-not $match.Success) { return $null }' + #13#10 +
    '  [pscustomobject]@{ Major = [int]$match.Groups[''major''].Value; Minor = [int]$match.Groups[''minor''].Value; Patch = [int]$match.Groups[''patch''].Value }' + #13#10 +
    '}' + #13#10 +
    'function Compare-SetupVersion($Left, $Right) {' + #13#10 +
    '  foreach ($name in @(''Major'',''Minor'',''Patch'')) {' + #13#10 +
    '    if ($Left.$name -gt $Right.$name) { return 1 }' + #13#10 +
    '    if ($Left.$name -lt $Right.$name) { return -1 }' + #13#10 +
    '  }' + #13#10 +
    '  return 0' + #13#10 +
    '}' + #13#10 +
    'function Format-SetupVersion([string]$Version) {' + #13#10 +
    '  $text = ([string]$Version).Trim()' + #13#10 +
    '  if ($text -notmatch ''^v'') { $text = ''v'' + $text }' + #13#10 +
    '  return $text' + #13#10 +
    '}' + #13#10 +
    'try {' + #13#10 +
    '  if ([string]::IsNullOrWhiteSpace($ApiUrl) -or [string]::IsNullOrWhiteSpace($CurrentVersion)) { Write-State @{ Status = ''Skipped'' }; exit 0 }' + #13#10 +
    '  $currentText = $CurrentVersion.Trim()' + #13#10 +
    '  $currentVersionObject = Convert-SetupVersion $currentText' + #13#10 +
    '  if ($null -eq $currentVersionObject) { Write-State @{ Status = ''Skipped'' }; exit 0 }' + #13#10 +
    '  $request = [System.Net.HttpWebRequest]::Create($ApiUrl)' + #13#10 +
    '  $request.Method = ''GET''' + #13#10 +
    '  $request.Timeout = 3000' + #13#10 +
    '  $request.ReadWriteTimeout = 3000' + #13#10 +
    '  $request.UserAgent = ''Baseline-SetupFreshness''' + #13#10 +
    '  $response = $request.GetResponse()' + #13#10 +
    '  $reader = New-Object System.IO.StreamReader($response.GetResponseStream())' + #13#10 +
    '  $releases = @($reader.ReadToEnd() | ConvertFrom-Json)' + #13#10 +
    '  $reader.Dispose(); $response.Dispose()' + #13#10 +
    '  $releaseChannelToken = ''stable''' + #13#10 +
    '  $assetPattern = ''(?i)^Baseline-\d+\.\d+\.\d+-'' + [regex]::Escape($releaseChannelToken) + ''\.zip$''' + #13#10 +
    '  $bestRelease = $null; $bestVersion = $null; $bestUrl = $null' + #13#10 +
    '  foreach ($release in @($releases | Where-Object { -not $_.draft })) {' + #13#10 +
    '    $asset = @($release.assets | Where-Object { $_.name -match $assetPattern } | Select-Object -First 1)' + #13#10 +
    '    if (-not $asset) { continue }' + #13#10 +
    '    $candidateVersion = Convert-SetupVersion ([string]$release.tag_name)' + #13#10 +
    '    if ($null -eq $candidateVersion) { continue }' + #13#10 +
    '    if (($null -eq $bestVersion) -or ((Compare-SetupVersion $candidateVersion $bestVersion) -gt 0)) { $bestRelease = $release; $bestVersion = $candidateVersion; $bestUrl = if ($asset.browser_download_url) { [string]$asset.browser_download_url } else { [string]$release.html_url } }' + #13#10 +
    '  }' + #13#10 +
    '  if ($null -eq $bestRelease) { Write-State @{ Status = ''UpToDate''; CurrentDisplayVersion = (Format-SetupVersion $currentText) }; exit 0 }' + #13#10 +
    '  if ((Compare-SetupVersion $bestVersion $currentVersionObject) -gt 0) { Write-State @{ Status = ''UpdateAvailable''; CurrentDisplayVersion = (Format-SetupVersion $currentText); LatestDisplayVersion = (Format-SetupVersion ([string]$bestRelease.tag_name)); ReleaseUrl = $bestUrl }; exit 0 }' + #13#10 +
    '  Write-State @{ Status = ''UpToDate''; CurrentDisplayVersion = (Format-SetupVersion $currentText); LatestDisplayVersion = (Format-SetupVersion ([string]$bestRelease.tag_name)) }' + #13#10 +
    '} catch {' + #13#10 +
    '  Write-State @{ Status = ''Skipped'' }' + #13#10 +
    '}';
end;

function ReadSetupFreshnessStateValue(StatePath, Name: String): String;
var
  Lines: TArrayOfString;
  I, SeparatorPos: Integer;
  Line, Key: String;
begin
  Result := '';
  if not LoadStringsFromFile(StatePath, Lines) then
    Exit;

  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Trim(Lines[I]);
    SeparatorPos := Pos('=', Line);
    if SeparatorPos <= 0 then
      Continue;

    Key := Uppercase(Trim(Copy(Line, 1, SeparatorPos - 1)));
    if Key = Uppercase(Name) then
    begin
      Result := Trim(Copy(Line, SeparatorPos + 1, Length(Line) - SeparatorPos));
      Exit;
    end;
  end;
end;

function ShowSetupFreshnessPrompt(CurrentDisplayVersion, LatestDisplayVersion: String): Integer;
begin
  Result := TaskDialogMsgBox(
    'A newer Baseline setup is available.',
    'Installed setup:' + #13#10 +
    CurrentDisplayVersion + #13#10 + #13#10 +
    'Latest setup:' + #13#10 +
    LatestDisplayVersion + #13#10 + #13#10 +
    'The newer setup may contain fixes, updated assets, or installation improvements.',
    mbInformation,
    MB_YESNOCANCEL, ['Continue Anyway', 'Download Latest Setup', 'Cancel'],
    IDYES);
end;

function RunSetupFreshnessCheck: Boolean;
var
  ScriptPath, StatePath, PowerShellPath, Arguments: String;
  Status, CurrentDisplayVersion, LatestDisplayVersion, ReleaseUrl: String;
  ResultCode, Choice: Integer;
begin
  Result := True;

  if GUpdateFlow or GResumeInstallFlow or WizardSilent then
    Exit;

  ScriptPath := ExpandConstant('{tmp}\BaselineSetupFreshness.ps1');
  StatePath := ExpandConstant('{tmp}\BaselineSetupFreshness.txt');
  DeleteFile(StatePath);

  if not SaveStringToFile(ScriptPath, GetSetupFreshnessScript, False) then
    Exit;

  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not FileExists(PowerShellPath) then
    Exit;

  Arguments :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"' +
    ' -ApiUrl "' + GetSetupFreshnessApiUrl + '"' +
    ' -CurrentVersion "{#MyAppVersion}"' +
    ' -Channel "' + GetSetupFreshnessChannel + '"' +
    ' -OutPath "' + StatePath + '"';

  if not Exec(PowerShellPath, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Exit;

  Status := ReadSetupFreshnessStateValue(StatePath, 'Status');
  if Status <> 'UpdateAvailable' then
    Exit;

  CurrentDisplayVersion := ReadSetupFreshnessStateValue(StatePath, 'CurrentDisplayVersion');
  LatestDisplayVersion := ReadSetupFreshnessStateValue(StatePath, 'LatestDisplayVersion');
  ReleaseUrl := ReadSetupFreshnessStateValue(StatePath, 'ReleaseUrl');

  Choice := ShowSetupFreshnessPrompt(CurrentDisplayVersion, LatestDisplayVersion);
  if Choice = IDNO then
  begin
    Result := False;
    if ReleaseUrl <> '' then
      ShellExecAsOriginalUser('open', ReleaseUrl, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
    Exit;
  end;

  if Choice <> IDYES then
    Result := False;
end;

procedure RestartInstallForAllUsers;
var
  ResultCode: Integer;
  ResumeStatePath, LaunchCommand, CmdExe: String;
begin
  ResumeStatePath := ExpandConstant('{localappdata}') + '\Baseline\SetupResume\install-state.txt';
  SaveInstallResumeState(ResumeStatePath);

  CmdExe := ExpandConstant('{sys}') + '\cmd.exe';
  LaunchCommand :=
    '/c ""' + ExpandConstant('{srcexe}') + '" /SP- /ALLUSERS /RESUMEINSTALL="' + ResumeStatePath + '""';

  GProgrammaticClose := True;
  if not ShellExec('runas', CmdExe, LaunchCommand, '', SW_HIDE, ewNoWait, ResultCode) then
  begin
    GProgrammaticClose := False;
    DeleteFile(ResumeStatePath);
    MsgBox(GetSetupString('RestartAdminError'), mbError, MB_OK);
    Exit;
  end;

  WizardForm.Close;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Helper: label factories
// ─────────────────────────────────────────────────────────────────────────────

function AddBoldLabel(Page: TWizardPage; Caption: String; X, Y, W: Integer): TNewStaticText;
var
  L: TNewStaticText;
begin
  L := TNewStaticText.Create(Page);
  L.Parent     := Page.Surface;
  L.Caption    := Caption;
  L.Left       := ScaleX(X);
  L.Top        := ScaleY(Y);
  L.Width      := ScaleX(W);
  L.Font.Style := [fsBold];
  Result := L;
end;

function AddLabel(Page: TWizardPage; Caption: String; X, Y, W, H: Integer): TNewStaticText;
var
  L: TNewStaticText;
begin
  L := TNewStaticText.Create(Page);
  L.Parent   := Page.Surface;
  L.Caption  := Caption;
  L.Left     := ScaleX(X);
  L.Top      := ScaleY(Y);
  L.Width    := ScaleX(W);
  L.Height   := ScaleY(H);
  L.WordWrap := True;
  Result := L;
end;

procedure UpdateNextButtonCaption(CurPageID: Integer);
begin
  if Assigned(PageFinish) and (CurPageID = PageFinish.ID) then
  begin
    WizardForm.NextButton.Caption   := GetSetupString('Btn.Finish');
    WizardForm.BackButton.Enabled   := False;
    WizardForm.CancelButton.Enabled := False;
    Exit;
  end;

  WizardForm.BackButton.Enabled   := True;
  WizardForm.CancelButton.Enabled := True;

  if Assigned(PageMode) and (CurPageID = PageMode.ID) and Assigned(RbPortable) and RbPortable.Checked then
    WizardForm.NextButton.Caption := GetSetupString('Btn.Extract')
  else if Assigned(PageShortcuts) and (CurPageID = PageShortcuts.ID) then
    WizardForm.NextButton.Caption := GetSetupString('Btn.Install')
  else
    WizardForm.NextButton.Caption := GetSetupString('Btn.Next');
end;

procedure ModeSelectionChanged(Sender: TObject);
begin
  if IsAdminInstallMode and Assigned(RbPortable) and RbPortable.Checked then
  begin
    RbPortable.Checked := False;
    RbInstall.Checked := True;
  end
  else if (not IsAdminInstallMode) and Assigned(RbInstall) and RbInstall.Checked then
  begin
    RbInstall.Checked := False;
    RbPortable.Checked := True;
  end;

  UpdateNextButtonCaption(PageMode.ID);
end;

procedure ApplyModeAvailability;
var
  InstallHint: String;
  PortableHint: String;
begin
  if GUpdateFlow or GResumeInstallFlow then
    Exit;

  if (not Assigned(RbInstall)) or (not Assigned(RbPortable)) then
    Exit;

  InstallHint := '';
  PortableHint := '';

  if IsAdminInstallMode then
  begin
    RbInstall.Enabled := True;
    RbPortable.Enabled := False;
    RbInstall.Checked := True;
    RbPortable.Checked := False;
    GInstallMode := True;
    PortableHint := GetSetupString('RbPortable.DisabledHint');
  end
  else
  begin
    RbInstall.Enabled := False;
    RbPortable.Enabled := True;
    RbInstall.Checked := False;
    RbPortable.Checked := True;
    GInstallMode := False;
    InstallHint := GetSetupString('RbInstall.DisabledHint');
  end;

  RbInstall.Hint := InstallHint;
  RbInstall.ShowHint := InstallHint <> '';
  RbPortable.Hint := PortableHint;
  RbPortable.ShowHint := PortableHint <> '';

  if Assigned(LblModeInstallDesc) then
  begin
    LblModeInstallDesc.Enabled := RbInstall.Enabled;
    LblModeInstallDesc.Hint := InstallHint;
    LblModeInstallDesc.ShowHint := InstallHint <> '';
  end;
  if Assigned(LblModePortableDesc) then
  begin
    LblModePortableDesc.Enabled := RbPortable.Enabled;
    LblModePortableDesc.Hint := PortableHint;
    LblModePortableDesc.ShowHint := PortableHint <> '';
  end;

  UpdateNextButtonCaption(PageMode.ID);
end;

function MatchesLocaleFilter(Entry: String; FilterText: String): Boolean;
var
  SearchText: String;
begin
  FilterText := Trim(FilterText);
  if FilterText = '' then
  begin
    Result := True;
    Exit;
  end;

  SearchText := LocaleEnglishName(Entry) + ' ' + LocaleNativeName(Entry) + ' ' + LocaleCode(Entry);
  Result := Pos(Lowercase(FilterText), Lowercase(SearchText)) > 0;
end;

procedure ApplyLanguagePageTranslations; forward;

procedure LanguageSelectionChanged(Sender: TObject);
begin
  if (LangList.ItemIndex >= 0) and (LangList.ItemIndex < LangVisibleCount) then
    GLocaleCode := LocaleCode(LangVisibleEntries[LangList.ItemIndex]);

  ApplyLanguagePageTranslations;
  WizardForm.Caption := GetSetupString('WizardTitle.Default');
  UpdateNextButtonCaption(PageLanguage.ID);
  ApplyPageTranslations;
end;

procedure ApplyLanguagePageTranslations;
begin
  if Assigned(PageLanguage) then
  begin
    PageLanguage.Caption     := GetSetupString('LangPage.Title');
    PageLanguage.Description := GetSetupString('LangPage.Desc');
  end;

  if Assigned(LblLangSearch) then LblLangSearch.Caption := GetSetupString('LangPage.Search');
  if Assigned(LblLangDisplay) then LblLangDisplay.Caption := GetSetupString('LangPage.Display');
  if Assigned(LangNoResults) then LangNoResults.Caption := GetSetupString('LangPage.NoResults');
  if Assigned(LblLangHelp) then LblLangHelp.Caption := GetSetupString('LangPage.Help');
end;

procedure PopulateLanguageList(FilterText: String);
var
  ActiveCode, Entry: String;
  i, MatchIndex, SelectedIndex: Integer;
begin
  ActiveCode := GLocaleCode;
  if (LangList.ItemIndex >= 0) and (LangList.ItemIndex < LangVisibleCount) then
    ActiveCode := LocaleCode(LangVisibleEntries[LangList.ItemIndex]);

  LangList.Items.Clear;
  SetArrayLength(LangVisibleEntries, 0);
  LangVisibleCount := 0;
  SelectedIndex := -1;

  for i := 0 to LocaleCount - 1 do
  begin
    Entry := LocaleEntries[i];
    if MatchesLocaleFilter(Entry, FilterText) then
    begin
      MatchIndex := LangVisibleCount;
      SetArrayLength(LangVisibleEntries, LangVisibleCount + 1);
      LangVisibleEntries[MatchIndex] := Entry;
      LangList.Items.Add(LocaleDisplayName(Entry));
      if LocaleCode(Entry) = ActiveCode then
        SelectedIndex := MatchIndex;
      LangVisibleCount := LangVisibleCount + 1;
    end;
  end;

  LangNoResults.Visible := LangVisibleCount = 0;
  LangList.Enabled := LangVisibleCount > 0;

  if LangVisibleCount > 0 then
  begin
    if SelectedIndex < 0 then
      SelectedIndex := 0;
    LangList.ItemIndex := SelectedIndex;
    GLocaleCode := LocaleCode(LangVisibleEntries[SelectedIndex]);
  end
  else
    LangList.ItemIndex := -1;

  ApplyLanguagePageTranslations;
  WizardForm.Caption := GetSetupString('WizardTitle.Default');
  UpdateNextButtonCaption(PageLanguage.ID);
end;

procedure LanguageSearchChanged(Sender: TObject);
begin
  PopulateLanguageList(LangSearchEdit.Text);
end;

// ─────────────────────────────────────────────────────────────────────────────
// Page 1: Language — populated from embedded locale list
// ─────────────────────────────────────────────────────────────────────────────

procedure CreatePageLanguage;
begin
  PageLanguage := CreateCustomPage(wpWelcome, GetSetupString('LangPage.Title'), GetSetupString('LangPage.Desc'));

  LblLangSearch := AddBoldLabel(PageLanguage, GetSetupString('LangPage.Search'), 0, 0, 200);

  LangSearchEdit := TNewEdit.Create(PageLanguage);
  LangSearchEdit.Parent   := PageLanguage.Surface;
  LangSearchEdit.Left     := ScaleX(0);
  LangSearchEdit.Top      := ScaleY(20);
  LangSearchEdit.Width    := ScaleX(400);
  LangSearchEdit.OnChange := @LanguageSearchChanged;

  LblLangDisplay := AddBoldLabel(PageLanguage, GetSetupString('LangPage.Display'), 0, 54, 200);

  LangList := TNewListBox.Create(PageLanguage);
  LangList.Parent := PageLanguage.Surface;
  LangList.Left   := ScaleX(0);
  LangList.Top    := ScaleY(76);
  LangList.Width  := ScaleX(400);
  LangList.Height := ScaleY(132);
  LangList.OnClick := @LanguageSelectionChanged;

  LangNoResults := AddLabel(PageLanguage, GetSetupString('LangPage.NoResults'), 0, 212, 400, 16);
  LangNoResults.Visible := False;

  LblLangHelp := AddLabel(PageLanguage,
    GetSetupString('LangPage.Help'),
    0, 230, 400, 32);

  PopulateLanguageList('');
  ApplyPageTranslations;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Page 2: Mode (Install / Portable)
// ─────────────────────────────────────────────────────────────────────────────

procedure CreatePageMode;
begin
  PageMode := CreateCustomPage(PageLanguage.ID, 'Installation Type', 'Specify whether you want to install Baseline or run it as a portable app.');

  LblModeAction := AddLabel(PageMode, 'Select action:', 0, 0, 200, 16);

  RbInstall := TNewRadioButton.Create(PageMode);
  RbInstall.Parent     := PageMode.Surface;
  RbInstall.Caption    := 'Install for this PC';
  RbInstall.Left       := ScaleX(0);
  RbInstall.Top        := ScaleY(24);
  RbInstall.Width      := ScaleX(400);
  RbInstall.Checked    := True;
  RbInstall.Font.Style := [fsBold];
  RbInstall.OnClick    := @ModeSelectionChanged;

  LblModeInstallDesc := AddLabel(PageMode,
    'Baseline will be installed and registered in Programs and Features.',
    18, 46, 390, 18);

  RbPortable := TNewRadioButton.Create(PageMode);
  RbPortable.Parent     := PageMode.Surface;
  RbPortable.Caption    := 'Portable';
  RbPortable.Left       := ScaleX(0);
  RbPortable.Top        := ScaleY(78);
  RbPortable.Width      := ScaleX(400);
  RbPortable.Font.Style := [fsBold];
  RbPortable.OnClick    := @ModeSelectionChanged;

  LblModePortableDesc := AddLabel(PageMode,
    'Run portable version (no installation needed).',
    18, 100, 390, 18);

  ApplyModeAvailability;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Page 3: Install scope (Install only)
// ─────────────────────────────────────────────────────────────────────────────

procedure CreatePageScope;
begin
  PageScope := CreateCustomPage(PageMode.ID, 'Install Scope', 'Choose who should be able to use Baseline.');

  LblScopeHeading := AddBoldLabel(PageScope, 'Select install scope:', 0, 0, 200);

  RbCurrentUser := TNewRadioButton.Create(PageScope);
  RbCurrentUser.Parent     := PageScope.Surface;
  RbCurrentUser.Caption    := 'Install for me only (recommended)';
  RbCurrentUser.Left       := ScaleX(0);
  RbCurrentUser.Top        := ScaleY(24);
  RbCurrentUser.Width      := ScaleX(400);
  RbCurrentUser.Checked    := not GInstallScopeAllUsers;
  RbCurrentUser.Font.Style := [fsBold];

  LblScopeCurrentDesc := AddLabel(PageScope,
    'Installs Baseline for the current Windows account only.',
    18, 46, 390, 18);

  RbAllUsers := TNewRadioButton.Create(PageScope);
  RbAllUsers.Parent     := PageScope.Surface;
  RbAllUsers.Caption    := 'Install for all users';
  RbAllUsers.Left       := ScaleX(0);
  RbAllUsers.Top        := ScaleY(78);
  RbAllUsers.Width      := ScaleX(400);
  RbAllUsers.Checked    := GInstallScopeAllUsers;
  RbAllUsers.Font.Style := [fsBold];

  LblScopeAllDesc := AddLabel(PageScope,
    'Installs Baseline for every account on this PC and restarts Setup with administrative privileges if needed.',
    18, 100, 390, 36);
end;

// ─────────────────────────────────────────────────────────────────────────────
// Page 4: Location (Install only)
// ─────────────────────────────────────────────────────────────────────────────

procedure BrowseForInstallFolder(Sender: TObject);
var
  Dir: String;
begin
  Dir := DirEdit.Text;
  if BrowseForFolder(GetSetupString('InstallFolderDialog.Title'), Dir, True) then
    DirEdit.Text := Dir;
end;

procedure CreatePageLocation;
begin
  PageLocation := CreateCustomPage(PageScope.ID, 'Install Location', 'Choose where Baseline should be installed.');

  LblLocHeading := AddBoldLabel(PageLocation, 'Install location:', 0, 0, 120);

  DirEdit := TNewEdit.Create(PageLocation);
  DirEdit.Parent := PageLocation.Surface;
  DirEdit.Left   := ScaleX(0);
  DirEdit.Top    := ScaleY(20);
  DirEdit.Width  := ScaleX(320);
  DirEdit.Text   := ExpandConstant('{pf}') + '\Baseline';

  BtnBrowse := TNewButton.Create(PageLocation);
  BtnBrowse.Parent   := PageLocation.Surface;
  BtnBrowse.Caption  := 'Browse...';
  BtnBrowse.Left     := ScaleX(328);
  BtnBrowse.Top      := ScaleY(18);
  BtnBrowse.Width    := ScaleX(76);
  BtnBrowse.Height   := ScaleY(23);
  BtnBrowse.OnClick  := @BrowseForInstallFolder;

  LblLocNote := AddLabel(PageLocation,
    'Baseline will be registered with Windows and can be uninstalled from Settings.',
    0, 56, 400, 36);
end;

// ─────────────────────────────────────────────────────────────────────────────
// Page 5: Shortcuts (Install only)
// ─────────────────────────────────────────────────────────────────────────────

procedure CreatePageShortcuts;
begin
  PageShortcuts := CreateCustomPage(PageLocation.ID, 'Shortcuts', 'Choose which shortcuts to create for Baseline.');

  LblShortHeading := AddBoldLabel(PageShortcuts, 'Create these shortcuts:', 0, 0, 200);

  CbDesktop := TNewCheckBox.Create(PageShortcuts);
  CbDesktop.Parent  := PageShortcuts.Surface;
  CbDesktop.Caption := 'Desktop shortcut';
  CbDesktop.Left    := ScaleX(0);
  CbDesktop.Top     := ScaleY(24);
  CbDesktop.Width   := ScaleX(300);
  CbDesktop.Checked := True;

  CbStartMenu := TNewCheckBox.Create(PageShortcuts);
  CbStartMenu.Parent  := PageShortcuts.Surface;
  CbStartMenu.Caption := 'Start menu shortcut';
  CbStartMenu.Left    := ScaleX(0);
  CbStartMenu.Top     := ScaleY(50);
  CbStartMenu.Width   := ScaleX(300);
  CbStartMenu.Checked := True;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Page 6: Finish page
// ─────────────────────────────────────────────────────────────────────────────

procedure CreatePageFinish;
var
  L: TNewStaticText;
begin
  PageFinish := CreateCustomPage(wpInstalling, 'Setup Complete', 'Baseline is ready to use.');

  L := AddLabel(PageFinish, '', 0, 0, 400, 40);
  L.Name := 'FinishMsg';

  CbLaunch := TNewCheckBox.Create(PageFinish);
  CbLaunch.Parent  := PageFinish.Surface;
  CbLaunch.Caption := 'Launch Baseline now';
  CbLaunch.Left    := ScaleX(0);
  CbLaunch.Top     := ScaleY(56);
  CbLaunch.Width   := ScaleX(300);
  CbLaunch.Checked := True;
end;

// ─────────────────────────────────────────────────────────────────────────────
// Portable extract
// ─────────────────────────────────────────────────────────────────────────────

procedure ExtractPortable;
var
  Dest: String;
begin
  if GPortablePath = '' then
    GPortablePath := ExpandConstant('{localappdata}') + '\Baseline';
  ForceDirectories(GPortablePath);
  Dest := GPortablePath + '\{#MyAppExeName}';

  if not FileExists(Dest) then
    RaiseException('Portable Baseline.exe was not found after extraction: ' + Dest);

  if not SaveStringToFile(GPortablePath + '\Baseline.portable', 'portable=1'#13#10, False) then
    RaiseException('Portable marker could not be written: ' + GPortablePath + '\Baseline.portable');

  if GDesktop then
    CreateShellLink(
      ExpandConstant('{autodesktop}') + '\Baseline.lnk',
      'Baseline',
      Dest,
      '',
      GPortablePath,
      Dest,
      0,
      SW_SHOWNORMAL);
end;

// ─────────────────────────────────────────────────────────────────────────────
// Seed the Baseline session JSON with the chosen locale
// ─────────────────────────────────────────────────────────────────────────────

procedure SeedLocale;
var
  SessionPath: String;
begin
  if GLocaleCode = 'en' then Exit;  // English is the default — no seeding needed

  if GInstallMode then
    // Installed: session lives in %LOCALAPPDATA%\Baseline\Profiles\
    SessionPath := ExpandConstant('{localappdata}') + '\Baseline\Profiles\Baseline-last-session.json'
  else
    // Portable: session lives alongside the exe in Data\Profiles\
    SessionPath := GPortablePath + '\Data\Profiles\Baseline-last-session.json';

  WriteLocaleToSession(SessionPath, GLocaleCode);
end;

// ─────────────────────────────────────────────────────────────────────────────
// Launch after finish
// ─────────────────────────────────────────────────────────────────────────────

function NormalizeSetupComparePath(Value: String): String;
begin
  Result := Uppercase(AddBackslash(Value));
end;

function IsBaselineRelaunchPathAllowed(ExePath, TargetDir: String): Boolean;
var
  ExeName, ExeDir, ExpectedDir: String;
begin
  Result := False;

  if (ExePath = '') or (TargetDir = '') then
    Exit;

  ExeName := ExtractFileName(ExePath);
  if Uppercase(ExeName) <> Uppercase('{#MyAppExeName}') then
    Exit;

  ExeDir := NormalizeSetupComparePath(ExtractFileDir(ExePath));
  ExpectedDir := NormalizeSetupComparePath(TargetDir);
  Result := Pos(ExpectedDir, ExeDir) = 1;
end;

procedure LaunchBaseline;
var
  ExePath, WorkDir, ExpectedDir: String;
  ResultCode: Integer;
begin
  if GUpdateRelaunchPath <> '' then
  begin
    ExePath := GUpdateRelaunchPath;
    WorkDir := ExtractFileDir(ExePath);
    if GInstallMode then
      ExpectedDir := GInstallPath
    else
      ExpectedDir := GPortablePath;

    if not IsBaselineRelaunchPathAllowed(ExePath, ExpectedDir) then
    begin
      Log('Rejected update relaunch target: ' + ExePath);
      Exit;
    end;
  end
  else if GInstallMode then
  begin
    WorkDir := GInstallPath;
    ExePath := WorkDir + '\{#MyAppExeName}';
  end
  else
  begin
    WorkDir := GPortablePath;
    ExePath := WorkDir + '\{#MyAppExeName}';
  end;

  if not FileExists(ExePath) then
  begin
    Log('Baseline launch target missing: ' + ExePath);
    Exit;
  end;

  if not ShellExec('open', ExePath, '', WorkDir, SW_SHOW, ewNoWait, ResultCode) then
    Log('Failed to launch Baseline: ' + ExePath + '; result code: ' + IntToStr(ResultCode));
end;

// ─────────────────────────────────────────────────────────────────────────────
// Inno event hooks
// ─────────────────────────────────────────────────────────────────────────────

procedure InitLocaleEntries;
begin
  SetArrayLength(LocaleEntries, LocaleCount);
  LocaleEntries[0]   := 'Afrikaans|Afrikaans|af';
  LocaleEntries[1]   := 'Amharic|አማርኛ|am';
  LocaleEntries[2]   := 'Arabic|العربية|ar';
  LocaleEntries[3]   := 'Assamese|অসমীয়া|as';
  LocaleEntries[4]   := 'Azerbaijani|azərbaycan|az';
  LocaleEntries[5]   := 'Belarusian|беларуская|be';
  LocaleEntries[6]   := 'Bulgarian|български|bg';
  LocaleEntries[7]   := 'Bengali|বাংলা|bn';
  LocaleEntries[8]   := 'Bengali (Bangladesh)|বাংলা (বাংলাদেশ)|bn-BD';
  LocaleEntries[9]   := 'Bosnian|bosanski|bs';
  LocaleEntries[10]  := 'Catalan|català|ca';
  LocaleEntries[11]  := 'Central Kurdish|کوردیی ناوەندی|ckb';
  LocaleEntries[12]  := 'Czech|čeština|cs';
  LocaleEntries[13]  := 'Welsh|Cymraeg|cy';
  LocaleEntries[14]  := 'Danish|dansk|da';
  LocaleEntries[15]  := 'German|Deutsch|de';
  LocaleEntries[16]  := 'Greek|Ελληνικά|el';
  LocaleEntries[17]  := 'English (US)|English|en';
  LocaleEntries[18]  := 'English (United Kingdom)|English (United Kingdom)|en-GB';
  LocaleEntries[19]  := 'English (Australia)|English (Australia)|en-AU';
  LocaleEntries[20]  := 'English (Belize)|English (Belize)|en-BZ';
  LocaleEntries[21]  := 'English (Canada)|English (Canada)|en-CA';
  LocaleEntries[22]  := 'English (Caribbean)|English (Caribbean)|en-029';
  LocaleEntries[23]  := 'English (India)|English (India)|en-IN';
  LocaleEntries[24]  := 'English (Ireland)|English (Ireland)|en-IE';
  LocaleEntries[25]  := 'English (Jamaica)|English (Jamaica)|en-JM';
  LocaleEntries[26]  := 'English (Malaysia)|English (Malaysia)|en-MY';
  LocaleEntries[27]  := 'English (Maldives)|English (Maldives)|en-MV';
  LocaleEntries[28]  := 'English (New Zealand)|English (New Zealand)|en-NZ';
  LocaleEntries[29]  := 'English (Philippines)|English (Philippines)|en-PH';
  LocaleEntries[30]  := 'English (Singapore)|English (Singapore)|en-SG';
  LocaleEntries[31]  := 'English (South Africa)|English (South Africa)|en-ZA';
  LocaleEntries[32]  := 'English (Trinidad and Tobago)|English (Trinidad and Tobago)|en-TT';
  LocaleEntries[33]  := 'English (United Arab Emirates)|English (United Arab Emirates)|en-AE';
  LocaleEntries[34]  := 'English (Zimbabwe)|English (Zimbabwe)|en-ZW';
  LocaleEntries[35]  := 'Spanish|español|es';
  LocaleEntries[36]  := 'Spanish (Mexico)|español (México)|es-MX';
  LocaleEntries[37]  := 'Estonian|eesti|et';
  LocaleEntries[38]  := 'Basque|euskara|eu';
  LocaleEntries[39]  := 'Persian|فارسی|fa';
  LocaleEntries[40]  := 'Finnish|suomi|fi';
  LocaleEntries[41]  := 'Filipino|Filipino|fil';
  LocaleEntries[42]  := 'French|français|fr';
  LocaleEntries[43]  := 'French (Canada)|français (Canada)|fr-CA';
  LocaleEntries[44]  := 'Irish|Gaeilge|ga';
  LocaleEntries[45]  := 'Scottish Gaelic|Gàidhlig|gd';
  LocaleEntries[46]  := 'Galician|galego|gl';
  LocaleEntries[47]  := 'Gujarati|ગુજરાતી|gu';
  LocaleEntries[48]  := 'Hausa|Hausa|ha';
  LocaleEntries[49]  := 'Hebrew|עברית|he';
  LocaleEntries[50]  := 'Hindi|हिन्दी|hi';
  LocaleEntries[51]  := 'Croatian|hrvatski|hr';
  LocaleEntries[52]  := 'Hungarian|magyar|hu';
  LocaleEntries[53]  := 'Armenian|հայերեն|hy';
  LocaleEntries[54]  := 'Indonesian|Indonesia|id';
  LocaleEntries[55]  := 'Igbo|Igbo|ig';
  LocaleEntries[56]  := 'Icelandic|íslenska|is';
  LocaleEntries[57]  := 'Italian|italiano|it';
  LocaleEntries[58]  := 'Japanese|日本語|ja';
  LocaleEntries[59]  := 'Georgian|ქართული|ka';
  LocaleEntries[60]  := 'Kazakh|қазақ тілі|kk';
  LocaleEntries[61]  := 'Khmer|ខ្មែរ|km';
  LocaleEntries[62]  := 'Kannada|ಕನ್ನಡ|kn';
  LocaleEntries[63]  := 'Korean|한국어|ko';
  LocaleEntries[64]  := 'Konkani|कोंकणी|kok';
  LocaleEntries[65]  := 'Kyrgyz|кыргызча|ky';
  LocaleEntries[66]  := 'Luxembourgish|Lëtzebuergesch|lb';
  LocaleEntries[67]  := 'Lao|ລາວ|lo';
  LocaleEntries[68]  := 'Lithuanian|lietuvių|lt';
  LocaleEntries[69]  := 'Latvian|latviešu|lv';
  LocaleEntries[70]  := 'Maori|Māori|mi';
  LocaleEntries[71]  := 'Macedonian|македонски|mk';
  LocaleEntries[72]  := 'Malayalam|മലയാളം|ml';
  LocaleEntries[73]  := 'Mongolian|монгол|mn';
  LocaleEntries[74]  := 'Marathi|मराठी|mr';
  LocaleEntries[75]  := 'Malay|Melayu|ms';
  LocaleEntries[76]  := 'Maltese|Malti|mt';
  LocaleEntries[77]  := 'Norwegian Bokmal|norsk bokmål|nb';
  LocaleEntries[78]  := 'Nepali|नेपाली|ne';
  LocaleEntries[79]  := 'Dutch|Nederlands|nl';
  LocaleEntries[80]  := 'Dutch (Belgium)|Nederlands (België)|nl-BE';
  LocaleEntries[81]  := 'Norwegian Nynorsk|norsk nynorsk|nn';
  LocaleEntries[82]  := 'Sesotho sa Leboa|Sesotho sa Leboa|nso';
  LocaleEntries[83]  := 'Odia|ଓଡ଼ିଆ|or';
  LocaleEntries[84]  := 'Punjabi|ਪੰਜਾਬੀ|pa';
  LocaleEntries[85]  := 'Punjabi (Arabic)|پنجابی (عربی)|pa-Arab';
  LocaleEntries[86]  := 'Polish|polski|pl';
  LocaleEntries[87]  := 'Dari|دری|prs';
  LocaleEntries[88]  := 'Pashto|پښتو|ps';
  LocaleEntries[89]  := 'Portuguese|português|pt';
  LocaleEntries[90]  := 'Portuguese (Brazil)|português (Brasil)|pt-BR';
  LocaleEntries[91]  := 'Quechua|Runasimi|qu';
  LocaleEntries[92]  := 'Kiche|Kʼicheʼ|quc';
  LocaleEntries[93]  := 'Romanian|română|ro';
  LocaleEntries[94]  := 'Russian|русский|ru';
  LocaleEntries[95]  := 'Kinyarwanda|Kinyarwanda|rw';
  LocaleEntries[96]  := 'Sindhi|سنڌي|sd';
  LocaleEntries[97]  := 'Sinhala|සිංහල|si';
  LocaleEntries[98]  := 'Slovak|slovenčina|sk';
  LocaleEntries[99]  := 'Slovenian|slovenščina|sl';
  LocaleEntries[100]  := 'Albanian|shqip|sq';
  LocaleEntries[101]  := 'Serbian|српски|sr';
  LocaleEntries[102]  := 'Serbian (Cyrillic)|српски (ћирилица)|sr-Cyrl';
  LocaleEntries[103]  := 'Swedish|svenska|sv';
  LocaleEntries[104]  := 'Swahili|Kiswahili|sw';
  LocaleEntries[105]  := 'Tamil|தமிழ்|ta';
  LocaleEntries[106]  := 'Telugu|తెలుగు|te';
  LocaleEntries[107]  := 'Thai|ไทย|th';
  LocaleEntries[108]  := 'Tigrinya|ትግርኛ|ti';
  LocaleEntries[109]  := 'Turkmen|türkmen dili|tk';
  LocaleEntries[110]  := 'Setswana|Setswana|tn';
  LocaleEntries[111]  := 'Turkish|Türkçe|tr';
  LocaleEntries[112]  := 'Tatar|татар|tt';
  LocaleEntries[113]  := 'Uyghur|ئۇيغۇرچە|ug';
  LocaleEntries[114]  := 'Ukrainian|українська|uk';
  LocaleEntries[115]  := 'Urdu|اردو|ur';
  LocaleEntries[116]  := 'Uzbek|o''zbek|uz';
  LocaleEntries[117]  := 'Vietnamese|Tiếng Việt|vi';
  LocaleEntries[118]  := 'Wolof|Wolof|wo';
  LocaleEntries[119]  := 'Xhosa|IsiXhosa|xh';
  LocaleEntries[120]  := 'Yoruba|Èdè Yorùbá|yo';
  LocaleEntries[121]  := 'Chinese (Simplified)|中文（简体）|zh-Hans';
  LocaleEntries[122]  := 'Chinese (Traditional)|中文（繁體）|zh-Hant';
  LocaleEntries[123]  := 'Zulu|isiZulu|zu';
end;

function InitializeSetup(): Boolean;
var
  ResumeStatePath: String;
begin
  Result := True;

  GInstallMode           := True;
  GInstallScopeAllUsers  := IsAdminInstallMode;
  GDesktop               := True;
  GStartMenu             := True;
  GPortablePath          := '';
  GInstallPath           := '';
  GLocaleCode            := 'en';
  GSetupCompleted        := False;
  GResumeInstallFlow     := False;
  GProgrammaticClose     := False;
  GUpdateFlow            := False;
  GUpdateRelaunchPath    := '';
  GUpdateTargetDir       := '';

  LoadUpdateFlowState;

  ResumeStatePath := GetCommandLineSwitchValue('RESUMEINSTALL');
  GResumeInstallFlow := ResumeStatePath <> '';
  if (not RunSetupFreshnessCheck) then
  begin
    Result := False;
    Exit;
  end;

  if ResumeStatePath = '' then
    Exit;

  if not FileExists(ResumeStatePath) then
  begin
    MsgBox('Installer resume state file not found: ' + ResumeStatePath, mbError, MB_OK);
    Result := False;
    Exit;
  end;

  if not LoadInstallResumeState(ResumeStatePath) then
  begin
    MsgBox('Setup could not load the elevated install state: ' + ResumeStatePath, mbError, MB_OK);
    Result := False;
    Exit;
  end;

  DeleteFile(ResumeStatePath);
end;

procedure InitializeWizard;
begin
  InitLocaleEntries;
  CreatePageLanguage;
  CreatePageMode;
  CreatePageScope;
  CreatePageLocation;
  CreatePageShortcuts;
  CreatePageFinish;

  WizardForm.Caption := GetSetupString('WizardTitle.Default');

  if GUpdateFlow then
  begin
    WizardForm.Caption := 'Updating Baseline';
    if Assigned(CbLaunch) then
      CbLaunch.Checked := True;
    if Assigned(DirEdit) and (GInstallPath <> '') then
      DirEdit.Text := GInstallPath;
    if GInstallPath <> '' then
      WizardForm.DirEdit.Text := GInstallPath;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;

  if GUpdateFlow and ((PageID = PageLanguage.ID) or (PageID = PageMode.ID) or (PageID = PageScope.ID) or (PageID = PageLocation.ID) or (PageID = PageShortcuts.ID) or (PageID = PageFinish.ID)) then begin Result := True; Exit; end;
  if GResumeInstallFlow and ((PageID = PageLanguage.ID) or (PageID = PageMode.ID) or (PageID = PageScope.ID)) then begin Result := True; Exit; end;
  if (PageID = PageLanguage.ID) or (PageID = PageMode.ID) then Exit;
  if PageID = PageScope.ID then begin Result := (not GInstallMode) or IsAdminInstallMode; Exit; end;

  if PageID = PageLocation.ID then begin Result := not GInstallMode; Exit; end;
  if PageID = PageShortcuts.ID then begin Result := not GInstallMode; Exit; end;

  if PageID = wpSelectDir   then begin Result := True; Exit; end;
  if PageID = wpSelectTasks then begin Result := True; Exit; end;
  if PageID = wpReady       then begin Result := True; Exit; end;
  if PageID = wpFinished    then begin Result := True; Exit; end;
  if PageID = wpInfoBefore  then begin Result := True; Exit; end;
  if PageID = wpInfoAfter   then begin Result := True; Exit; end;
  if PageID = wpPassword    then begin Result := True; Exit; end;
  if PageID = wpLicense     then begin Result := True; Exit; end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = PageLanguage.ID then
  begin
    if (LangList.ItemIndex < 0) or (LangList.ItemIndex >= LangVisibleCount) then
    begin
      MsgBox('Please choose a language.', mbError, MB_OK);
      Result := False;
      Exit;
    end;

    GLocaleCode := LocaleCode(LangVisibleEntries[LangList.ItemIndex]);
  end;

  if CurPageID = PageMode.ID then
  begin
    GInstallMode := RbInstall.Checked;
    if GInstallMode then
      WizardForm.Caption := GetSetupString('WizardTitle.Install')
    else
      WizardForm.Caption := GetSetupString('WizardTitle.Portable');
    if (not GInstallMode) and IsAdminInstallMode then
    begin
      MsgBox(GetSetupString('PortableMode.AllUsersError'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;

  if CurPageID = PageScope.ID then
  begin
    GInstallScopeAllUsers := RbAllUsers.Checked;
    if GInstallScopeAllUsers and (not IsAdminInstallMode) then
    begin
      RestartInstallForAllUsers;
      Result := False;
      Exit;
    end;
  end;

  if CurPageID = PageLocation.ID then
  begin
    GInstallPath := DirEdit.Text;
    if GInstallPath = '' then
    begin
      MsgBox(GetSetupString('InstallPath.EmptyError'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
    WizardForm.DirEdit.Text := GInstallPath;
  end;

  if CurPageID = PageShortcuts.ID then
  begin
    GDesktop   := CbDesktop.Checked;
    GStartMenu := CbStartMenu.Checked;
  end;

  if CurPageID = PageFinish.ID then
  begin
    if GSetupCompleted and CbLaunch.Checked then
      LaunchBaseline;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';

  if (not GInstallMode) and IsAdminInstallMode then
    Result := GetSetupString('PortableMode.AllUsersError');
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if GProgrammaticClose then
  begin
    Cancel := False;
    Confirm := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  L: TNewStaticText;
  Msg: String;
begin
  if CurStep = ssPostInstall then
  begin
    if not GInstallMode then
      ExtractPortable;

    SeedLocale;
    if GInstallMode then
      GInstallPath := ExpandConstant('{app}');
    GSetupCompleted := True;

    if GInstallMode then
      Msg := GetSetupString('FinishMsg.Install') + #13#10 + GInstallPath
    else
      Msg := GetSetupString('FinishMsg.Portable') + #13#10 + GPortablePath + #13#10 + #13#10 +
             GetSetupString('FinishMsg.PortableShortcut');

    L := TNewStaticText(PageFinish.Surface.FindComponent('FinishMsg'));
    if Assigned(L) then
      L.Caption := Msg;

    if GUpdateFlow then
      LaunchBaseline;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  // When leaving the language page (i.e. arriving at the first post-language
  // page), re-render all subsequent pages with the confirmed locale.
  if CurPageID = PageMode.ID then
  begin
    ApplyPageTranslations;
    ApplyModeAvailability;
  end;

  // Keep the Location page DirEdit in sync with the install scope.
  // - All-users / admin:    C:\Program Files\Baseline  (default)
  // - Current-user / non-admin: %LocalAppData%\Programs\Baseline
  if CurPageID = PageLocation.ID then
  begin
    if Assigned(DirEdit) then
    begin
      if GUpdateFlow and (GInstallPath <> '') then
        DirEdit.Text := GInstallPath
      else if IsAdminInstallMode then
        DirEdit.Text := ExpandConstant('{pf}') + '\Baseline'
      else
        DirEdit.Text := ExpandConstant('{localappdata}') + '\Programs\Baseline';
    end;
  end;

  UpdateNextButtonCaption(CurPageID);
end;
