unit code_decl_to_abi_registry;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.FPC.GenericList,
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings, Z.Parsing,
  Z.ListEngine,
  Z.UnicodeMixedLib,
  Z.Pascal_Func_Model;

type
  TGenerateFunc = function(Model: TPascal_Func_Model): TPascalStringList;

  TArtifactSide = (asService, asCall, asBoth);

  TArtifactKind = (
    akServiceCode,
    akServiceHeader,
    akServiceReadme,
    akCallCode,
    akCallHeader,
    akCallReadme,
    akCallHtml,
    akTestCode,
    akTestReadme,
    akBuildScript,
    akBuildMain
  );

  TArtifactKindSet = set of TArtifactKind;
  TArtifactKindCounts = array[TArtifactKind] of Integer;

  TCodeGenEntry = record
    LanguageID: TPascalString;
    DisplayName: TPascalString;
    Side: TArtifactSide;
    Kind: TArtifactKind;
    Suffix: TPascalString;
    FixedName: Boolean;
    Extension: TPascalString;
    Func: TGenerateFunc;
  end;
  PCodeGenEntry = ^TCodeGenEntry;
  TCodeGenEntryArray = array of PCodeGenEntry;

  TLanguageInfo = record
    LanguageID: TPascalString;
    DisplayName: TPascalString;
    HasService: Boolean;
    HasCall: Boolean;
    HasBoth: Boolean;
    ArtifactCount: Integer;
    ServiceCount: Integer;
    CallCount: Integer;
    Kinds: TArtifactKindSet;
    KindCounts: TArtifactKindCounts;
    Extensions: TPascalString;
  end;

  TGeneratorKind = (
    gkService,
    gkCall,
    gkDoc,
    gkTest,
    gkProject,
    gkScript,
    gkPs1,
    gkOther
  );
  TGeneratorKinds = set of TGeneratorKind;

const
  gkServiceDoc = gkDoc;
  gkCallDoc = gkDoc;

type
  TGeneratorEntry = record
    ModuleId: TPascalString;
    FileNameTemplate: TPascalString;
    Kind: TGeneratorKind;
    Description: TPascalString;
    Func: TGenerateFunc;
  end;
  PGeneratorEntry = ^TGeneratorEntry;
  TGeneratorEntryArray = array of PGeneratorEntry;

  TCodeGenRegistry = class(TCore_Object_Intermediate)
  private
    FEntries: TGenericsList<PCodeGenEntry>;
    FViews: TGenericsList<PGeneratorEntry>;
    FCritical: TCritical;
    function MakeExtension(const Suffix: TPascalString;
      FixedName: Boolean): TPascalString;
    function InternalAdd(const Entry: TCodeGenEntry;
      const LegacyModuleId, LegacyFileNameTemplate: TPascalString;
      LegacyKind: TGeneratorKind;
      const LegacyDescription: TPascalString;
      LegacyFunc: TGenerateFunc): PGeneratorEntry;
  public
    constructor Create;
    destructor Destroy; override;

    function Add(const Entry: TCodeGenEntry): PCodeGenEntry;
    function AddLegacy(const ModuleId, FileNameTemplate: TPascalString;
      Kind: TGeneratorKind;
      const Description: TPascalString;
      Func: TGenerateFunc): PGeneratorEntry;

    function Count: Integer;
    function GetEntry(Index: Integer): PGeneratorEntry;
    function GetCodeGenEntry(Index: Integer): PCodeGenEntry;

    function FindByTemplate(const Template: TPascalString): PGeneratorEntry;
    function FindByExtension(const Ext: TPascalString): TGeneratorEntryArray;
    function FindByKind(Kind: TGeneratorKind): TGeneratorEntryArray;
    function FindByKinds(const Kinds: TGeneratorKinds): TGeneratorEntryArray;
    function FindByModule(const ModuleId: TPascalString): TGeneratorEntryArray;
    function FindByModuleAndKind(const ModuleId: TPascalString;
      Kind: TGeneratorKind): TGeneratorEntryArray;
    function FindByModuleAndKinds(const ModuleId: TPascalString;
      const Kinds: TGeneratorKinds): TGeneratorEntryArray;

    function FindByLanguage(const LangID: TPascalString): TCodeGenEntryArray;
    function FindByLanguageAndSide(const LangID: TPascalString;
      Side: TArtifactSide): TCodeGenEntryArray;
    function FindByLanguageAndArtifact(const LangID: TPascalString;
      Kind: TArtifactKind): TCodeGenEntryArray;
    function HasLanguage(const LangID: TPascalString): Boolean;
    function FindLanguageByExtension(const Ext: TPascalString): TPascalString;
    function GetLanguageInfo(const LangID: TPascalString): TLanguageInfo;

    function GetLanguageCount: Integer;
    function GetLanguageID(Index: Integer): TPascalString;
    function GetAllLanguageIDs(const Delim: string): string;
    function GetAllExtensions(const Delim: string): string;
  end;

var
  CodeGenRegistry: TCodeGenRegistry = nil;

procedure RegisterGenerator(const ModuleId, FileNameTemplate: string;
  Kind: TGeneratorKind; const Description: string; Func: TGenerateFunc);

function FindGeneratorByTemplate(const FileNameTemplate: string): PGeneratorEntry;
function FindGeneratorsByExtension(const Extension: string): TGeneratorEntryArray;
function FindGeneratorsByKind(Kind: TGeneratorKind): TGeneratorEntryArray;
function FindGeneratorsByKinds(const Kinds: TGeneratorKinds): TGeneratorEntryArray;
function GetGeneratorsByModule(const ModuleId: string): TGeneratorEntryArray;
function GetGeneratorsByModuleAndKind(const ModuleId: string;
  Kind: TGeneratorKind): TGeneratorEntryArray;
function GetGeneratorsByModuleAndKinds(const ModuleId: string;
  const Kinds: TGeneratorKinds): TGeneratorEntryArray;

function GetGeneratorCount: integer;
function GetGeneratorByIndex(Index: integer): PGeneratorEntry;

function GetRegisteredExtensions: TPascalStringList;
function GetRegisteredModules: TPascalStringList;
function GetRegisteredKinds: TGeneratorKinds;

function KindToText(Kind: TGeneratorKind): string;
function KindFromText(const Text: string; out Kind: TGeneratorKind): Boolean;

function IsSourceKind(Kind: TGeneratorKind): Boolean;
function IsDocKind(Kind: TGeneratorKind): Boolean;
function IsScriptKind(Kind: TGeneratorKind): Boolean;
function IsBuildKind(Kind: TGeneratorKind): Boolean;
function IsTestKind(Kind: TGeneratorKind): Boolean;

function ResolveFileName(const Template, UnitName: string): string;
function TemplateExtension(const Template: string): string;
function TemplateBaseName(const Template: string): string;
function TemplateDirectory(const Template: string): string;
function EnsureDirectoryForFile(const FileName: string): Boolean;
function ResolveRelativePath(const BaseDir, FullPath: string): string;
function InvokeGenerator(Entry: PGeneratorEntry;
  Model: TPascal_Func_Model): TPascalStringList;

procedure RegisterCodeGenEntry(
  const LanguageID, DisplayName: TPascalString;
  const Side: TArtifactSide;
  const Kind: TArtifactKind;
  const Suffix: TPascalString;
  const FixedName: Boolean;
  const Func: TGenerateFunc);

function Side_Matches_Requested(const EntrySide: TArtifactSide;
  const AsCall: Boolean): Boolean;
function Side_Has_Service(const Side: TArtifactSide): Boolean;
function Side_Has_Call(const Side: TArtifactSide): Boolean;
function Side_To_String(const Side: TArtifactSide): string;

function ArtifactKind_Is_Readme(const Kind: TArtifactKind): Boolean;
function ArtifactKind_Is_Code(const Kind: TArtifactKind): Boolean;
function ArtifactKind_Is_Header(const Kind: TArtifactKind): Boolean;
function ArtifactKind_Is_Html(const Kind: TArtifactKind): Boolean;
function ArtifactKind_Is_Test(const Kind: TArtifactKind): Boolean;
function ArtifactKind_Is_Build(const Kind: TArtifactKind): Boolean;
function ArtifactKind_To_String(const Kind: TArtifactKind): string;
function ArtifactKind_To_Short(const Kind: TArtifactKind): string;

function LegacyKind_To_Side(Kind: TGeneratorKind): TArtifactSide;
function LegacyKind_To_Artifact(Kind: TGeneratorKind): TArtifactKind;
function Artifact_To_LegacyKind(Side: TArtifactSide;
  Kind: TArtifactKind): TGeneratorKind;

implementation

uses
  SysUtils;

function Side_Matches_Requested(const EntrySide: TArtifactSide;
  const AsCall: Boolean): Boolean;
begin
  if EntrySide = TArtifactSide.asBoth then
    Result := True
  else if AsCall then
    Result := (EntrySide = TArtifactSide.asCall)
  else
    Result := (EntrySide = TArtifactSide.asService);
end;

function Side_Has_Service(const Side: TArtifactSide): Boolean;
begin
  Result := (Side = TArtifactSide.asService) or (Side = TArtifactSide.asBoth);
end;

function Side_Has_Call(const Side: TArtifactSide): Boolean;
begin
  Result := (Side = TArtifactSide.asCall) or (Side = TArtifactSide.asBoth);
end;

function Side_To_String(const Side: TArtifactSide): string;
begin
  case Side of
    TArtifactSide.asService: Result := 'service';
    TArtifactSide.asCall:    Result := 'call';
    TArtifactSide.asBoth:    Result := 'both';
  else
    Result := 'unknown';
  end;
end;

function ArtifactKind_Is_Readme(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akServiceReadme, akCallReadme, akTestReadme];
end;

function ArtifactKind_Is_Code(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akServiceCode, akServiceHeader, akCallCode,
    akCallHeader, akTestCode, akCallHtml, akBuildScript, akBuildMain];
end;

function ArtifactKind_Is_Header(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akServiceHeader, akCallHeader];
end;

function ArtifactKind_Is_Html(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind = akCallHtml;
end;

function ArtifactKind_Is_Test(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akTestCode, akTestReadme];
end;

function ArtifactKind_Is_Build(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akBuildScript, akBuildMain];
end;

function ArtifactKind_To_String(const Kind: TArtifactKind): string;
begin
  case Kind of
    akServiceCode:   Result := 'service-code';
    akServiceHeader: Result := 'service-header';
    akServiceReadme: Result := 'service-readme';
    akCallCode:      Result := 'call-code';
    akCallHeader:    Result := 'call-header';
    akCallReadme:    Result := 'call-readme';
    akCallHtml:      Result := 'call-html';
    akTestCode:      Result := 'test-code';
    akTestReadme:    Result := 'test-readme';
    akBuildScript:   Result := 'build-script';
    akBuildMain:     Result := 'build-main';
  else
    Result := 'unknown';
  end;
end;

function ArtifactKind_To_Short(const Kind: TArtifactKind): string;
begin
  case Kind of
    akServiceCode:   Result := 'svc';
    akServiceHeader: Result := 'svh';
    akServiceReadme: Result := 'svr';
    akCallCode:      Result := 'clc';
    akCallHeader:    Result := 'clh';
    akCallReadme:    Result := 'clr';
    akCallHtml:      Result := 'cht';
    akTestCode:      Result := 'tst';
    akTestReadme:    Result := 'tsr';
    akBuildScript:   Result := 'bds';
    akBuildMain:     Result := 'bdm';
  else
    Result := 'unk';
  end;
end;

function LegacyKind_To_Side(Kind: TGeneratorKind): TArtifactSide;
begin
  case Kind of
    gkService: Result := TArtifactSide.asService;
    gkCall:    Result := TArtifactSide.asCall;
    else       Result := TArtifactSide.asBoth;
  end;
end;

function LegacyKind_To_Artifact(Kind: TGeneratorKind): TArtifactKind;
begin
  case Kind of
    gkService: Result := akServiceCode;
    gkCall:    Result := akCallCode;
    gkDoc:     Result := akServiceReadme;
    gkTest:    Result := akTestCode;
    gkProject: Result := akBuildScript;
    gkScript:  Result := akBuildScript;
    gkPs1:     Result := akBuildScript;
    else       Result := akTestCode;
  end;
end;

function Artifact_To_LegacyKind(Side: TArtifactSide;
  Kind: TArtifactKind): TGeneratorKind;
begin
  case Kind of
    akServiceCode:   Result := gkService;
    akServiceHeader: Result := gkService;
    akServiceReadme: Result := gkDoc;
    akCallCode:      Result := gkCall;
    akCallHeader:    Result := gkCall;
    akCallReadme:    Result := gkDoc;
    akCallHtml:      Result := gkCall;
    akTestCode:      Result := gkTest;
    akTestReadme:    Result := gkDoc;
    akBuildScript:   Result := gkProject;
    akBuildMain:     Result := gkProject;
    else             Result := gkOther;
  end;
end;

constructor TCodeGenRegistry.Create;
begin
  inherited Create;
  FEntries := TGenericsList<PCodeGenEntry>.Create;
  FViews := TGenericsList<PGeneratorEntry>.Create;
  FCritical := TCritical.Create('code_decl_to_abi_registry');
end;

destructor TCodeGenRegistry.Destroy;
var
  i: Integer;
begin
  if FCritical <> nil then
    FCritical.Acquire;
  try
    if FEntries <> nil then
    begin
      for i := 0 to FEntries.Count - 1 do
        if FEntries[i] <> nil then
          Dispose(FEntries[i]);
      FEntries.Clear;
    end;
    if FViews <> nil then
    begin
      for i := 0 to FViews.Count - 1 do
        if FViews[i] <> nil then
          Dispose(FViews[i]);
      FViews.Clear;
    end;
  finally
    if FCritical <> nil then
      FCritical.Release;
  end;
  DisposeObject(FEntries);
  DisposeObject(FViews);
  DisposeObject(FCritical);
  inherited Destroy;
end;

function TCodeGenRegistry.MakeExtension(const Suffix: TPascalString;
  FixedName: Boolean): TPascalString;
var
  Ext: string;
begin
  if FixedName then
  begin
    Result := '';
    Exit;
  end;
  Ext := LowerCase(ExtractFileExt(Suffix.Text));
  Result := Ext;
end;

function TCodeGenRegistry.InternalAdd(const Entry: TCodeGenEntry;
  const LegacyModuleId, LegacyFileNameTemplate: TPascalString;
  LegacyKind: TGeneratorKind;
  const LegacyDescription: TPascalString;
  LegacyFunc: TGenerateFunc): PGeneratorEntry;
var
  ce: PCodeGenEntry;
  ve: PGeneratorEntry;
begin
  Result := nil;
  FCritical.Acquire;
  try
    New(ce);
    ce^ := Entry;
    if ce^.Extension.Len = 0 then
      ce^.Extension := MakeExtension(ce^.Suffix, ce^.FixedName);
    FEntries.Add(ce);

    New(ve);
    ve^.ModuleId := LegacyModuleId;
    ve^.FileNameTemplate := LegacyFileNameTemplate;
    ve^.Kind := LegacyKind;
    ve^.Description := LegacyDescription;
    ve^.Func := LegacyFunc;
    FViews.Add(ve);

    Result := ve;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.AddLegacy(const ModuleId,
  FileNameTemplate: TPascalString; Kind: TGeneratorKind;
  const Description: TPascalString; Func: TGenerateFunc): PGeneratorEntry;
var
  ce: TCodeGenEntry;
  tpl, suffix: TPascalString;
  xxx_pos: integer;
  fixed_name: Boolean;
begin
  Result := nil;

  tpl := FileNameTemplate;
  xxx_pos := tpl.GetPos('xxx', 1);
  if xxx_pos > 0 then
  begin
    suffix := tpl.GetString(xxx_pos + 3, tpl.Len + 1);
    fixed_name := False;
  end
  else
  begin
    suffix := tpl;
    fixed_name := True;
  end;

  ce.LanguageID := ModuleId;
  ce.DisplayName := Description;
  ce.Side := LegacyKind_To_Side(Kind);
  ce.Kind := LegacyKind_To_Artifact(Kind);
  ce.Suffix := suffix;
  ce.FixedName := fixed_name;
  ce.Extension := '';
  ce.Func := Func;

  Result := InternalAdd(ce, ModuleId, FileNameTemplate,
    Kind, Description, Func);
end;

function TCodeGenRegistry.Add(const Entry: TCodeGenEntry): PCodeGenEntry;
var
  ce: PCodeGenEntry;
  ve: PGeneratorEntry;
  legacy_tpl: TPascalString;
  legacy_kind: TGeneratorKind;
begin
  Result := nil;
  FCritical.Acquire;
  try
    New(ce);
    ce^ := Entry;
    if ce^.Extension.Len = 0 then
      ce^.Extension := MakeExtension(ce^.Suffix, ce^.FixedName);
    FEntries.Add(ce);

    if ce^.FixedName then
      legacy_tpl := ce^.Suffix
    else
      legacy_tpl := 'xxx' + ce^.Suffix;
    legacy_kind := Artifact_To_LegacyKind(ce^.Side, ce^.Kind);

    New(ve);
    ve^.ModuleId := ce^.LanguageID;
    ve^.FileNameTemplate := legacy_tpl;
    ve^.Kind := legacy_kind;
    ve^.Description := ce^.DisplayName;
    ve^.Func := ce^.Func;
    FViews.Add(ve);

    Result := ce;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.Count: Integer;
begin
  FCritical.Acquire;
  try
    Result := FEntries.Count;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.GetEntry(Index: Integer): PGeneratorEntry;
begin
  Result := nil;
  FCritical.Acquire;
  try
    if (Index >= 0) and (Index < FViews.Count) then
      Result := FViews[Index];
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.GetCodeGenEntry(Index: Integer): PCodeGenEntry;
begin
  Result := nil;
  FCritical.Acquire;
  try
    if (Index >= 0) and (Index < FEntries.Count) then
      Result := FEntries[Index];
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByTemplate(
  const Template: TPascalString): PGeneratorEntry;
var
  i: integer;
  v: PGeneratorEntry;
begin
  Result := nil;
  FCritical.Acquire;
  try
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if (v <> nil) and v^.FileNameTemplate.Same(Template) then
      begin
        Result := v;
        Exit;
      end;
    end;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByExtension(
  const Ext: TPascalString): TGeneratorEntryArray;
var
  i, n: integer;
  v: PGeneratorEntry;
  ext_lower: string;
begin
  Result := nil;
  SetLength(Result, 0);
  ext_lower := LowerCase(Ext.Text);
  if ext_lower = '' then Exit;
  FCritical.Acquire;
  try
    SetLength(Result, FViews.Count);
    n := 0;
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if v = nil then Continue;
      if LowerCase(TemplateExtension(v^.FileNameTemplate.Text)) = ext_lower then
      begin
        Result[n] := v;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByKind(
  Kind: TGeneratorKind): TGeneratorEntryArray;
var
  i, n: integer;
  v: PGeneratorEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FViews.Count);
    n := 0;
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if (v <> nil) and (v^.Kind = Kind) then
      begin
        Result[n] := v;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByKinds(
  const Kinds: TGeneratorKinds): TGeneratorEntryArray;
var
  i, n: integer;
  v: PGeneratorEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FViews.Count);
    n := 0;
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if (v <> nil) and (v^.Kind in Kinds) then
      begin
        Result[n] := v;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByModule(
  const ModuleId: TPascalString): TGeneratorEntryArray;
var
  i, n: integer;
  v: PGeneratorEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FViews.Count);
    n := 0;
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if (v <> nil) and v^.ModuleId.Same(ModuleId) then
      begin
        Result[n] := v;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByModuleAndKind(const ModuleId: TPascalString;
  Kind: TGeneratorKind): TGeneratorEntryArray;
var
  i, n: integer;
  v: PGeneratorEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FViews.Count);
    n := 0;
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if (v <> nil) and v^.ModuleId.Same(ModuleId) and (v^.Kind = Kind) then
      begin
        Result[n] := v;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByModuleAndKinds(const ModuleId: TPascalString;
  const Kinds: TGeneratorKinds): TGeneratorEntryArray;
var
  i, n: integer;
  v: PGeneratorEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FViews.Count);
    n := 0;
    for i := 0 to FViews.Count - 1 do
    begin
      v := FViews[i];
      if (v <> nil) and v^.ModuleId.Same(ModuleId) and (v^.Kind in Kinds) then
      begin
        Result[n] := v;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByLanguage(
  const LangID: TPascalString): TCodeGenEntryArray;
var
  i, n: integer;
  e: PCodeGenEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FEntries.Count);
    n := 0;
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if (e <> nil) and e^.LanguageID.Same(LangID) then
      begin
        Result[n] := e;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByLanguageAndSide(const LangID: TPascalString;
  Side: TArtifactSide): TCodeGenEntryArray;
var
  i, n: integer;
  e: PCodeGenEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FEntries.Count);
    n := 0;
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if (e <> nil) and e^.LanguageID.Same(LangID) and (e^.Side = Side) then
      begin
        Result[n] := e;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindByLanguageAndArtifact(const LangID: TPascalString;
  Kind: TArtifactKind): TCodeGenEntryArray;
var
  i, n: integer;
  e: PCodeGenEntry;
begin
  Result := nil;
  SetLength(Result, 0);
  FCritical.Acquire;
  try
    SetLength(Result, FEntries.Count);
    n := 0;
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if (e <> nil) and e^.LanguageID.Same(LangID) and (e^.Kind = Kind) then
      begin
        Result[n] := e;
        Inc(n);
      end;
    end;
    SetLength(Result, n);
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.HasLanguage(const LangID: TPascalString): Boolean;
var
  i: integer;
  e: PCodeGenEntry;
begin
  Result := False;
  if LangID.Len = 0 then Exit;
  FCritical.Acquire;
  try
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if (e <> nil) and e^.LanguageID.Same(LangID) then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.FindLanguageByExtension(
  const Ext: TPascalString): TPascalString;
var
  i: integer;
  e: PCodeGenEntry;
  lext: string;
begin
  Result := '';
  lext := LowerCase(Ext.Text);
  if lext = '' then Exit;
  FCritical.Acquire;
  try
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if e = nil then Continue;
      if (e^.Extension.Len > 0) and (e^.Extension.Text = lext) then
      begin
        Result := e^.LanguageID;
        Exit;
      end;
    end;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.GetLanguageInfo(
  const LangID: TPascalString): TLanguageInfo;
var
  i: integer;
  e: PCodeGenEntry;
  ext_list: TPascalString;
  k: TArtifactKind;
  found: Boolean;
  prefix, joinStr: TPascalString;
begin
  Result.LanguageID := LangID;
  Result.DisplayName := '';
  Result.HasService := False;
  Result.HasCall := False;
  Result.HasBoth := False;
  Result.ArtifactCount := 0;
  Result.ServiceCount := 0;
  Result.CallCount := 0;
  Result.Kinds := [];
  for k := Low(TArtifactKind) to High(TArtifactKind) do
    Result.KindCounts[k] := 0;
  Result.Extensions := '';

  ext_list := '';
  FCritical.Acquire;
  try
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if e = nil then Continue;
      if not e^.LanguageID.Same(LangID) then Continue;

      if Result.DisplayName.Len = 0 then
        Result.DisplayName := e^.DisplayName;

      Inc(Result.ArtifactCount);
      Result.Kinds := Result.Kinds + [e^.Kind];
      Inc(Result.KindCounts[e^.Kind]);

      case e^.Side of
        TArtifactSide.asService: Result.HasService := True;
        TArtifactSide.asCall:    Result.HasCall := True;
        TArtifactSide.asBoth:    Result.HasBoth := True;
      end;

      if e^.Kind in [akServiceCode, akServiceHeader, akServiceReadme,
        akBuildScript] then
        Inc(Result.ServiceCount);
      if e^.Kind in [akCallCode, akCallHeader, akCallReadme, akCallHtml,
        akBuildMain] then
        Inc(Result.CallCount);

      if e^.Extension.Len > 0 then
      begin
        found := False;
        if ext_list.Len > 0 then
        begin
          prefix := '|' + e^.Extension + '|';
          if (('|' + ext_list + '|').GetPos(prefix) > 0) then
            found := True;
        end
        else if ext_list.Same(e^.Extension) then
          found := True;
        if not found then
        begin
          if ext_list.Len > 0 then
            ext_list := ext_list + '|';
          ext_list := ext_list + e^.Extension;
        end;
      end;
    end;
  finally
    FCritical.Release;
  end;

  if ext_list.Len > 0 then
  begin
    joinStr := ext_list;
    joinStr := joinStr.ReplaceChar('|', ' ');
    Result.Extensions := joinStr;
  end;
end;

function TCodeGenRegistry.GetLanguageCount: Integer;
var
  i, n: integer;
  e: PCodeGenEntry;
  found: Boolean;
  j: integer;
begin
  Result := 0;
  FCritical.Acquire;
  try
    n := 0;
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if e = nil then Continue;
      found := False;
      for j := 0 to i - 1 do
      begin
        if (FEntries[j] <> nil) and FEntries[j]^.LanguageID.Same(e^.LanguageID) then
        begin
          found := True;
          Break;
        end;
      end;
      if not found then Inc(n);
    end;
    Result := n;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.GetLanguageID(Index: Integer): TPascalString;
var
  i, n: integer;
  e: PCodeGenEntry;
  found: Boolean;
  j: integer;
begin
  Result := '';
  FCritical.Acquire;
  try
    n := 0;
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if e = nil then Continue;
      found := False;
      for j := 0 to i - 1 do
      begin
        if (FEntries[j] <> nil) and FEntries[j]^.LanguageID.Same(e^.LanguageID) then
        begin
          found := True;
          Break;
        end;
      end;
      if not found then
      begin
        if n = Index then
        begin
          Result := e^.LanguageID;
          Exit;
        end;
        Inc(n);
      end;
    end;
  finally
    FCritical.Release;
  end;
end;

function TCodeGenRegistry.GetAllLanguageIDs(const Delim: string): string;
var
  i, n: integer;
  e: PCodeGenEntry;
  found: Boolean;
  j: integer;
  s: string;
begin
  s := '';
  FCritical.Acquire;
  try
    n := 0;
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if e = nil then Continue;
      found := False;
      for j := 0 to i - 1 do
      begin
        if (FEntries[j] <> nil) and FEntries[j]^.LanguageID.Same(e^.LanguageID) then
        begin
          found := True;
          Break;
        end;
      end;
      if not found then
      begin
        if s <> '' then s := s + Delim;
        s := s + e^.LanguageID.Text;
        Inc(n);
      end;
    end;
  finally
    FCritical.Release;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetAllExtensions(const Delim: string): string;
var
  i: integer;
  e: PCodeGenEntry;
  seen: TPascalString;
  found: Boolean;
  s: string;
  search: TPascalString;
begin
  seen := '';
  s := '';
  FCritical.Acquire;
  try
    for i := 0 to FEntries.Count - 1 do
    begin
      e := FEntries[i];
      if (e = nil) or (e^.Extension.Len = 0) then Continue;
      found := False;
      if seen.Len > 0 then
      begin
        search := '|' + e^.Extension + '|';
        if (('|' + seen + '|').GetPos(search) > 0) then
          found := True;
      end
      else if seen.Same(e^.Extension) then
        found := True;
      if found then Continue;
      if seen.Len > 0 then
        seen := seen + '|';
      seen := seen + e^.Extension;
      if s <> '' then s := s + Delim;
      s := s + e^.Extension.Text;
    end;
  finally
    FCritical.Release;
  end;
  Result := s;
end;

procedure RegisterGenerator(const ModuleId, FileNameTemplate: string;
  Kind: TGeneratorKind; const Description: string; Func: TGenerateFunc);
begin
  if CodeGenRegistry = nil then Exit;
  CodeGenRegistry.AddLegacy(ModuleId, FileNameTemplate, Kind, Description, Func);
end;

function FindGeneratorByTemplate(
  const FileNameTemplate: string): PGeneratorEntry;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByTemplate(TPascalString(FileNameTemplate));
end;

function FindGeneratorsByExtension(
  const Extension: string): TGeneratorEntryArray;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByExtension(TPascalString(Extension));
end;

function FindGeneratorsByKind(Kind: TGeneratorKind): TGeneratorEntryArray;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByKind(Kind);
end;

function FindGeneratorsByKinds(
  const Kinds: TGeneratorKinds): TGeneratorEntryArray;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByKinds(Kinds);
end;

function GetGeneratorsByModule(const ModuleId: string): TGeneratorEntryArray;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByModule(TPascalString(ModuleId));
end;

function GetGeneratorsByModuleAndKind(const ModuleId: string;
  Kind: TGeneratorKind): TGeneratorEntryArray;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByModuleAndKind(TPascalString(ModuleId), Kind);
end;

function GetGeneratorsByModuleAndKinds(const ModuleId: string;
  const Kinds: TGeneratorKinds): TGeneratorEntryArray;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.FindByModuleAndKinds(TPascalString(ModuleId), Kinds);
end;

function GetGeneratorCount: integer;
begin
  if CodeGenRegistry = nil then Exit(0);
  Result := CodeGenRegistry.Count;
end;

function GetGeneratorByIndex(Index: integer): PGeneratorEntry;
begin
  Result := nil;
  if CodeGenRegistry = nil then Exit;
  Result := CodeGenRegistry.GetEntry(Index);
end;

function GetRegisteredExtensions: TPascalStringList;
var
  i: integer;
  v: PGeneratorEntry;
  ExtStr: TPascalString;
begin
  Result := TPascalStringList.Create;
  if CodeGenRegistry = nil then Exit;
  for i := 0 to CodeGenRegistry.Count - 1 do
  begin
    v := CodeGenRegistry.GetEntry(i);
    if v = nil then Continue;
    ExtStr := TemplateExtension(v^.FileNameTemplate.Text);
    if ExtStr.Len = 0 then Continue;
    if Result.IndexOf(ExtStr.Text) < 0 then
      Result.Add(ExtStr.Text);
  end;
end;

function GetRegisteredModules: TPascalStringList;
var
  i: integer;
  v: PGeneratorEntry;
begin
  Result := TPascalStringList.Create;
  if CodeGenRegistry = nil then Exit;
  for i := 0 to CodeGenRegistry.Count - 1 do
  begin
    v := CodeGenRegistry.GetEntry(i);
    if v = nil then Continue;
    if Result.IndexOf(v^.ModuleId.Text) < 0 then
      Result.Add(v^.ModuleId.Text);
  end;
end;

function GetRegisteredKinds: TGeneratorKinds;
var
  i: integer;
  v: PGeneratorEntry;
begin
  Result := [];
  if CodeGenRegistry = nil then Exit;
  for i := 0 to CodeGenRegistry.Count - 1 do
  begin
    v := CodeGenRegistry.GetEntry(i);
    if v <> nil then
      Include(Result, v^.Kind);
  end;
end;

function KindToText(Kind: TGeneratorKind): string;
begin
  case Kind of
    gkService:  Result := 'service';
    gkCall:     Result := 'call';
    gkDoc:      Result := 'doc';
    gkTest:     Result := 'test';
    gkProject:  Result := 'project';
    gkScript:   Result := 'script';
    gkPs1:      Result := 'ps1';
    gkOther:    Result := 'other';
  else
    Result := 'unknown';
  end;
end;

function KindFromText(const Text: string; out Kind: TGeneratorKind): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(Text));
  if L = 'service' then
  begin
    Kind := gkService;
    Result := True;
  end
  else if L = 'call' then
  begin
    Kind := gkCall;
    Result := True;
  end
  else if L = 'doc' then
  begin
    Kind := gkDoc;
    Result := True;
  end
  else if L = 'test' then
  begin
    Kind := gkTest;
    Result := True;
  end
  else if L = 'project' then
  begin
    Kind := gkProject;
    Result := True;
  end
  else if L = 'script' then
  begin
    Kind := gkScript;
    Result := True;
  end
  else if L = 'ps1' then
  begin
    Kind := gkPs1;
    Result := True;
  end
  else if L = 'other' then
  begin
    Kind := gkOther;
    Result := True;
  end
  else
  begin
    Kind := gkOther;
    Result := False;
  end;
end;

function IsSourceKind(Kind: TGeneratorKind): Boolean;
begin
  Result := Kind in [gkService, gkCall];
end;

function IsDocKind(Kind: TGeneratorKind): Boolean;
begin
  Result := Kind = gkDoc;
end;

function IsScriptKind(Kind: TGeneratorKind): Boolean;
begin
  Result := Kind in [gkScript, gkPs1];
end;

function IsBuildKind(Kind: TGeneratorKind): Boolean;
begin
  Result := Kind = gkProject;
end;

function IsTestKind(Kind: TGeneratorKind): Boolean;
begin
  Result := Kind = gkTest;
end;

function ResolveFileName(const Template, UnitName: string): string;
var
  T: TPascalString;
  U: TPascalString;
  P, StartPos: integer;
begin
  T := Template;
  U := UnitName;
  if U.Len = 0 then
  begin
    Result := Template;
    Exit;
  end;
  StartPos := 1;
  while StartPos <= T.Len do
  begin
    P := T.GetPos('xxx', StartPos);
    if P = 0 then Break;
    T := T.GetString(1, P) + U + T.GetString(P + 3, T.Len + 1);
    StartPos := P + U.Len;
  end;
  Result := T.Text;
end;

function TemplateExtension(const Template: string): string;
var
  T: TPascalString;
  i: integer;
begin
  Result := '';
  T := Template;
  for i := T.Len downto 1 do
  begin
    if (T[i] = '/') or (T[i] = '\') then Exit;
    if T[i] = '.' then
    begin
      Result := T.GetString(i, T.Len + 1).Text;
      Exit;
    end;
  end;
end;

function TemplateBaseName(const Template: string): string;
var
  T: TPascalString;
  i: integer;
begin
  Result := Template;
  T := Template;
  for i := T.Len downto 1 do
  begin
    if (T[i] = '/') or (T[i] = '\') then
    begin
      Result := T.GetString(i + 1, T.Len + 1).Text;
      Exit;
    end;
  end;
end;

function TemplateDirectory(const Template: string): string;
var
  T: TPascalString;
  i: integer;
begin
  Result := '';
  T := Template;
  for i := T.Len downto 1 do
  begin
    if (T[i] = '/') or (T[i] = '\') then
    begin
      Result := T.GetString(1, i).Text;
      Exit;
    end;
  end;
end;

function EnsureDirectoryForFile(const FileName: string): Boolean;
var
  Dir: string;
begin
  Result := True;
  if FileName = '' then Exit;
  Dir := ExtractFileDir(FileName);
  if Dir = '' then Exit;
  if umlDirectoryExists(Dir) then Exit;
  Result := umlCreateDirectory(Dir);
end;

function ResolveRelativePath(const BaseDir, FullPath: string): string;
var
  Base: TPascalString;
  Full: TPascalString;
  NextChar: TP_Char;
begin
  Base := BaseDir;
  Full := FullPath;
  if Base.Len = 0 then
  begin
    Result := FullPath;
    Exit;
  end;
  if Full.Same(Base) then
  begin
    Result := '';
    Exit;
  end;
  if (Full.Len > Base.Len) and Full.ComparePos(1, Base) then
  begin
    NextChar := Full[Base.Len + 1];
    if (NextChar = '/') or (NextChar = '\') then
    begin
      Result := Full.GetString(Base.Len + 2, Full.Len + 1).Text;
      Exit;
    end;
  end;
  Result := FullPath;
end;

function InvokeGenerator(Entry: PGeneratorEntry;
  Model: TPascal_Func_Model): TPascalStringList;
begin
  Result := nil;
  if Entry = nil then Exit;
  if not Assigned(Entry^.Func) then Exit;
  if Model = nil then Exit;
  try
    Result := Entry^.Func(Model);
  except
    Result := nil;
  end;
end;

procedure RegisterCodeGenEntry(
  const LanguageID, DisplayName: TPascalString;
  const Side: TArtifactSide;
  const Kind: TArtifactKind;
  const Suffix: TPascalString;
  const FixedName: Boolean;
  const Func: TGenerateFunc);
var
  e: TCodeGenEntry;
begin
  if CodeGenRegistry = nil then Exit;
  e.LanguageID := LanguageID;
  e.DisplayName := DisplayName;
  e.Side := Side;
  e.Kind := Kind;
  e.Suffix := Suffix;
  e.FixedName := FixedName;
  e.Extension := '';
  e.Func := Func;
  CodeGenRegistry.Add(e);
end;

initialization
  CodeGenRegistry := TCodeGenRegistry.Create;

finalization
  if CodeGenRegistry <> nil then
  begin
    CodeGenRegistry.Free;
    CodeGenRegistry := nil;
  end;

end.
