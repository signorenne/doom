unit OptionTests;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  Options;

type
  TOptionsTest = class(TTestCase)
  private
    { The kind of error AArguments raise; fails when they raise none. }
    function ErrorOf(const AArguments: array of string): TOptionErrorKind;
  published
    procedure AnEmptyCommandLineGivesTheDefaults;
    procedure NameTakesTheNextArgument;
    procedure NameTakesAJoinedValue;
    procedure ShortOptionsWork;
    procedure CountTakesAWholeNumber;
    procedure VerboseIsAFlag;
    procedure HelpAndVersionAreFlags;
    procedure AnOptionWithoutItsValueIsAnError;
    procedure AnUnknownOptionIsAnError;
    procedure AFlagGivenAValueIsAnError;
    procedure ACountThatIsNotAPositiveNumberIsAnError;
  end;

implementation

function TOptionsTest.ErrorOf(const AArguments: array of string): TOptionErrorKind;
begin
  Result := oeUnknownOption;
  try
    ParseOptions(AArguments);
    Fail('no error raised');
  except
    on E: EOptionError do
      Result := E.Kind;
  end;
end;

procedure TOptionsTest.AnEmptyCommandLineGivesTheDefaults;
var
  Parsed: TOptions;
begin
  Parsed := ParseOptions([]);
  AssertEquals('world', Parsed.Name);
  AssertEquals(1, Parsed.Count);
  AssertFalse(Parsed.Verbose);
  AssertFalse(Parsed.ShowHelp);
  AssertFalse(Parsed.ShowVersion);
end;

procedure TOptionsTest.NameTakesTheNextArgument;
begin
  AssertEquals('ada', ParseOptions(['--name', 'ada']).Name);
end;

procedure TOptionsTest.NameTakesAJoinedValue;
begin
  AssertEquals('ada', ParseOptions(['--name=ada']).Name);
end;

procedure TOptionsTest.ShortOptionsWork;
var
  Parsed: TOptions;
begin
  Parsed := ParseOptions(['-n', 'ada', '-c', '3', '-v']);
  AssertEquals('ada', Parsed.Name);
  AssertEquals(3, Parsed.Count);
  AssertTrue(Parsed.Verbose);
end;

procedure TOptionsTest.CountTakesAWholeNumber;
begin
  AssertEquals(4, ParseOptions(['--count', '4']).Count);
end;

procedure TOptionsTest.VerboseIsAFlag;
begin
  AssertTrue(ParseOptions(['--verbose']).Verbose);
end;

procedure TOptionsTest.HelpAndVersionAreFlags;
begin
  AssertTrue(ParseOptions(['-h']).ShowHelp);
  AssertTrue(ParseOptions(['--version']).ShowVersion);
end;

procedure TOptionsTest.AnOptionWithoutItsValueIsAnError;
begin
  AssertTrue(ErrorOf(['--name']) = oeMissingValue);
end;

procedure TOptionsTest.AnUnknownOptionIsAnError;
begin
  AssertTrue(ErrorOf(['--colour']) = oeUnknownOption);
end;

procedure TOptionsTest.AFlagGivenAValueIsAnError;
begin
  AssertTrue(ErrorOf(['--verbose=yes']) = oeUnexpectedValue);
end;

procedure TOptionsTest.ACountThatIsNotAPositiveNumberIsAnError;
begin
  AssertTrue(ErrorOf(['--count', 'three']) = oeBadNumber);
  AssertTrue(ErrorOf(['--count', '0']) = oeBadNumber);
end;

initialization
  RegisterTest(TOptionsTest);
end.
