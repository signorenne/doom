program {{PROJECT}};

{$MODE OBJFPC}{$H+}

uses
  SysUtils,
  {{PROJECT}}_core;

var
  Greeting: string;
begin
  try
    Greeting := Greet(ParamStr(1));
    WriteLn(Greeting);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, '{{PROJECT}}: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
