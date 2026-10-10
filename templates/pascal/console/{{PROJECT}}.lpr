program {{PROJECT}};

{$MODE OBJFPC}{$H+}

uses
  SysUtils,
  Options,
  Greeter;

{ The arguments after the program's name, as the parser takes them. }
function Arguments: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, ParamCount);
  for Index := 1 to ParamCount do
    Result[Index - 1] := ParamStr(Index);
end;

var
  Parsed: TOptions;
  Line: string;
begin
  try
    Parsed := ParseOptions(Arguments);
  except
    on E: EOptionError do
    begin
      WriteLn(StdErr, '{{PROJECT}}: ', E.Message);
      WriteLn(StdErr, UsageText('{{PROJECT}}'));
      Halt(2);
    end;
  end;

  if Parsed.ShowHelp then
  begin
    WriteLn(UsageText('{{PROJECT}}'));
    Exit;
  end;
  if Parsed.ShowVersion then
  begin
    WriteLn('{{PROJECT}} ', ProgramVersion);
    Exit;
  end;

  try
    if Parsed.Verbose then
    begin
      WriteLn(StdErr, Format('greeting %s, %d time(s)', [Parsed.Name, Parsed.Count]));
      { On a pipe StdErr waits for a full buffer: say it before the output. }
      Flush(StdErr);
    end;
    for Line in Greetings(Parsed) do
      WriteLn(Line);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, '{{PROJECT}}: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
