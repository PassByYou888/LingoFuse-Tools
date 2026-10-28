unit java_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallJavaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or
    T.Same('pwidechar');
end;

function ABI_Type_To_Java_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'long'
  else if T.Same('word') then
    Result := 'int'
  else if T.Same('smallint') then
    Result := 'short'
  else if T.Same('byte') then
    Result := 'byte'
  else if T.Same('uint64') then
    Result := 'long'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Java_Boxed(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'Integer'
  else if T.Same('int64') then
    Result := 'Long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'Long'
  else if T.Same('word') then
    Result := 'Integer'
  else if T.Same('smallint') then
    Result := 'Short'
  else if T.Same('byte') then
    Result := 'Byte'
  else if T.Same('uint64') then
    Result := 'Long'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'Double'
  else if T.Same('single') then
    Result := 'Float'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Java_Read_Result_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'readResult_Int32'
  else if T.Same('int64') then
    Result := 'readResult_Int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'readResult_UInt32'
  else if T.Same('word') then
    Result := 'readResult_UInt16'
  else if T.Same('smallint') then
    Result := 'readResult_Int16'
  else if T.Same('byte') then
    Result := 'readResult_Int8'
  else if T.Same('uint64') then
    Result := 'readResult_UInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'readResult_Double'
  else if T.Same('single') then
    Result := 'readResult_Single'
  else if IsStringABIType(T) then
    Result := 'readResult_String'
  else
    Result := '';
end;

function ABI_Type_To_Java_Write_Stmt(const T: TP_String;
  const ParamName: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := TP_String('writeInt32(') + ParamName + TP_String(')')
  else if T.Same('int64') then
    Result := TP_String('writeInt64(') + ParamName + TP_String(')')
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := TP_String('writeInt32((int)(') + ParamName +
      TP_String(' & 0xFFFFFFFFL))')
  else if T.Same('word') then
    Result := TP_String('writeInt16((short)(') + ParamName +
      TP_String(' & 0xFFFF))')
  else if T.Same('smallint') then
    Result := TP_String('writeInt16(') + ParamName + TP_String(')')
  else if T.Same('byte') then
    Result := TP_String('writeInt8(') + ParamName + TP_String(')')
  else if T.Same('uint64') then
    Result := TP_String('writeInt64(') + ParamName + TP_String(')')
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := TP_String('writeDouble(') + ParamName + TP_String(')')
  else if T.Same('single') then
    Result := TP_String('writeSingle(') + ParamName + TP_String(')')
  else if IsStringABIType(T) then
    Result := TP_String('writeString(') + ParamName + TP_String(')')
  else
    Result := TP_String('');
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Java_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsJavaKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('assert') or S.Same('boolean') or
    S.Same('break') or S.Same('byte') or S.Same('case') or
    S.Same('catch') or S.Same('char') or S.Same('class') or
    S.Same('const') or S.Same('continue') or S.Same('default') or
    S.Same('do') or S.Same('double') or S.Same('else') or
    S.Same('enum') or S.Same('extends') or S.Same('final') or
    S.Same('finally') or S.Same('float') or S.Same('for') or
    S.Same('goto') or S.Same('if') or S.Same('implements') or
    S.Same('import') or S.Same('instanceof') or S.Same('int') or
    S.Same('interface') or S.Same('long') or S.Same('native') or
    S.Same('new') or S.Same('package') or S.Same('private') or
    S.Same('protected') or S.Same('public') or S.Same('return') or
    S.Same('short') or S.Same('static') or S.Same('strictfp') or
    S.Same('super') or S.Same('switch') or S.Same('synchronized') or
    S.Same('this') or S.Same('throw') or S.Same('throws') or
    S.Same('transient') or S.Same('try') or S.Same('void') or
    S.Same('volatile') or S.Same('while') or S.Same('true') or
    S.Same('false') or S.Same('null') or S.Same('var') or
    S.Same('record') or S.Same('yield') or S.Same('sealed') or
    S.Same('permits');
end;

function IsReservedLocalName(const S: TP_String): boolean;
begin
  Result :=
    S.Same('appName') or S.Same('group') or S.Same('handler') or
    S.Same('uidBytes') or S.Same('apiName') or
    S.Same('req') or S.Same('resp') or
    S.Same('status') or S.Same('err') or S.Same('t') or
    S.Same('value') or S.Same('ret') or
    S.Same('in') or S.Same('out') or S.Same('body') or
    S.Same('msg') or S.Same('result');
end;

function MakeSafeJavaParamName(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := TP_String('p') + TP_String(umlIntToStr(Index).Text);
    Exit;
  end;
  Result := TP_String('');
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append(TP_Char('_'));
  end;
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := TP_String('_') + Result;
  if IsJavaKeyword(Result) then
    Result := Result + TP_String('_');
  if IsReservedLocalName(Result) then
    Result := Result + TP_String('_');
end;

function JavaStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
begin
  Result := TP_String('"');
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
      Result := Result + TP_String('\') + TP_String('"')
    else if c = '\' then
      Result := Result + TP_String('\') + TP_String('\')
    else if c = #10 then
      Result := Result + TP_String('\') + TP_String('n')
    else if c = #13 then
      Result := Result + TP_String('\') + TP_String('r')
    else if c = #9 then
      Result := Result + TP_String('\') + TP_String('t')
    else if (Ord(c) < 32) or (Ord(c) > 126) then
    begin
      Code := Ord(c);
      Result := Result + TP_String('\') + TP_String('u') +
        TP_String(IntToHex(Code, 4));
    end
    else
      Result.Append(c);
  end;
  Result := Result + TP_String('"');
end;

function JavaPackageName(const UnitName: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := TP_String('lingofuse.abi.');
  for i := 1 to UnitName.Len do
  begin
    c := UnitName[i];
    if (c >= 'A') and (c <= 'Z') then
      Result.Append(TP_Char(Ord(c) + 32))
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append(TP_Char('_'));
  end;
end;

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  if T.Len > 0 then
  begin
    if T[1] = '{' then
      T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;
  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then
      T := T.GetString(1, T.Len).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then
      T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
  end;
  Result := T;
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var
  i, j: integer;
  Line: TP_String;
begin
  Result := TP_String('');
  if Comment.Len = 0 then
    Exit;
  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do
      Inc(j);
    if j > i then
    begin
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);
      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
        end
        else
        begin
          if Line[1] = '*' then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if Line.Len > 0 then
          begin
            Result := Line;
            if Result.Len > 200 then
              Result := Result.GetString(1, 201);
            Exit;
          end;
        end;
      end;
    end;
    i := j;
    while (i <= Comment.Len) and
          ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
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
        Log(TP_String(PFormat(
          'Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text])));
        Break;
      end;
    if Supported and f.IsFunction and
       (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(TP_String(PFormat(
        'Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text])));
    end;
    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log(TP_String('Skipped: routine with empty Name'));
    end;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function BuildJavaParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := TP_String('');
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeJavaParamName(Params[i].Name, i);
    PTyp := ABI_Type_To_Java_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + TP_String(', ');
    Result := Result + PTyp + TP_String(' ') + PName;
  end;
end;

procedure EmitReadResultHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    private static int readResult_Int32(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt32();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static long readResult_Int64(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt64();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static long readResult_UInt32(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt32() & 0xFFFFFFFFL;');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static int readResult_UInt16(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt16() & 0xFFFF;');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static short readResult_Int16(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt16();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static byte readResult_Int8(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static long readResult_UInt64(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readInt64();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static float readResult_Single(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readSingle();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static double readResult_Double(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readDouble();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static String readResult_String(String apiName, DataHandle resp) {');
  Lines.Add('        if (resp.size() <= 0) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" returned empty response (timeout or target not found)");');
  Lines.Add('        }');
  Lines.Add('        resp.setPosition(0);');
  Lines.Add('        byte status;');
  Lines.Add('        try {');
  Lines.Add('            status = resp.readInt8();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (status)", t);');
  Lines.Add('        }');
  Lines.Add('        if (status != STATUS_OK) {');
  Lines.Add('            String err;');
  Lines.Add('            try { err = resp.readString(); } catch (Throwable t) { err = "<unreadable>"; }');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('        }');
  Lines.Add('        try {');
  Lines.Add('            return resp.readString();');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new EABIRemoteError("ABI call \"" + apiName + "\": response truncated (result)", t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSyncCall(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const CallFuncName: TP_String;
  const FirstArgDecl: TP_String;
  const FirstArgExpr: TP_String;
  const FrameworkCallExpr: TP_String);
var
  i: integer;
  PName, WriteStmt, RetDecl, ReadFunc: TP_String;
  ParamDecl, FullParamDecl: TP_String;
begin
  ParamDecl := BuildJavaParamDecl(F.Params);
  if ParamDecl.Len > 0 then
    FullParamDecl := FirstArgDecl + TP_String(', ') + ParamDecl
  else
    FullParamDecl := FirstArgDecl;

  RetDecl := ABI_Type_To_Java_Decl(F.ReturnType);
  ReadFunc := ABI_Type_To_Java_Read_Result_Func(F.ReturnType);

  Lines.Add('    public static ' + RetDecl.Text + ' ' + CallFuncName.Text +
    '(' + FullParamDecl.Text + ') {');
  Lines.Add('        try (DataHandle _req = new DataHandle(' +
    JavaStrLit(ApiName).Text + ')) {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJavaParamName(F.Params[i].Name, i);
    WriteStmt := ABI_Type_To_Java_Write_Stmt(F.Params[i].PascalType, PName);
    Lines.Add('            _req.' + WriteStmt.Text + ';');
  end;
  Lines.Add('            try (DataHandle _resp = ' + FrameworkCallExpr.Text +
    '(' + FirstArgExpr.Text + ', _req, ABI_TIMEOUT)) {');
  Lines.Add('                return ' + ReadFunc.Text + '(' +
    JavaStrLit(ApiName).Text + ', _resp);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncCall(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const CallFuncName: TP_String;
  const FirstArgDecl: TP_String;
  const FirstArgExpr: TP_String;
  const FrameworkAsyncCallExpr: TP_String);
var
  i: integer;
  PName, WriteStmt, BoxedType, ReadFunc: TP_String;
  ParamDecl, HandlerParam, FullParamDecl: TP_String;
  NotDispatchedMsg: TP_String;
begin
  ParamDecl := BuildJavaParamDecl(F.Params);
  BoxedType := ABI_Type_To_Java_Boxed(F.ReturnType);
  HandlerParam := TP_String('TypedAsyncResultHandler<') + BoxedType +
    TP_String('> handler');
  if ParamDecl.Len > 0 then
    FullParamDecl := FirstArgDecl + TP_String(', ') + ParamDecl +
      TP_String(', ') + HandlerParam
  else
    FullParamDecl := FirstArgDecl + TP_String(', ') + HandlerParam;

  ReadFunc := ABI_Type_To_Java_Read_Result_Func(F.ReturnType);
  NotDispatchedMsg := JavaStrLit(
    TP_String('async call to "') + ApiName + TP_String('" was not dispatched'));

  Lines.Add('    public static boolean ' + CallFuncName.Text +
    '(' + FullParamDecl.Text + ') {');
  Lines.Add('        DataHandle _req = new DataHandle(' +
    JavaStrLit(ApiName).Text + ');');
  Lines.Add('        try {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJavaParamName(F.Params[i].Name, i);
    WriteStmt := ABI_Type_To_Java_Write_Stmt(F.Params[i].PascalType, PName);
    Lines.Add('            _req.' + WriteStmt.Text + ';');
  end;
  Lines.Add('            boolean _dispatched = ' + FrameworkAsyncCallExpr.Text +
    '(' + FirstArgExpr.Text + ', _req, (_res, _err) -> {');
  Lines.Add('                if (_err != null) {');
  Lines.Add('                    handler.onResult(null, _err);');
  Lines.Add('                    return;');
  Lines.Add('                }');
  Lines.Add('                try {');
  Lines.Add('                    ' + BoxedType.Text + ' _value = ' +
    ReadFunc.Text + '(' + JavaStrLit(ApiName).Text + ', _res);');
  Lines.Add('                    handler.onResult(_value, null);');
  Lines.Add('                } catch (Throwable _t) {');
  Lines.Add('                    handler.onResult(null, _t);');
  Lines.Add('                }');
  Lines.Add('            });');
  Lines.Add('            if (!_dispatched) {');
  Lines.Add('                handler.onResult(null, new EABIRemoteError(' +
    NotDispatchedMsg.Text + '));');
  Lines.Add('            }');
  Lines.Add('            return _dispatched;');
  Lines.Add('        } finally {');
  Lines.Add('            _req.close();');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitNotify(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const NotifyFuncName: TP_String;
  const FirstArgDecl: TP_String;
  const FirstArgExpr: TP_String;
  const FrameworkNotifyExpr: TP_String);
var
  i: integer;
  PName, WriteStmt, ParamDecl, FullParamDecl: TP_String;
begin
  ParamDecl := BuildJavaParamDecl(F.Params);
  if ParamDecl.Len > 0 then
    FullParamDecl := FirstArgDecl + TP_String(', ') + ParamDecl
  else
    FullParamDecl := FirstArgDecl;

  Lines.Add('    public static void ' + NotifyFuncName.Text +
    '(' + FullParamDecl.Text + ') {');
  Lines.Add('        try (DataHandle _req = new DataHandle(' +
    JavaStrLit(ApiName).Text + ')) {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJavaParamName(F.Params[i].Name, i);
    WriteStmt := ABI_Type_To_Java_Write_Stmt(F.Params[i].PascalType, PName);
    Lines.Add('            _req.' + WriteStmt.Text + ';');
  end;
  Lines.Add('            ' + FrameworkNotifyExpr.Text + '(' +
    FirstArgExpr.Text + ', _req);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

function GenerateABICallJavaCode(
  Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, PackageName, ClassName, AppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log(TP_String('GenerateABICallJavaCode: Model is nil'));
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log(TP_String('GenerateABICallJavaCode: UnitName is empty'));
    Exit;
  end;

  PackageName := JavaPackageName(UnitName);
  ClassName := UnitName + TP_String('AbiCall');
  AppName := MakeApiName(UnitName) + TP_String('_abi');

  Log(TP_String(PFormat('Generating Java ABI call for unit "%s"',
    [UnitName.Text])));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log(TP_String('No supported routines; generating an empty skeleton.'));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('package ' + PackageName.Text + ';');
    Lines.Add('');
    Lines.Add('import lingofuse.DataHandle;');
    Lines.Add('import lingofuse.Framework;');
    Lines.Add('import lingofuse.async.TypedAsyncResultHandler;');
    Lines.Add('');
    Lines.Add('public final class ' + ClassName.Text + ' {');
    Lines.Add('');
    Lines.Add('    public static String ABI_TARGET_APP = ' +
      JavaStrLit(AppName).Text + ';');
    Lines.Add('    public static long ABI_TIMEOUT = 5000L;');
    Lines.Add('');
    Lines.Add('    public static final byte STATUS_OK    = 0x00;');
    Lines.Add('    public static final byte STATUS_ERROR = (byte) 0xFF;');
    Lines.Add('');
    Lines.Add('    public static final int ABI_ERR_CREATE_FAILED       = 1;');
    Lines.Add('    public static final int ABI_ERR_ASYNC_SUBMIT_FAILED = 2;');
    Lines.Add('    public static final int ABI_ERR_DISPATCH_EXCEPTION  = 3;');
    Lines.Add('    public static final int ABI_ERR_TIMEOUT             = 4;');
    Lines.Add('    public static final int ABI_ERR_EMPTY_RESPONSE      = 5;');
    Lines.Add('    public static final int ABI_ERR_TRUNCATED_STATUS    = 6;');
    Lines.Add('    public static final int ABI_ERR_REMOTE_ERROR        = 7;');
    Lines.Add('    public static final int ABI_ERR_TRUNCATED_RESULT    = 8;');
    Lines.Add('');
    Lines.Add('    public static final class EABIRemoteError extends RuntimeException {');
    Lines.Add('        public EABIRemoteError(String message) {');
    Lines.Add('            super(message);');
    Lines.Add('        }');
    Lines.Add('        public EABIRemoteError(String message, Throwable cause) {');
    Lines.Add('            super(message, cause);');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private ' + ClassName.Text + '() {');
    Lines.Add('    }');
    Lines.Add('');

    EmitReadResultHelpers(Lines);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);

      if F.IsFunction then
      begin
        EmitSyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName,
          TP_String('String appName'),
          TP_String('appName'),
          TP_String('Framework.call'));
        EmitAsyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('Async'),
          TP_String('String appName'),
          TP_String('appName'),
          TP_String('Framework.asyncCall'));
        EmitAsyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('SequencedAsync'),
          TP_String('String appName'),
          TP_String('appName'),
          TP_String('Framework.asyncSequencedCall'));
        EmitSyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('ByUid'),
          TP_String('byte[] uidBytes'),
          TP_String('uidBytes'),
          TP_String('Framework.uidCall'));
        EmitAsyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('AsyncByUid'),
          TP_String('byte[] uidBytes'),
          TP_String('uidBytes'),
          TP_String('Framework.asyncUidCall'));
        EmitAsyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('SequencedAsyncByUid'),
          TP_String('byte[] uidBytes'),
          TP_String('uidBytes'),
          TP_String('Framework.asyncUidSequencedCall'));
        EmitSyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('ByP2PName'),
          TP_String('String group'),
          TP_String('group'),
          TP_String('Framework.p2pCall'));
        EmitAsyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('AsyncByP2PName'),
          TP_String('String group'),
          TP_String('group'),
          TP_String('Framework.asyncP2pCall'));
        EmitAsyncCall(Lines, ApiName, F,
          TP_String('call') + ApiName + TP_String('SequencedAsyncByP2PName'),
          TP_String('String group'),
          TP_String('group'),
          TP_String('Framework.asyncP2pSequencedCall'));
      end
      else
      begin
        EmitNotify(Lines, ApiName, F,
          TP_String('notify') + ApiName,
          TP_String('String appName'),
          TP_String('appName'),
          TP_String('Framework.notify'));
        EmitNotify(Lines, ApiName, F,
          TP_String('notify') + ApiName + TP_String('Sequenced'),
          TP_String('String appName'),
          TP_String('appName'),
          TP_String('Framework.sequencedNotify'));
        EmitNotify(Lines, ApiName, F,
          TP_String('notify') + ApiName + TP_String('ByUid'),
          TP_String('byte[] uidBytes'),
          TP_String('uidBytes'),
          TP_String('Framework.uidNotify'));
        EmitNotify(Lines, ApiName, F,
          TP_String('notify') + ApiName + TP_String('SequencedByUid'),
          TP_String('byte[] uidBytes'),
          TP_String('uidBytes'),
          TP_String('Framework.uidSequencedNotify'));
        EmitNotify(Lines, ApiName, F,
          TP_String('notify') + ApiName + TP_String('ByP2PName'),
          TP_String('String group'),
          TP_String('group'),
          TP_String('Framework.p2pNotify'));
        EmitNotify(Lines, ApiName, F,
          TP_String('notify') + ApiName + TP_String('SequencedByP2PName'),
          TP_String('String group'),
          TP_String('group'),
          TP_String('Framework.p2pSequencedNotify'));
      end;
    end;

    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(TP_String(PFormat('Generated %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)])));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'java',
    'xxxAbiCall.java',
    gkCall,
    'Java ABI call',
    @GenerateABICallJavaCode);

end.
