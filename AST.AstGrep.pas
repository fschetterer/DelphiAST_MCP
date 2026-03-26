unit AST.AstGrep;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.JSON,
  System.Generics.Collections, System.SyncObjs;

type
  TAstGrepMetaVar = record
    Name: string;
    Text: string;
  end;

  TAstGrepMatch = record
    FilePath: string;
    Text: string;
    Line: Integer;
    Column: Integer;
    EndLine: Integer;
    EndColumn: Integer;
    MetaVars: TArray<TAstGrepMetaVar>;
    HasError: Boolean;
  end;

  TAstGrepResult = record
    Matches: TArray<TAstGrepMatch>;
    CandidateFiles: TArray<string>;
    ErrorFiles: TArray<string>;
    Success: Boolean;
    ErrorMessage: string;
    ElapsedMs: Cardinal;
  end;

  TAstGrepConfig = record
    ExePath: string;
    ConfigPath: string;
    TimeoutMs: Cardinal;
    IsAvailable: Boolean;
    Version: string;
  end;

  TAstGrepWrapper = class
  private
    FConfig: TAstGrepConfig;
    FLock: TLightweightMREW;
    function ExecuteProcess(const ACommandLine, AWorkDir: string;
      ATimeoutMs: Cardinal; out AOutput: string; out AExitCode: Integer): Boolean;
    function ParseJsonOutput(const AJsonText: string): TArray<TAstGrepMatch>;
    procedure CollectFileInfo(const AMatches: TArray<TAstGrepMatch>;
      out ACandidateFiles, AErrorFiles: TArray<string>);
    function BuildCommandLine(const APattern, ASearchPath: string;
      AUseJson: Boolean): string;
  public
    constructor Create;

    procedure Configure(const AExePath, AConfigPath: string;
      ATimeoutMs: Cardinal = 30000);
    function Probe: Boolean;

    function RunPattern(const APattern, ASearchPath: string;
      AMaxResults: Integer = 0): TAstGrepResult;

    function FindCandidateFiles(const AIdentifier, ASearchPath: string): TAstGrepResult;

    property Config: TAstGrepConfig read FConfig;
    property IsAvailable: Boolean read FConfig.IsAvailable;
  end;

implementation

{ TAstGrepWrapper }

constructor TAstGrepWrapper.Create;
begin
  inherited;
  FConfig.ExePath := 'ast-grep';
  FConfig.ConfigPath := '';
  FConfig.TimeoutMs := 30000;
  FConfig.IsAvailable := False;
  FConfig.Version := '';
end;

procedure TAstGrepWrapper.Configure(const AExePath, AConfigPath: string;
  ATimeoutMs: Cardinal);
begin
  FLock.BeginWrite;
  try
    FConfig.ExePath := AExePath;
    FConfig.ConfigPath := AConfigPath;
    FConfig.TimeoutMs := ATimeoutMs;
    FConfig.IsAvailable := False;
    FConfig.Version := '';
  finally
    FLock.EndWrite;
  end;
end;

function TAstGrepWrapper.Probe: Boolean;
var
  Output: string;
  ExitCode: Integer;
begin
  Result := False;
  FLock.BeginWrite;
  try
    FConfig.IsAvailable := False;
    FConfig.Version := '';

    if not ExecuteProcess('cmd /c ""' + FConfig.ExePath + '" --version""', '', 5000,
      Output, ExitCode) then
      Exit;

    if ExitCode <> 0 then
      Exit;

    FConfig.Version := Trim(Output);
    // Verify config path has sgconfig.yml + pascal.dll
    if (FConfig.ConfigPath <> '') and not FileExists(FConfig.ConfigPath) then
    begin
      WriteLn(ErrOutput, '[ast-grep] Config not found: ' + FConfig.ConfigPath);
      Exit;
    end;

    FConfig.IsAvailable := True;
    Result := True;
  finally
    FLock.EndWrite;
  end;
end;

function TAstGrepWrapper.BuildCommandLine(const APattern, ASearchPath: string;
  AUseJson: Boolean): string;
begin
  Result := 'cmd /c ""' + FConfig.ExePath + '" run';
  if FConfig.ConfigPath <> '' then
    Result := Result + ' -c "' + FConfig.ConfigPath + '"';
  Result := Result + ' --pattern "' + APattern + '" -l pascal';
  if AUseJson then
    Result := Result + ' --json';
  if ASearchPath <> '' then
    Result := Result + ' "' + ASearchPath + '"';
  Result := Result + '"';  // Close outer cmd /c quote
end;

function TAstGrepWrapper.ExecuteProcess(const ACommandLine, AWorkDir: string;
  ATimeoutMs: Cardinal; out AOutput: string; out AExitCode: Integer): Boolean;
var
  SI: TStartupInfoW;
  PI: TProcessInformation;
  SA: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  Buffer: TBytes;
  BytesRead, TotalSize: DWORD;
  WaitResult: DWORD;
  OutputBuilder: TStringBuilder;
  WorkDir: PWideChar;
begin
  Result := False;
  AOutput := '';
  AExitCode := -1;

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then
    Exit;
  try
    // Don't let child inherit the read end
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.hStdOutput := WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := 0;
    SI.wShowWindow := SW_HIDE;

    FillChar(PI, SizeOf(PI), 0);

    if AWorkDir <> '' then
      WorkDir := PWideChar(AWorkDir)
    else
      WorkDir := nil;

    if not CreateProcessW(nil, PWideChar(ACommandLine), nil, nil, True,
      CREATE_NO_WINDOW, nil, WorkDir, SI, PI) then
      Exit;

    try
      // Close write end in parent so ReadFile will return when child exits
      CloseHandle(WritePipe);
      WritePipe := 0;

      // Read all output
      SetLength(Buffer, 65536);
      OutputBuilder := TStringBuilder.Create;
      try
        repeat
          BytesRead := 0;
          if not ReadFile(ReadPipe, Buffer[0], Length(Buffer), BytesRead, nil) then
            Break;
          if BytesRead > 0 then
            OutputBuilder.Append(TEncoding.UTF8.GetString(Buffer, 0, BytesRead));
        until BytesRead = 0;
        AOutput := OutputBuilder.ToString;
      finally
        OutputBuilder.Free;
      end;

      // Wait for process with timeout
      WaitResult := WaitForSingleObject(PI.hProcess, ATimeoutMs);
      if WaitResult = WAIT_TIMEOUT then
      begin
        TerminateProcess(PI.hProcess, 1);
        WaitForSingleObject(PI.hProcess, 1000);
        Exit;
      end;

      GetExitCodeProcess(PI.hProcess, DWORD(AExitCode));
      Result := True;
    finally
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
    end;
  finally
    CloseHandle(ReadPipe);
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
  end;
end;

function TAstGrepWrapper.ParseJsonOutput(const AJsonText: string): TArray<TAstGrepMatch>;
var
  JsonValue: TJSONValue;
  JsonArr: TJSONArray;
  MatchObj, RangeObj, StartObj, EndObj, MetaObj, SingleObj, VarObj: TJSONObject;
  I: Integer;
  Match: TAstGrepMatch;
  MatchList: TList<TAstGrepMatch>;
  Pair: TJSONPair;
begin
  Result := nil;
  if AJsonText = '' then
    Exit;

  JsonValue := TJSONObject.ParseJSONValue(AJsonText);
  if JsonValue = nil then
    Exit;

  try
    if not (JsonValue is TJSONArray) then
      Exit;

    JsonArr := TJSONArray(JsonValue);
    MatchList := TList<TAstGrepMatch>.Create;
    try
      for I := 0 to JsonArr.Count - 1 do
      begin
        if not (JsonArr.Items[I] is TJSONObject) then
          Continue;

        MatchObj := TJSONObject(JsonArr.Items[I]);
        FillChar(Match, SizeOf(Match), 0);
        Match.FilePath := MatchObj.GetValue<string>('file', '');
        Match.Text := MatchObj.GetValue<string>('text', '');

        // Parse range
        if MatchObj.TryGetValue<TJSONObject>('range', RangeObj) then
        begin
          if RangeObj.TryGetValue<TJSONObject>('start', StartObj) then
          begin
            Match.Line := StartObj.GetValue<Integer>('line', 0);
            Match.Column := StartObj.GetValue<Integer>('column', 0);
          end;
          if RangeObj.TryGetValue<TJSONObject>('end', EndObj) then
          begin
            Match.EndLine := EndObj.GetValue<Integer>('line', 0);
            Match.EndColumn := EndObj.GetValue<Integer>('column', 0);
          end;
        end;

        // Parse metaVariables.single
        if MatchObj.TryGetValue<TJSONObject>('metaVariables', MetaObj) then
        begin
          if MetaObj.TryGetValue<TJSONObject>('single', SingleObj) then
          begin
            SetLength(Match.MetaVars, SingleObj.Count);
            var VarIdx := 0;
            for Pair in SingleObj do
            begin
              Match.MetaVars[VarIdx].Name := Pair.JsonString.Value;
              if Pair.JsonValue is TJSONObject then
                Match.MetaVars[VarIdx].Text :=
                  TJSONObject(Pair.JsonValue).GetValue<string>('text', '')
              else
                Match.MetaVars[VarIdx].Text := Pair.JsonValue.Value;
              Inc(VarIdx);
            end;
          end;
        end;

        // Check for ERROR in matched text (indicates parse failure)
        Match.HasError := Pos('ERROR', Match.Text) > 0;

        MatchList.Add(Match);
      end;

      Result := MatchList.ToArray;
    finally
      MatchList.Free;
    end;
  finally
    JsonValue.Free;
  end;
end;

procedure TAstGrepWrapper.CollectFileInfo(const AMatches: TArray<TAstGrepMatch>;
  out ACandidateFiles, AErrorFiles: TArray<string>);
var
  CandidateSet, ErrorSet: TDictionary<string, Boolean>;
  Match: TAstGrepMatch;
  Key: string;
begin
  CandidateSet := TDictionary<string, Boolean>.Create;
  ErrorSet := TDictionary<string, Boolean>.Create;
  try
    for Match in AMatches do
    begin
      Key := LowerCase(Match.FilePath);
      CandidateSet.AddOrSetValue(Key, True);
      if Match.HasError then
        ErrorSet.AddOrSetValue(Key, True);
    end;

    ACandidateFiles := CandidateSet.Keys.ToArray;
    AErrorFiles := ErrorSet.Keys.ToArray;
  finally
    CandidateSet.Free;
    ErrorSet.Free;
  end;
end;

function TAstGrepWrapper.RunPattern(const APattern, ASearchPath: string;
  AMaxResults: Integer): TAstGrepResult;
var
  CmdLine, Output: string;
  ExitCode: Integer;
  StartTick: Cardinal;
begin
  FillChar(Result, SizeOf(Result), 0);

  FLock.BeginRead;
  try
    if not FConfig.IsAvailable then
    begin
      Result.ErrorMessage := 'ast-grep is not available';
      Exit;
    end;
    CmdLine := BuildCommandLine(APattern, ASearchPath, True);
  finally
    FLock.EndRead;
  end;

  StartTick := GetTickCount;

  if not ExecuteProcess(CmdLine, '', FConfig.TimeoutMs, Output, ExitCode) then
  begin
    Result.ErrorMessage := 'Failed to execute ast-grep';
    Result.ElapsedMs := GetTickCount - StartTick;
    Exit;
  end;

  Result.ElapsedMs := GetTickCount - StartTick;

  // ast-grep returns exit code 0 for matches, 1 for no matches
  if not (ExitCode in [0, 1]) then
  begin
    Result.ErrorMessage := 'ast-grep exited with code ' + IntToStr(ExitCode) +
      ': ' + Copy(Output, 1, 500);
    Exit;
  end;

  if ExitCode = 1 then
  begin
    // No matches — still a success
    Result.Success := True;
    Exit;
  end;

  Result.Matches := ParseJsonOutput(Output);
  CollectFileInfo(Result.Matches, Result.CandidateFiles, Result.ErrorFiles);

  // Truncate if max_results specified
  if (AMaxResults > 0) and (Length(Result.Matches) > AMaxResults) then
    SetLength(Result.Matches, AMaxResults);

  Result.Success := True;
end;

function TAstGrepWrapper.FindCandidateFiles(const AIdentifier,
  ASearchPath: string): TAstGrepResult;
begin
  // Same as RunPattern but we only care about the file lists
  Result := RunPattern(AIdentifier, ASearchPath, 0);
end;

end.
