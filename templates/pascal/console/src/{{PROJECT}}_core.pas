{ The logic, so the program file only wires things together and the
  tests have something to call. }
unit {{PROJECT}}_core;

{$MODE OBJFPC}{$H+}

interface

{ Returns a greeting for AName, or for the world when it is empty. }
function Greet(const AName: string): string;

implementation

uses
  SysUtils;

function Greet(const AName: string): string;
begin
  if Trim(AName) = '' then
    Result := 'Hello, world'
  else
    Result := 'Hello, ' + Trim(AName);
end;

end.
