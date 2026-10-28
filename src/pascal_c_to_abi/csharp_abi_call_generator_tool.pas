unit csharp_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_CSharp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'int'
  else if T.Same('int64') then Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'uint'
  else if T.Same('word') then Result := 'ushort'
  else if T.Same('smallint') then Result := 'short'
  else if T.Same('byte') then Result := 'byte'
  else if T.Same('uint64') then Result := 'ulong'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'double'
  else if T.Same('single') then Result := 'float'
  else if IsStringABIType(T) then Result := 'string'
  else Result := '';
end;

function ABI_Type_To_CSharp_Reader_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'ReadInt32'
  else if T.Same('int64') then Result := 'ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'ReadUInt32'
  else if T.Same('word') then Result := 'ReadUInt16'
  else if T.Same('smallint') then Result := 'ReadInt16'
  else if T.Same('byte') then Result := 'ReadUInt8'
  else if T.Same('uint64') then Result := 'ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'ReadDouble'
  else if T.Same('single') then Result := 'ReadSingle'
  else if IsStringABIType(T) then Result := 'ReadString'
  else Result := '';
end;

function ABI_Type_To_CSharp_Writer_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'WriteInt32'
  else if T.Same('int64') then Result := 'WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'WriteUInt32'
  else if T.Same('word') then Result := 'WriteUInt16'
  else if T.Same('smallint') then Result := 'WriteInt16'
  else if T.Same('byte') then Result := 'WriteUInt8'
  else if T.Same('uint64') then Result := 'WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'WriteDouble'
  else if T.Same('single') then Result := 'WriteSingle'
  else if IsStringABIType(T) then Result := 'WriteString'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_CSharp_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsCSharpKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('base') or S.Same('bool') or
    S.Same('break') or S.Same('byte') or S.Same('case') or S.Same('catch') or
    S.Same('char') or S.Same('checked') or S.Same('class') or S.Same('const') or
    S.Same('continue') or S.Same('decimal') or S.Same('default') or S.Same('delegate') or
    S.Same('do') or S.Same('double') or S.Same('else') or S.Same('enum') or
    S.Same('event') or S.Same('explicit') or S.Same('extern') or S.Same('false') or
    S.Same('finally') or S.Same('fixed') or S.Same('float') or S.Same('for') or
    S.Same('foreach') or S.Same('goto') or S.Same('if') or S.Same('implicit') or
    S.Same('in') or S.Same('int') or S.Same('interface') or S.Same('internal') or
    S.Same('is') or S.Same('lock') or S.Same('long') or S.Same('namespace') or
    S.Same('new') or S.Same('null') or S.Same('object') or S.Same('operator') or
    S.Same('out') or S.Same('override') or S.Same('params') or S.Same('private') or
    S.Same('protected') or S.Same('public') or S.Same('readonly') or S.Same('ref') or
    S.Same('return') or S.Same('sbyte') or S.Same('sealed') or S.Same('short') or
    S.Same('sizeof') or S.Same('stackalloc') or S.Same('static') or S.Same('string') or
    S.Same('struct') or S.Same('switch') or S.Same('this') or S.Same('throw') or
    S.Same('true') or S.Same('try') or S.Same('typeof') or S.Same('uint') or
    S.Same('ulong') or S.Same('unchecked') or S.Same('unsafe') or S.Same('ushort') or
    S.Same('using') or S.Same('virtual') or S.Same('void') or S.Same('volatile') or
    S.Same('while');
end;

function IsReservedInternalName(const S: TP_String): boolean;
begin
  Result := S.Same('lfUid') or S.Same('lfP2PName') or
    S.Same('inHandle') or S.Same('outHandle') or
    S.Same('ex') or S.Same('ret') or
    S.Same('uid') or S.Same('p2pName') or
    S.Same('param') or S.Same('response') or
    S.Same('status') or S.Same('err') or
    S.Same('apiName') or S.Same('task');
end;

function MakeSafeCSharpParamName(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'p' + umlIntToStr(Index);
    Exit;
  end;

  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if IsCSharpKeyword(Result) then
    Result := Result + '_';

  if IsReservedInternalName(Result) then
    Result := Result + '_';
end;

function CSharpStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
    begin
      Result.Append('\');
      Result.Append('"');
    end
    else if c = '\' then
    begin
      Result.Append('\');
      Result.Append('\');
    end
    else if c = #10 then
    begin
      Result.Append('\');
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append('\');
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append('\');
      Result.Append('t');
    end
    else if c = #0 then
    begin
      Result.Append('\');
      Result.Append('0');
    end
    else
      Result.Append(c);
  end;
  Result.Append('"');
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

procedure EmitCommentLines(Lines: TPascalStringList; const Indent, Comment: TP_String);
var
  i, j: integer;
  Line: TP_String;
begin
  if Comment.Len = 0 then Exit;
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
        if Line[1] = '*' then
          Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
        if (Line.Len > 0) and (Line[1] = '*') then
          Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
        if Line.Len > 0 then
          Lines.Add(Indent + '// ' + Line.Text);
      end;
    end;
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
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
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
      Supported := False;
    if Supported and (f.Name.Len = 0) then
      Supported := False;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

procedure EmitCheckResponseHelpers(Lines: TPascalStringList);
begin
  Lines.Add('        private static void CheckResponse(DataHandle response, string apiName)');
  Lines.Add('        {');
  Lines.Add('            if (!response.IsValid || response.Size == 0)');
  Lines.Add('            {');
  Lines.Add('                throw new LingoFuseCallException(');
  Lines.Add('                    "ABI call \"" + apiName + "\" returned an empty response (timeout or target application not found).",');
  Lines.Add('                    targetApp: TargetApp,');
  Lines.Add('                    targetApi: apiName);');
  Lines.Add('            }');
  Lines.Add('            response.Position = 0;');
  Lines.Add('            byte status = response.ReadUInt8();');
  Lines.Add('            if (status != WireStatus.Ok)');
  Lines.Add('            {');
  Lines.Add('                string err = "";');
  Lines.Add('                try { err = response.ReadString(); } catch { }');
  Lines.Add('                throw new LingoFuseException(');
  Lines.Add('                    "ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        private static async Task<DataHandle> CheckResponseAsync(');
  Lines.Add('            Task<DataHandle> task, string apiName)');
  Lines.Add('        {');
  Lines.Add('            DataHandle response;');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                response = await task.ConfigureAwait(false);');
  Lines.Add('            }');
  Lines.Add('            catch (LingoFuseException)');
  Lines.Add('            {');
  Lines.Add('                throw;');
  Lines.Add('            }');
  Lines.Add('            catch (Exception ex)');
  Lines.Add('            {');
  Lines.Add('                throw new LingoFuseCallException(');
  Lines.Add('                    "ABI call \"" + apiName + "\" failed to dispatch: " + ex.Message,');
  Lines.Add('                    targetApp: TargetApp,');
  Lines.Add('                    targetApi: apiName);');
  Lines.Add('            }');
  Lines.Add('            if (!response.IsValid || response.Size == 0)');
  Lines.Add('            {');
  Lines.Add('                response.Dispose();');
  Lines.Add('                throw new LingoFuseCallException(');
  Lines.Add('                    "ABI call \"" + apiName + "\" returned an empty response (timeout or target application not found).",');
  Lines.Add('                    targetApp: TargetApp,');
  Lines.Add('                    targetApi: apiName);');
  Lines.Add('            }');
  Lines.Add('            response.Position = 0;');
  Lines.Add('            byte status = response.ReadUInt8();');
  Lines.Add('            if (status != WireStatus.Ok)');
  Lines.Add('            {');
  Lines.Add('                string err = "";');
  Lines.Add('                try { err = response.ReadString(); } catch { }');
  Lines.Add('                response.Dispose();');
  Lines.Add('                throw new LingoFuseException(');
  Lines.Add('                    "ABI call \"" + apiName + "\" failed: " + err);');
  Lines.Add('            }');
  Lines.Add('            return response;');
  Lines.Add('        }');
end;

procedure EmitFunctionSync(
  Lines: TPascalStringList;
  const MethodName, ApiName, FirstParamDecl, FirstParamExpr, CallFunc: TP_String;
  const F: TFunctionStructure);
var
  RetType, ParamList, WriterMethod: TP_String;
  i: integer;
begin
  RetType := ABI_Type_To_CSharp_Decl(F.ReturnType);
  ParamList := FirstParamDecl;
  for i := 0 to High(F.Params) do
  begin
    if ParamList <> '' then ParamList := ParamList + ', ';
    ParamList := ParamList + ABI_Type_To_CSharp_Decl(F.Params[i].PascalType) + ' ' +
      MakeSafeCSharpParamName(F.Params[i].Name, i);
  end;

  Lines.Add('        public static ' + RetType + ' ' + MethodName + '(' + ParamList + ')');
  Lines.Add('        {');
  Lines.Add('            using (var param = new DataHandle(' + CSharpStrLit(ApiName) + '))');
  Lines.Add('            {');
  for i := 0 to High(F.Params) do
  begin
    WriterMethod := ABI_Type_To_CSharp_Writer_Method(F.Params[i].PascalType);
    Lines.Add('                param.' + WriterMethod + '(' + MakeSafeCSharpParamName(F.Params[i].Name, i) + ');');
  end;
  if Length(F.Params) > 0 then
    Lines.Add('');
  if FirstParamExpr = '' then
    Lines.Add('                using (var response = ' + CallFunc + '(TargetApp, param, Timeout))')
  else
    Lines.Add('                using (var response = ' + CallFunc + '(' + FirstParamExpr + ', param, Timeout))');
  Lines.Add('                {');
  Lines.Add('                    CheckResponse(response, ' + CSharpStrLit(ApiName) + ');');
  Lines.Add('                    return response.' + ABI_Type_To_CSharp_Reader_Method(F.ReturnType) + '();');
  Lines.Add('                }');
  Lines.Add('            }');
  Lines.Add('        }');
end;

procedure EmitFunctionAsync(
  Lines: TPascalStringList;
  const MethodName, ApiName, FirstParamDecl, FirstParamExpr, CallFunc: TP_String;
  const F: TFunctionStructure);
var
  RetType, ParamList, WriterMethod: TP_String;
  i: integer;
begin
  RetType := ABI_Type_To_CSharp_Decl(F.ReturnType);
  ParamList := FirstParamDecl;
  for i := 0 to High(F.Params) do
  begin
    if ParamList <> '' then ParamList := ParamList + ', ';
    ParamList := ParamList + ABI_Type_To_CSharp_Decl(F.Params[i].PascalType) + ' ' +
      MakeSafeCSharpParamName(F.Params[i].Name, i);
  end;

  Lines.Add('        public static async Task<' + RetType + '> ' + MethodName + '(' + ParamList + ')');
  Lines.Add('        {');
  Lines.Add('            using (var param = new DataHandle(' + CSharpStrLit(ApiName) + '))');
  Lines.Add('            {');
  for i := 0 to High(F.Params) do
  begin
    WriterMethod := ABI_Type_To_CSharp_Writer_Method(F.Params[i].PascalType);
    Lines.Add('                param.' + WriterMethod + '(' + MakeSafeCSharpParamName(F.Params[i].Name, i) + ');');
  end;
  if Length(F.Params) > 0 then
    Lines.Add('');
  if FirstParamExpr = '' then
    Lines.Add('                using (var response = await CheckResponseAsync(' + CallFunc + '(TargetApp, param), ' + CSharpStrLit(ApiName) + ').ConfigureAwait(false))')
  else
    Lines.Add('                using (var response = await CheckResponseAsync(' + CallFunc + '(' + FirstParamExpr + ', param), ' + CSharpStrLit(ApiName) + ').ConfigureAwait(false))');
  Lines.Add('                {');
  Lines.Add('                    return response.' + ABI_Type_To_CSharp_Reader_Method(F.ReturnType) + '();');
  Lines.Add('                }');
  Lines.Add('            }');
  Lines.Add('        }');
end;

procedure EmitProcedureNotify(
  Lines: TPascalStringList;
  const MethodName, ApiName, FirstParamDecl, FirstParamExpr, NotifyFunc: TP_String;
  const F: TFunctionStructure);
var
  ParamList, WriterMethod: TP_String;
  i: integer;
begin
  ParamList := FirstParamDecl;
  for i := 0 to High(F.Params) do
  begin
    if ParamList <> '' then ParamList := ParamList + ', ';
    ParamList := ParamList + ABI_Type_To_CSharp_Decl(F.Params[i].PascalType) + ' ' +
      MakeSafeCSharpParamName(F.Params[i].Name, i);
  end;

  Lines.Add('        public static void ' + MethodName + '(' + ParamList + ')');
  Lines.Add('        {');
  Lines.Add('            using (var param = new DataHandle(' + CSharpStrLit(ApiName) + '))');
  Lines.Add('            {');
  for i := 0 to High(F.Params) do
  begin
    WriterMethod := ABI_Type_To_CSharp_Writer_Method(F.Params[i].PascalType);
    Lines.Add('                param.' + WriterMethod + '(' + MakeSafeCSharpParamName(F.Params[i].Name, i) + ');');
  end;
  if FirstParamExpr = '' then
    Lines.Add('                ' + NotifyFunc + '(TargetApp, param);')
  else
    Lines.Add('                ' + NotifyFunc + '(' + FirstParamExpr + ', param);');
  Lines.Add('            }');
  Lines.Add('        }');
end;

function GenerateABICallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
    Exit;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
    Exit;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi_call';
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C# ABI call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('using System;');
    Lines.Add('using System.Threading.Tasks;');
    Lines.Add('using LingoFuse;');
    Lines.Add('');
    Lines.Add('namespace ' + NsName);
    Lines.Add('{');
    Lines.Add('    internal static class WireStatus');
    Lines.Add('    {');
    Lines.Add('        public const byte Ok = 0x00;');
    Lines.Add('        public const byte Error = 0xFF;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    public static class ABI');
    Lines.Add('    {');
    Lines.Add('        public static string TargetApp = ' + CSharpStrLit(TargetAppName) + ';');
    Lines.Add('        public static ulong Timeout = 5000;');
    Lines.Add('');
    EmitCheckResponseHelpers(Lines);
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := MakeApiName(f.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      if i > 0 then
        Lines.Add('');

      EmitCommentLines(Lines, '        ', f.Comment);

      if f.IsFunction then
      begin
        EmitFunctionSync(Lines, ApiName, ApiName, '', '', 'Framework.Call', f);
        Lines.Add('');
        EmitFunctionAsync(Lines, ApiName + '_Async', ApiName, '', '', 'Framework.CallAsync', f);
        Lines.Add('');
        EmitFunctionAsync(Lines, ApiName + '_AsyncSequenced', ApiName, '', '', 'Framework.CallSequencedAsync', f);
        Lines.Add('');
        EmitFunctionSync(Lines, ApiName + '_UID_Call', ApiName, 'P2PUid uid', 'uid', 'Framework.CallByUid', f);
        Lines.Add('');
        EmitFunctionAsync(Lines, ApiName + '_UID_Async', ApiName, 'P2PUid uid', 'uid', 'Framework.CallByUidAsync', f);
        Lines.Add('');
        EmitFunctionAsync(Lines, ApiName + '_UID_AsyncSequenced', ApiName, 'P2PUid uid', 'uid', 'Framework.CallByUidSequencedAsync', f);
        Lines.Add('');
        EmitFunctionSync(Lines, ApiName + '_P2PName_Call', ApiName, 'string p2pName', 'p2pName', 'Framework.CallByP2PName', f);
        Lines.Add('');
        EmitFunctionAsync(Lines, ApiName + '_P2PName_Async', ApiName, 'string p2pName', 'p2pName', 'Framework.CallByP2PNameAsync', f);
        Lines.Add('');
        EmitFunctionAsync(Lines, ApiName + '_P2PName_AsyncSequenced', ApiName, 'string p2pName', 'p2pName', 'Framework.CallByP2PNameSequencedAsync', f);
      end
      else
      begin
        EmitProcedureNotify(Lines, ApiName, ApiName, '', '', 'Framework.Notify', f);
        Lines.Add('');
        EmitProcedureNotify(Lines, ApiName + '_SequencedNotify', ApiName, '', '', 'Framework.SequencedNotify', f);
        Lines.Add('');
        EmitProcedureNotify(Lines, ApiName + '_UID_Notify', ApiName, 'P2PUid uid', 'uid', 'Framework.NotifyByUid', f);
        Lines.Add('');
        EmitProcedureNotify(Lines, ApiName + '_UID_SequencedNotify', ApiName, 'P2PUid uid', 'uid', 'Framework.SequencedNotifyByUid', f);
        Lines.Add('');
        EmitProcedureNotify(Lines, ApiName + '_P2PName_Notify', ApiName, 'string p2pName', 'p2pName', 'Framework.NotifyByP2PName', f);
        Lines.Add('');
        EmitProcedureNotify(Lines, ApiName + '_P2PName_SequencedNotify', ApiName, 'string p2pName', 'p2pName', 'Framework.SequencedNotifyByP2PName', f);
      end;
    end;

    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the C# call module.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'csharp',
    'xxx_abi_call.cs',
    gkCall,
    'C# ABI call library',
    @GenerateABICallCsharpCode);

end.
