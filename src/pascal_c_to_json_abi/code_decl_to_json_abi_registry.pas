unit code_decl_to_json_abi_registry;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  SysUtils, Classes,
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.ListEngine,
  Z.Pascal_Func_Model;

type
  TGeneratefunc = function(Model: TPascal_Func_Model): TPascalStringList;

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
    LanguageID: TP_String;
    DisplayName: TP_String;
    Side: TArtifactSide;
    Kind: TArtifactKind;
    Suffix: TP_String;
    FixedName: Boolean;
    Extension: TP_String;
    Func: TGeneratefunc;
  end;

  PCodeGenEntry = ^TCodeGenEntry;

  TLanguageInfo = record
    LanguageID: TP_String;
    DisplayName: TP_String;
    HasService: Boolean;
    HasCall: Boolean;
    HasBoth: Boolean;
    ArtifactCount: Integer;
    ServiceCount: Integer;
    CallCount: Integer;
    Kinds: TArtifactKindSet;
    KindCounts: TArtifactKindCounts;
    Extensions: TP_String;
  end;

  TCodeGenRegistry = class
  private
    FList: TList;
    FLangIDsCache: TPascalStringList;
    FLangIDsValid: Boolean;
    function GetCount: Integer;
    function GetEntry(Index: Integer): PCodeGenEntry;
    function MakeExtension(const Suffix: TP_String; FixedName: Boolean): TP_String;
    procedure EnsureLangCache;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const Entry: TCodeGenEntry): PCodeGenEntry;
    property Count: Integer read GetCount;
    property Entries[Index: Integer]: PCodeGenEntry read GetEntry; default;

    function FindLanguageByExtension(const Ext: string): TP_String;
    function HasLanguage(const LangID: TP_String): Boolean;
    function GetLanguageCount: Integer;
    function GetLanguageID(Index: Integer): TP_String;
    function GetLanguageInfo(const LangID: TP_String): TLanguageInfo;

    function GetAllExtensions(const Delim: string): string;
    function GetAllLanguageIDs(const Delim: string): string;
    function GetRegisteredLanguageSummary: string;
    function GetRegisteredLanguageDetail: string;
    function GetCallOnlyLanguages: string;
    function GetServiceOnlyLanguages: string;
    function GetBothLanguages: string;
    function GetSeparateBothLanguages: string;
    function GetCompleteSetLanguages: string;
  end;

var
  CodeGenRegistry: TCodeGenRegistry;

procedure RegisterCodeGenEntry(
  const LanguageID, DisplayName: TP_String;
  const Side: TArtifactSide;
  const Kind: TArtifactKind;
  const Suffix: TP_String;
  const FixedName: Boolean;
  const Func: TGeneratefunc);

function Side_Matches_Requested(const EntrySide: TArtifactSide;
  const AsCall: Boolean): Boolean;
function Side_Has_Service(const Side: TArtifactSide): Boolean;
function Side_Has_Call(const Side: TArtifactSide): Boolean;
function Side_To_String(const Side: TArtifactSide): string;

function Kind_Is_Readme(const Kind: TArtifactKind): Boolean;
function Kind_Is_Code(const Kind: TArtifactKind): Boolean;
function Kind_Is_Header(const Kind: TArtifactKind): Boolean;
function Kind_Is_Html(const Kind: TArtifactKind): Boolean;
function Kind_Is_Test(const Kind: TArtifactKind): Boolean;
function Kind_Is_Build(const Kind: TArtifactKind): Boolean;
function Kind_To_String(const Kind: TArtifactKind): string;
function Kind_To_Short(const Kind: TArtifactKind): string;

implementation

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

function Kind_Is_Readme(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akServiceReadme, akCallReadme, akTestReadme];
end;

function Kind_Is_Code(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akServiceCode, akServiceHeader, akCallCode,
    akCallHeader, akTestCode, akCallHtml, akBuildScript, akBuildMain];
end;

function Kind_Is_Header(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akServiceHeader, akCallHeader];
end;

function Kind_Is_Html(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind = akCallHtml;
end;

function Kind_Is_Test(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akTestCode, akTestReadme];
end;

function Kind_Is_Build(const Kind: TArtifactKind): Boolean;
begin
  Result := Kind in [akBuildScript, akBuildMain];
end;

function Kind_To_String(const Kind: TArtifactKind): string;
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

function Kind_To_Short(const Kind: TArtifactKind): string;
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

constructor TCodeGenRegistry.Create;
begin
  inherited Create;
  FList := TList.Create;
  FLangIDsCache := TPascalStringList.Create;
  FLangIDsValid := False;
end;

destructor TCodeGenRegistry.Destroy;
var
  i: Integer;
  p: PCodeGenEntry;
begin
  for i := 0 to FList.Count - 1 do
  begin
    p := PCodeGenEntry(FList[i]);
    if p <> nil then
      Dispose(p);
  end;
  FList.Clear;
  FList.Free;
  FLangIDsCache.Free;
  inherited Destroy;
end;

function TCodeGenRegistry.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TCodeGenRegistry.GetEntry(Index: Integer): PCodeGenEntry;
begin
  Result := PCodeGenEntry(FList[Index]);
end;

function TCodeGenRegistry.MakeExtension(const Suffix: TP_String;
  FixedName: Boolean): TP_String;
begin
  if FixedName then
    Result := ''
  else
    Result := LowerCase(SysUtils.ExtractFileExt(Suffix.Text));
end;

procedure TCodeGenRegistry.EnsureLangCache;
var
  i, j: Integer;
  e: PCodeGenEntry;
  lang: string;
  found: Boolean;
begin
  if FLangIDsValid then Exit;
  FLangIDsCache.Clear;
  for i := 0 to FList.Count - 1 do
  begin
    e := PCodeGenEntry(FList[i]);
    if e = nil then Continue;
    lang := e^.LanguageID.Text;
    found := False;
    for j := 0 to FLangIDsCache.Count - 1 do
      if FLangIDsCache[j] = lang then
      begin
        found := True;
        Break;
      end;
    if not found then
      FLangIDsCache.Add(lang);
  end;
  FLangIDsValid := True;
end;

function TCodeGenRegistry.Add(const Entry: TCodeGenEntry): PCodeGenEntry;
var
  p: PCodeGenEntry;
  e: TCodeGenEntry;
begin
  e := Entry;
  if e.Extension.Len = 0 then
    e.Extension := MakeExtension(e.Suffix, e.FixedName);
  New(p);
  p^ := e;
  FList.Add(p);
  FLangIDsValid := False;
  Result := p;
end;

function TCodeGenRegistry.FindLanguageByExtension(const Ext: string): TP_String;
var
  i: Integer;
  e: PCodeGenEntry;
  lext: string;
begin
  Result := '';
  lext := LowerCase(Ext);
  if lext = '' then Exit;
  for i := 0 to FList.Count - 1 do
  begin
    e := PCodeGenEntry(FList[i]);
    if e = nil then Continue;
    if (e^.Extension.Len > 0) and (e^.Extension.Text = lext) then
    begin
      Result := e^.LanguageID;
      Exit;
    end;
  end;
end;

function TCodeGenRegistry.HasLanguage(const LangID: TP_String): Boolean;
var
  i: Integer;
  e: PCodeGenEntry;
begin
  Result := False;
  if LangID.Len = 0 then Exit;
  for i := 0 to FList.Count - 1 do
  begin
    e := PCodeGenEntry(FList[i]);
    if e = nil then Continue;
    if e^.LanguageID.Same(LangID) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TCodeGenRegistry.GetLanguageCount: Integer;
begin
  EnsureLangCache;
  Result := FLangIDsCache.Count;
end;

function TCodeGenRegistry.GetLanguageID(Index: Integer): TP_String;
begin
  EnsureLangCache;
  Result := FLangIDsCache[Index];
end;

function TCodeGenRegistry.GetLanguageInfo(const LangID: TP_String): TLanguageInfo;
var
  i, j: Integer;
  e: PCodeGenEntry;
  extList: TPascalStringList;
  extStr: string;
  found: Boolean;
  k: TArtifactKind;
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

  extList := TPascalStringList.Create;
  try
    for i := 0 to FList.Count - 1 do
    begin
      e := PCodeGenEntry(FList[i]);
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
        for j := 0 to extList.Count - 1 do
          if extList[j] = e^.Extension.Text then
          begin
            found := True;
            Break;
          end;
        if not found then
          extList.Add(e^.Extension.Text);
      end;
    end;

    extStr := '';
    for i := 0 to extList.Count - 1 do
    begin
      if extStr <> '' then extStr := extStr + ', ';
      extStr := extStr + extList[i];
    end;
    Result.Extensions := extStr;
  finally
    extList.Free;
  end;
end;

function TCodeGenRegistry.GetAllExtensions(const Delim: string): string;
var
  i, j: Integer;
  e: PCodeGenEntry;
  seen: TPascalStringList;
  s: string;
  found: Boolean;
begin
  seen := TPascalStringList.Create;
  try
    s := '';
    for i := 0 to FList.Count - 1 do
    begin
      e := PCodeGenEntry(FList[i]);
      if e = nil then Continue;
      if e^.Extension.Len = 0 then Continue;
      found := False;
      for j := 0 to seen.Count - 1 do
        if seen[j] = e^.Extension.Text then
        begin
          found := True;
          Break;
        end;
      if found then Continue;
      seen.Add(e^.Extension.Text);
      if s <> '' then s := s + Delim;
      s := s + e^.Extension.Text;
    end;
    Result := s;
  finally
    seen.Free;
  end;
end;

function TCodeGenRegistry.GetAllLanguageIDs(const Delim: string): string;
var
  i: Integer;
  s: string;
begin
  EnsureLangCache;
  s := '';
  for i := 0 to FLangIDsCache.Count - 1 do
  begin
    if s <> '' then s := s + Delim;
    s := s + FLangIDsCache[i];
  end;
  Result := s;
end;

function TCodeGenRegistry.GetRegisteredLanguageSummary: string;
var
  i: Integer;
  k: TArtifactKind;
  info: TLanguageInfo;
  sideStr, breakdown: string;
  s: string;
begin
  EnsureLangCache;
  s := '';
  for i := 0 to FLangIDsCache.Count - 1 do
  begin
    info := GetLanguageInfo(FLangIDsCache[i]);

    if info.HasBoth and (not info.HasService) and (not info.HasCall) then
      sideStr := 'complete-set'
    else if info.HasService and info.HasCall then
      sideStr := 'service+call'
    else if info.HasService and info.HasBoth then
      sideStr := 'service+complete'
    else if info.HasCall and info.HasBoth then
      sideStr := 'call+complete'
    else if info.HasService then
      sideStr := 'service-only'
    else if info.HasCall then
      sideStr := 'call-only'
    else
      sideStr := 'unknown';

    breakdown := '';
    for k := Low(TArtifactKind) to High(TArtifactKind) do
      if info.KindCounts[k] > 0 then
      begin
        if breakdown <> '' then breakdown := breakdown + ', ';
        breakdown := breakdown + Kind_To_String(k) + ' x' + IntToStr(info.KindCounts[k]);
      end;
    if breakdown = '' then
      breakdown := 'no artifacts';

    s := s + Format('  [%-12s] %-17s %-16s %s  (%d total)',
      [info.LanguageID.Text, sideStr, info.Extensions.Text,
       breakdown, info.ArtifactCount]) + sLineBreak;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetRegisteredLanguageDetail: string;
var
  i, j: Integer;
  info: TLanguageInfo;
  serviceCap, callCap: Boolean;
  sideStr: string;
  s: string;
  e: PCodeGenEntry;
begin
  s := '';
  for i := 0 to GetLanguageCount - 1 do
  begin
    info := GetLanguageInfo(GetLanguageID(i));
    serviceCap := info.HasService or info.HasBoth;
    callCap := info.HasCall or info.HasBoth;
    if serviceCap and callCap then
      sideStr := 'service+call'
    else if serviceCap then
      sideStr := 'service-only'
    else if callCap then
      sideStr := 'call-only'
    else
      sideStr := 'unknown';

    s := s + Format('[%s] %s',
      [info.LanguageID.Text, info.DisplayName.Text]) + sLineBreak;
    s := s + Format('  Side: %s  Exts: %s  Artifacts: %d',
      [sideStr, info.Extensions.Text, info.ArtifactCount]) + sLineBreak;

    for j := 0 to FList.Count - 1 do
    begin
      e := PCodeGenEntry(FList[j]);
      if e = nil then Continue;
      if not e^.LanguageID.Same(info.LanguageID) then Continue;
      s := s + Format('    - %s [%s] side=%s suffix=%s%s',
        [e^.DisplayName.Text, Kind_To_String(e^.Kind),
         Side_To_String(e^.Side), e^.Suffix.Text,
         BoolToStr(e^.FixedName, ' fixed', '')]) + sLineBreak;
    end;
    s := s + sLineBreak;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetCallOnlyLanguages: string;
var
  i: Integer;
  info: TLanguageInfo;
  serviceCap, callCap: Boolean;
  s: string;
begin
  s := '';
  for i := 0 to GetLanguageCount - 1 do
  begin
    info := GetLanguageInfo(GetLanguageID(i));
    serviceCap := info.HasService or info.HasBoth;
    callCap := info.HasCall or info.HasBoth;
    if callCap and (not serviceCap) then
    begin
      if s <> '' then s := s + ', ';
      s := s + info.LanguageID.Text;
    end;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetServiceOnlyLanguages: string;
var
  i: Integer;
  info: TLanguageInfo;
  serviceCap, callCap: Boolean;
  s: string;
begin
  s := '';
  for i := 0 to GetLanguageCount - 1 do
  begin
    info := GetLanguageInfo(GetLanguageID(i));
    serviceCap := info.HasService or info.HasBoth;
    callCap := info.HasCall or info.HasBoth;
    if serviceCap and (not callCap) then
    begin
      if s <> '' then s := s + ', ';
      s := s + info.LanguageID.Text;
    end;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetBothLanguages: string;
var
  i: Integer;
  info: TLanguageInfo;
  serviceCap, callCap: Boolean;
  s: string;
begin
  s := '';
  for i := 0 to GetLanguageCount - 1 do
  begin
    info := GetLanguageInfo(GetLanguageID(i));
    serviceCap := info.HasService or info.HasBoth;
    callCap := info.HasCall or info.HasBoth;
    if serviceCap and callCap then
    begin
      if s <> '' then s := s + ', ';
      s := s + info.LanguageID.Text;
    end;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetSeparateBothLanguages: string;
var
  i: Integer;
  info: TLanguageInfo;
  s: string;
begin
  s := '';
  for i := 0 to GetLanguageCount - 1 do
  begin
    info := GetLanguageInfo(GetLanguageID(i));
    if info.HasService and info.HasCall then
    begin
      if s <> '' then s := s + ', ';
      s := s + info.LanguageID.Text;
    end;
  end;
  Result := s;
end;

function TCodeGenRegistry.GetCompleteSetLanguages: string;
var
  i: Integer;
  info: TLanguageInfo;
  s: string;
begin
  s := '';
  for i := 0 to GetLanguageCount - 1 do
  begin
    info := GetLanguageInfo(GetLanguageID(i));
    if info.HasBoth and (not info.HasService) and (not info.HasCall) then
    begin
      if s <> '' then s := s + ', ';
      s := s + info.LanguageID.Text;
    end;
  end;
  Result := s;
end;

procedure RegisterCodeGenEntry(
  const LanguageID, DisplayName: TP_String;
  const Side: TArtifactSide;
  const Kind: TArtifactKind;
  const Suffix: TP_String;
  const FixedName: Boolean;
  const Func: TGeneratefunc);
var
  Entry: TCodeGenEntry;
begin
  if CodeGenRegistry = nil then Exit;
  Entry.LanguageID := LanguageID;
  Entry.DisplayName := DisplayName;
  Entry.Side := Side;
  Entry.Kind := Kind;
  Entry.Suffix := Suffix;
  Entry.FixedName := FixedName;
  Entry.Extension := '';
  Entry.Func := Func;
  CodeGenRegistry.Add(Entry);
end;

initialization
  CodeGenRegistry := TCodeGenRegistry.Create;

finalization
  CodeGenRegistry.Free;
  CodeGenRegistry := nil;

end.
