{ What the program does with its options. }
unit Greeter;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils,
  Options;

{ The greeting AOptions ask for, one line for each of its Count; a name
  that is only blanks greets the world. }
function Greetings(const AOptions: TOptions): TStringArray;

implementation

function Greetings(const AOptions: TOptions): TStringArray;
var
  Name: string;
  Index: Integer;
begin
  Name := Trim(AOptions.Name);
  if Name = '' then
    Name := 'world';
  Result := nil;
  SetLength(Result, AOptions.Count);
  for Index := 0 to AOptions.Count - 1 do
    Result[Index] := 'Hello, ' + Name;
end;

end.
