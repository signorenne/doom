unit GreeterTests;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils,
  fpcunit,
  testregistry,
  Options,
  Greeter;

type
  TGreeterTest = class(TTestCase)
  published
    procedure OneLineForEachOfTheCount;
    procedure ABlankNameGreetsTheWorld;
  end;

implementation

procedure TGreeterTest.OneLineForEachOfTheCount;
var
  Lines: TStringArray;
begin
  Lines := Greetings(ParseOptions(['--name', 'ada', '--count', '2']));
  AssertEquals(2, Length(Lines));
  AssertEquals('Hello, ada', Lines[0]);
  AssertEquals('Hello, ada', Lines[1]);
end;

procedure TGreeterTest.ABlankNameGreetsTheWorld;
begin
  AssertEquals('Hello, world', Greetings(ParseOptions(['--name', '  ']))[0]);
end;

initialization
  RegisterTest(TGreeterTest);
end.
