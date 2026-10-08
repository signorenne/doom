{ The tests: SPC k t builds and runs them, or by hand
    fpc -Mobjfpc -Sh -FEbin -FUlib -Fusrc -Futests tests/tests.lpr
    bin/tests --all --format=plain
  Any test that fails makes the exit code non-zero. }
program tests;

{$MODE OBJFPC}{$H+}

uses
  consoletestrunner,
  OptionTests,
  GreeterTests;

var
  Runner: TTestRunner;
begin
  DefaultRunAllTests := True;
  DefaultFormat := fPlain;
  Runner := TTestRunner.Create(nil);
  try
    Runner.Initialize;
    Runner.Title := '{{PROJECT}} tests';
    Runner.Run;
  finally
    Runner.Free;
  end;
end.
