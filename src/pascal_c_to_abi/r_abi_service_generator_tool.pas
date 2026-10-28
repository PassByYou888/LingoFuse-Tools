unit R_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceRCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[R_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[R_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function RStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append(#92);
      Result.Append(#39);
    end
    else if c = #92 then
    begin
      Result.Append(#92);
      Result.Append(#92);
    end
    else if c = #10 then
    begin
      Result.Append(#92);
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append(#92);
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append(#92);
      Result.Append('t');
    end
    else
      Result.Append(c);
  end;
  Result.Append(#39);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function IsInt64ABIType(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
end;

function ABI_Type_To_R_Pack_Fn(const T: TP_String): TP_String;
begin
  if T.Same('shortint') then Result := 'abi_pack_int8'
  else if T.Same('smallint') then Result := 'abi_pack_int16'
  else if T.Same('integer') or T.Same('longint') then Result := 'abi_pack_int32'
  else if T.Same('int64') then Result := 'abi_pack_int64'
  else if T.Same('byte') then Result := 'abi_pack_uint8'
  else if T.Same('word') then Result := 'abi_pack_uint16'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'abi_pack_uint32'
  else if T.Same('uint64') then Result := 'abi_pack_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'abi_pack_double'
  else if T.Same('single') then Result := 'abi_pack_single'
  else if IsStringABIType(T) then Result := 'abi_pack_string'
  else Result := '';
end;

function ABI_Type_To_R_Read_Fn(const T: TP_String): TP_String;
begin
  if T.Same('shortint') then Result := 'abi_read_int8'
  else if T.Same('smallint') then Result := 'abi_read_int16'
  else if T.Same('integer') or T.Same('longint') then Result := 'abi_read_int32'
  else if T.Same('int64') then Result := 'abi_read_int64'
  else if T.Same('byte') then Result := 'abi_read_uint8'
  else if T.Same('word') then Result := 'abi_read_uint16'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'abi_read_uint32'
  else if T.Same('uint64') then Result := 'abi_read_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'abi_read_double'
  else if T.Same('single') then Result := 'abi_read_single'
  else if IsStringABIType(T) then Result := 'abi_read_string'
  else Result := '';
end;

function ABI_Type_To_R_Default_Value(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then Result := #39#39
  else if IsInt64ABIType(T) then Result := 'bit64::as.integer64(0)'
  else if T.Same('double') or T.Same('extended') or T.Same('real') or T.Same('single') then Result := '0'
  else Result := '0L';
end;

function ABI_Type_To_R_Write_Ok_Fn(const T: TP_String): TP_String;
begin
  if T.Same('shortint') then Result := 'abi_write_ok_int8'
  else if T.Same('smallint') then Result := 'abi_write_ok_int16'
  else if T.Same('integer') or T.Same('longint') then Result := 'abi_write_ok_int32'
  else if T.Same('int64') then Result := 'abi_write_ok_int64'
  else if T.Same('byte') then Result := 'abi_write_ok_uint8'
  else if T.Same('word') then Result := 'abi_write_ok_uint16'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'abi_write_ok_uint32'
  else if T.Same('uint64') then Result := 'abi_write_ok_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'abi_write_ok_double'
  else if T.Same('single') then Result := 'abi_write_ok_single'
  else if IsStringABIType(T) then Result := 'abi_write_ok_string'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_R_Pack_Fn(T) <> '';
end;

function BuildRParamNames(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i).Text
    else
      n := MakeApiName(Params[i].Name);
    if i > 0 then Result := Result + ', ';
    Result := Result + n.Text;
  end;
end;

function BuildRInternalCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := 'ctx$sender_uid, ctx$sender_p2p_name';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i).Text
    else
      n := MakeApiName(Params[i].Name);
    Result := Result + ', ' + n.Text;
  end;
end;

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;
    for j := 0 to High(f.Params) do
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text]));
    end;
    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: routine with empty Name');
    end;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('STATUS_OK <- as.raw(0)');
  Lines.Add('STATUS_ERROR <- as.raw(255)');
  Lines.Add('');
end;

procedure EmitPackers(Lines: TPascalStringList);
begin
  Lines.Add('abi_pack_int8 <- function(v) {');
  Lines.Add('  v <- as.integer(v)');
  Lines.Add('  if (is.na(v) || v < -128L || v > 127L) stop(' + #39 + 'abi_pack_int8: out of range' + #39 + ')');
  Lines.Add('  if (v < 0L) v <- v + 256L');
  Lines.Add('  as.raw(v)');
  Lines.Add('}');
  Lines.Add('abi_pack_int16 <- function(v) {');
  Lines.Add('  v <- as.integer(v)');
  Lines.Add('  if (is.na(v) || v < -32768L || v > 32767L) stop(' + #39 + 'abi_pack_int16: out of range' + #39 + ')');
  Lines.Add('  if (v < 0L) v <- v + 65536L');
  Lines.Add('  as.raw(c(v %% 256L, (v %/% 256L) %% 256L))');
  Lines.Add('}');
  Lines.Add('abi_pack_int32 <- function(v) {');
  Lines.Add('  v <- as.integer(v)');
  Lines.Add('  if (is.na(v)) stop(' + #39 + 'abi_pack_int32: cannot represent as int32' + #39 + ')');
  Lines.Add('  if (v < 0L) v <- v + 2^32');
  Lines.Add('  v <- as.numeric(v)');
  Lines.Add('  as.raw(c(v %% 256, (v %/% 256) %% 256, (v %/% 65536) %% 256, (v %/% 16777216) %% 256))');
  Lines.Add('}');
  Lines.Add('abi_pack_uint8 <- function(v) {');
  Lines.Add('  v <- as.integer(v)');
  Lines.Add('  if (is.na(v) || v < 0L || v > 255L) stop(' + #39 + 'abi_pack_uint8: out of range' + #39 + ')');
  Lines.Add('  as.raw(v)');
  Lines.Add('}');
  Lines.Add('abi_pack_uint16 <- function(v) {');
  Lines.Add('  v <- as.integer(v)');
  Lines.Add('  if (is.na(v) || v < 0L || v > 65535L) stop(' + #39 + 'abi_pack_uint16: out of range' + #39 + ')');
  Lines.Add('  as.raw(c(v %% 256L, (v %/% 256L) %% 256L))');
  Lines.Add('}');
  Lines.Add('abi_pack_uint32 <- function(v) {');
  Lines.Add('  v <- as.numeric(v)');
  Lines.Add('  if (is.na(v) || v < 0 || v >= 2^32) stop(' + #39 + 'abi_pack_uint32: out of range' + #39 + ')');
  Lines.Add('  as.raw(c(v %% 256, (v %/% 256) %% 256, (v %/% 65536) %% 256, (v %/% 16777216) %% 256))');
  Lines.Add('}');
  Lines.Add('abi_pack_int64 <- function(v) {');
  Lines.Add('  if (!requireNamespace(' + #39 + 'bit64' + #39 + ', quietly = TRUE)) stop(' + #39 + 'abi_pack_int64 requires bit64' + #39 + ')');
  Lines.Add('  v64 <- bit64::as.integer64(v)');
  Lines.Add('  mask_lo <- bit64::as.integer64(' + #39 + '4294967295' + #39 + ')');
  Lines.Add('  mask_hi <- bit64::as.integer64(' + #39 + '4294967296' + #39 + ')');
  Lines.Add('  lo <- as.numeric(v64 %% mask_hi)');
  Lines.Add('  hi <- as.numeric(v64 %/% mask_hi)');
  Lines.Add('  c(');
  Lines.Add('    as.raw(c(lo %% 256, (lo %/% 256) %% 256, (lo %/% 65536) %% 256, (lo %/% 16777216) %% 256)),');
  Lines.Add('    as.raw(c(hi %% 256, (hi %/% 256) %% 256, (hi %/% 65536) %% 256, (hi %/% 16777216) %% 256))');
  Lines.Add('  )');
  Lines.Add('}');
  Lines.Add('abi_pack_uint64 <- abi_pack_int64');
  Lines.Add('abi_pack_double <- function(v) {');
  Lines.Add('  writeBin(as.numeric(v), raw(), size = 8L, endian = ' + #39 + 'little' + #39 + ')');
  Lines.Add('}');
  Lines.Add('abi_pack_single <- function(v) {');
  Lines.Add('  writeBin(as.numeric(v), raw(), size = 4L, endian = ' + #39 + 'little' + #39 + ')');
  Lines.Add('}');
  Lines.Add('abi_pack_string <- function(v) {');
  Lines.Add('  c(charToRaw(enc2utf8(v)), as.raw(0))');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitReaders(Lines: TPascalStringList);
begin
  Lines.Add('abi_read_int8 <- function(buf, pos) {');
  Lines.Add('  if (pos > length(buf)) stop(' + #39 + 'input truncated: int8' + #39 + ')');
  Lines.Add('  v <- as.integer(buf[pos])');
  Lines.Add('  if (v >= 128L) v <- v - 256L');
  Lines.Add('  list(value = v, pos = pos + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_int16 <- function(buf, pos) {');
  Lines.Add('  end <- pos + 1L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: int16' + #39 + ')');
  Lines.Add('  bytes <- as.integer(buf[pos:end])');
  Lines.Add('  v <- bytes[1] + bytes[2] * 256L');
  Lines.Add('  if (v >= 32768L) v <- v - 65536L');
  Lines.Add('  list(value = v, pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_int32 <- function(buf, pos) {');
  Lines.Add('  end <- pos + 3L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: int32' + #39 + ')');
  Lines.Add('  bytes <- as.numeric(as.integer(buf[pos:end]))');
  Lines.Add('  v <- bytes[1] + bytes[2] * 256 + bytes[3] * 65536 + bytes[4] * 16777216');
  Lines.Add('  if (v >= 2^31) v <- v - 2^32');
  Lines.Add('  list(value = as.integer(v), pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_uint8 <- function(buf, pos) {');
  Lines.Add('  if (pos > length(buf)) stop(' + #39 + 'input truncated: uint8' + #39 + ')');
  Lines.Add('  list(value = as.integer(buf[pos]), pos = pos + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_uint16 <- function(buf, pos) {');
  Lines.Add('  end <- pos + 1L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: uint16' + #39 + ')');
  Lines.Add('  bytes <- as.integer(buf[pos:end])');
  Lines.Add('  list(value = bytes[1] + bytes[2] * 256L, pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_uint32 <- function(buf, pos) {');
  Lines.Add('  end <- pos + 3L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: uint32' + #39 + ')');
  Lines.Add('  bytes <- as.numeric(as.integer(buf[pos:end]))');
  Lines.Add('  list(value = bytes[1] + bytes[2] * 256 + bytes[3] * 65536 + bytes[4] * 16777216, pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_int64 <- function(buf, pos) {');
  Lines.Add('  if (!requireNamespace(' + #39 + 'bit64' + #39 + ', quietly = TRUE)) stop(' + #39 + 'abi_read_int64 requires bit64' + #39 + ')');
  Lines.Add('  end <- pos + 7L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: int64' + #39 + ')');
  Lines.Add('  bytes <- as.numeric(as.integer(buf[pos:end]))');
  Lines.Add('  lo <- bytes[1] + bytes[2] * 256 + bytes[3] * 65536 + bytes[4] * 16777216');
  Lines.Add('  hi <- bytes[5] + bytes[6] * 256 + bytes[7] * 65536 + bytes[8] * 16777216');
  Lines.Add('  v64 <- bit64::as.integer64(hi) * bit64::as.integer64(' + #39 + '4294967296' + #39 + ') + bit64::as.integer64(lo)');
  Lines.Add('  list(value = v64, pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_uint64 <- abi_read_int64');
  Lines.Add('abi_read_double <- function(buf, pos) {');
  Lines.Add('  end <- pos + 7L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: double' + #39 + ')');
  Lines.Add('  list(value = readBin(buf[pos:end], numeric(), n = 1L, size = 8L, endian = ' + #39 + 'little' + #39 + '), pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_single <- function(buf, pos) {');
  Lines.Add('  end <- pos + 3L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: single' + #39 + ')');
  Lines.Add('  list(value = readBin(buf[pos:end], numeric(), n = 1L, size = 4L, endian = ' + #39 + 'little' + #39 + '), pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('abi_read_string <- function(buf, pos) {');
  Lines.Add('  if (pos > length(buf)) stop(' + #39 + 'input truncated: string' + #39 + ')');
  Lines.Add('  end <- pos');
  Lines.Add('  while (end <= length(buf) && buf[end] != as.raw(0)) end <- end + 1L');
  Lines.Add('  if (end > length(buf)) stop(' + #39 + 'input truncated: string (no NUL)' + #39 + ')');
  Lines.Add('  if (end > pos) {');
  Lines.Add('    v <- rawToChar(buf[pos:(end - 1L)])');
  Lines.Add('    Encoding(v) <- ' + #39 + 'UTF-8' + #39);
  Lines.Add('  } else {');
  Lines.Add('    v <- ' + #39#39);
  Lines.Add('  }');
  Lines.Add('  list(value = v, pos = end + 1L)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitWriters(Lines: TPascalStringList);
begin
  Lines.Add('abi_write_error <- function(msg) c(STATUS_ERROR, charToRaw(enc2utf8(msg)), as.raw(0))');
  Lines.Add('abi_write_ok_void <- function() as.raw(0)');
  Lines.Add('abi_write_ok_int8 <- function(v) c(STATUS_OK, abi_pack_int8(v))');
  Lines.Add('abi_write_ok_int16 <- function(v) c(STATUS_OK, abi_pack_int16(v))');
  Lines.Add('abi_write_ok_int32 <- function(v) c(STATUS_OK, abi_pack_int32(v))');
  Lines.Add('abi_write_ok_int64 <- function(v) c(STATUS_OK, abi_pack_int64(v))');
  Lines.Add('abi_write_ok_uint8 <- function(v) c(STATUS_OK, abi_pack_uint8(v))');
  Lines.Add('abi_write_ok_uint16 <- function(v) c(STATUS_OK, abi_pack_uint16(v))');
  Lines.Add('abi_write_ok_uint32 <- function(v) c(STATUS_OK, abi_pack_uint32(v))');
  Lines.Add('abi_write_ok_uint64 <- function(v) c(STATUS_OK, abi_pack_uint64(v))');
  Lines.Add('abi_write_ok_double <- function(v) c(STATUS_OK, abi_pack_double(v))');
  Lines.Add('abi_write_ok_single <- function(v) c(STATUS_OK, abi_pack_single(v))');
  Lines.Add('abi_write_ok_string <- function(v) c(STATUS_OK, abi_pack_string(v))');
  Lines.Add('');
end;

procedure EmitInternalCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamList: TP_String;
begin
  ParamList := 'lf_uid, lf_p2p_name';
  if Length(F.Params) > 0 then
    ParamList := ParamList + ', ' + BuildRParamNames(F.Params);

  Lines.Add('internal_call_' + ApiName + ' <- function(' + ParamList + ') {');
  if F.IsFunction then
    Lines.Add('  ' + ABI_Type_To_R_Default_Value(F.ReturnType))
  else
    Lines.Add('  invisible(NULL)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackFunction(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn: TP_String;
begin
  Lines.Add('callback_' + ApiName + ' <- function(input_raw, ctx) {');
  Lines.Add('  tryCatch({');
  if Length(F.Params) > 0 then
  begin
    Lines.Add('    pos <- 1L');
    for i := 0 to High(F.Params) do
    begin
      if F.Params[i].Name.Len = 0 then
        PName := 'p' + umlIntToStr(i).Text
      else
        PName := MakeApiName(F.Params[i].Name);
      ReadFn := ABI_Type_To_R_Read_Fn(F.Params[i].PascalType);
      Lines.Add('    r <- ' + ReadFn + '(input_raw, pos)');
      Lines.Add('    ' + PName.Text + ' <- r$value');
      Lines.Add('    pos <- r$pos');
    end;
  end;
  Lines.Add('    result <- internal_call_' + ApiName + '(' + BuildRInternalCallArgList(F.Params) + ')');
  Lines.Add('    ' + ABI_Type_To_R_Write_Ok_Fn(F.ReturnType) + '(result)');
  Lines.Add('  }, error = function(e) {');
  Lines.Add('    abi_write_error(conditionMessage(e))');
  Lines.Add('  })');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackProcedure(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn: TP_String;
begin
  Lines.Add('callback_' + ApiName + ' <- function(input_raw, ctx) {');
  Lines.Add('  tryCatch({');
  if Length(F.Params) > 0 then
  begin
    Lines.Add('    pos <- 1L');
    for i := 0 to High(F.Params) do
    begin
      if F.Params[i].Name.Len = 0 then
        PName := 'p' + umlIntToStr(i).Text
      else
        PName := MakeApiName(F.Params[i].Name);
      ReadFn := ABI_Type_To_R_Read_Fn(F.Params[i].PascalType);
      Lines.Add('    r <- ' + ReadFn + '(input_raw, pos)');
      Lines.Add('    ' + PName.Text + ' <- r$value');
      Lines.Add('    pos <- r$pos');
    end;
  end;
  Lines.Add('    internal_call_' + ApiName + '(' + BuildRInternalCallArgList(F.Params) + ')');
  Lines.Add('  }, error = function(e) {');
  Lines.Add('  })');
  Lines.Add('  invisible(NULL)');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceRCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating R ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines);
    Lines.Add('DEFAULT_APP_NAME <- ' + RStrLit(AppName));
    Lines.Add('DEFAULT_APP_DESC <- ' + RStrLit(AppDesc));
    Lines.Add('');

    EmitPackers(Lines);
    EmitReaders(Lines);
    EmitWriters(Lines);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitInternalCall(Lines, ApiName, F);
      if F.IsFunction then
        EmitCallbackFunction(Lines, ApiName, F)
      else
        EmitCallbackProcedure(Lines, ApiName, F);
    end;

    Lines.Add('register_all_abi_apis <- function(app) {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      if F.IsFunction then
        Lines.Add('  lf_register_call(app, ' + RStrLit(ApiName) + ', ' +
          RStrLit(F.Name) + ', callback_' + ApiName + ', bin = TRUE, with_context = TRUE)')
      else
        Lines.Add('  lf_register_notify(app, ' + RStrLit(ApiName) + ', ' +
          RStrLit(F.Name) + ', callback_' + ApiName + ', bin = TRUE, with_context = TRUE)');
    end;
    Lines.Add('  invisible(NULL)');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('register_all_p2p_abi_apis <- function() {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      if F.IsFunction then
        Lines.Add('  lf_register_p2p_call(' + RStrLit(ApiName) + ', ' +
          RStrLit(F.Name) + ', callback_' + ApiName + ', bin = TRUE, with_context = TRUE)')
      else
        Lines.Add('  lf_register_p2p_notify(' + RStrLit(ApiName) + ', ' +
          RStrLit(F.Name) + ', callback_' + ApiName + ', bin = TRUE, with_context = TRUE)');
    end;
    Lines.Add('  invisible(NULL)');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('create_and_register_abi_app <- function() {');
    Lines.Add('  app <- lf_create_app(DEFAULT_APP_NAME, DEFAULT_APP_DESC)');
    Lines.Add('  if (is.null(app)) return(NULL)');
    Lines.Add('  register_all_abi_apis(app)');
    Lines.Add('  app');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service module', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'r',
    'xxx_abi_service.R',
    gkService,
    'R ABI service implementation',
    @GenerateABIServiceRCode);

end.
