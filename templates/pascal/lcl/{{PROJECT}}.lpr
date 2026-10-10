program {{PROJECT}};

{$MODE OBJFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms,
  MainForm;

begin
  // No resource directive above: Lazarus writes the .res file it names
  // only once the project has an icon or version information, and with
  // the directive a project that has neither does not build. Give it
  // either in the IDE and Lazarus puts the directive back itself.
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainWindow, MainWindow);
  Application.Run;
end.
