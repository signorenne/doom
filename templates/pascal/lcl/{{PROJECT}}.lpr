program {{PROJECT}};

{$MODE OBJFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms,
  MainForm;

{ No {$R *.res} here: Lazarus writes that resource file only once the
  project has an icon or version information, and a project that has
  neither would not build without it. Give it either in the IDE and
  Lazarus puts the directive back itself. }

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainWindow, MainWindow);
  Application.Run;
end.
