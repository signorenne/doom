{ The main window. The form's widgets live in mainform.lfm beside this
  file; Lazarus edits that visually, and it is plain text either way. }
unit MainForm;

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls;

type

  { TMainWindow }

  TMainWindow = class(TForm)
    GreetButton: TButton;
    GreetingLabel: TLabel;
    procedure GreetButtonClick(Sender: TObject);
  private
    FCount: Integer;
  end;

var
  MainWindow: TMainWindow;

implementation

{$R *.lfm}

{ TMainWindow }

procedure TMainWindow.GreetButtonClick(Sender: TObject);
begin
  Inc(FCount);
  GreetingLabel.Caption := Format('Pressed %d time(s)', [FCount]);
end;

end.
