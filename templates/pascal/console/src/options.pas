{ The command line: what the program was asked to do. It is read from
  an array of strings, not from ParamStr, so the tests can hand it any
  command line they like. }
unit Options;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils;

const
  ProgramVersion = '0.1.0';

type
  { What the command line asked for. }
  TOptions = record
    Name: string;         { Who to greet. }
    Count: Integer;       { How many times, from 1 up. }
    Verbose: Boolean;     { Say what is being done, on stderr. }
    ShowHelp: Boolean;    { Print the usage and stop. }
    ShowVersion: Boolean; { Print the version and stop. }
  end;

  { Why a command line could not be read. }
  TOptionErrorKind = (oeUnknownOption, oeMissingValue, oeUnexpectedValue,
                      oeBadNumber);

  EOptionError = class(Exception)
  private
    FKind: TOptionErrorKind;
  public
    constructor Create(AKind: TOptionErrorKind; const AMessage: string);
    property Kind: TOptionErrorKind read FKind;
  end;

{ The options AArguments give, the program's own name not among them.
  A value follows its option, --name ada, or joins it, --name=ada.
  Raises EOptionError on an option it does not know, one missing its
  value, a flag given a value, or a count that is not a whole number
  from 1 up. }
function ParseOptions(const AArguments: array of string): TOptions;

{ The usage, for --help and after an error: AProgram is the name the
  program is called by. }
function UsageText(const AProgram: string): string;

implementation

constructor EOptionError.Create(AKind: TOptionErrorKind; const AMessage: string);
begin
  inherited Create(AMessage);
  FKind := AKind;
end;

function DefaultOptions: TOptions;
begin
  Result.Name := 'world';
  Result.Count := 1;
  Result.Verbose := False;
  Result.ShowHelp := False;
  Result.ShowVersion := False;
end;

function ParseOptions(const AArguments: array of string): TOptions;
var
  Index: Integer;
  Option, Joined, Text: string;
  Separator: SizeInt;
  HasJoined: Boolean;

  { The value of Option: the part after its =, else the next argument. }
  function TakeValue: string;
  begin
    if HasJoined then
      Exit(Joined);
    if Index >= High(AArguments) then
      raise EOptionError.Create(oeMissingValue, Option + ' needs a value');
    Inc(Index);
    Result := AArguments[Index];
  end;

  { Option is a flag: a value given to it is a mistake worth saying. }
  procedure NoValue;
  begin
    if HasJoined then
      raise EOptionError.Create(oeUnexpectedValue, Option + ' takes no value');
  end;

begin
  Result := DefaultOptions;
  Index := Low(AArguments);
  while Index <= High(AArguments) do
  begin
    Option := AArguments[Index];
    Separator := Pos('=', Option);
    HasJoined := (Separator > 0) and (Copy(Option, 1, 2) = '--');
    if HasJoined then
    begin
      Joined := Copy(Option, Separator + 1, MaxInt);
      Option := Copy(Option, 1, Separator - 1);
    end;

    if (Option = '-n') or (Option = '--name') then
      Result.Name := TakeValue
    else if (Option = '-c') or (Option = '--count') then
    begin
      Text := TakeValue;
      if not TryStrToInt(Text, Result.Count) or (Result.Count < 1) then
        raise EOptionError.Create(oeBadNumber,
          Format('%s needs a whole number from 1 up, not "%s"', [Option, Text]));
    end
    else if (Option = '-v') or (Option = '--verbose') then
    begin
      NoValue;
      Result.Verbose := True;
    end
    else if (Option = '-h') or (Option = '--help') then
    begin
      NoValue;
      Result.ShowHelp := True;
    end
    else if Option = '--version' then
    begin
      NoValue;
      Result.ShowVersion := True;
    end
    else
      raise EOptionError.Create(oeUnknownOption, 'unknown option ' + Option);

    Inc(Index);
  end;
end;

function UsageText(const AProgram: string): string;
begin
  Result :=
    'usage: ' + AProgram + ' [--name NAME] [--count N] [--verbose]' + LineEnding +
    LineEnding +
    '  -n, --name NAME   who to greet (world)' + LineEnding +
    '  -c, --count N     how many times, from 1 up (1)' + LineEnding +
    '  -v, --verbose     say what is being done, on stderr' + LineEnding +
    '  -h, --help        this text' + LineEnding +
    '      --version     the version';
end;

end.
