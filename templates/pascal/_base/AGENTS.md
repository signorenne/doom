# {{PROJECT}} agent guide

The rules to keep in memory before changing this repo.

## Hard rules

- Object Pascal in `{$MODE OBJFPC}` with `{$H+}`: long strings, and the
  dialect Free Pascal and Delphi agree on. No Turbo Pascal shortcuts.
- Every unit carries an `interface` and an `implementation` section, and
  nothing in `interface` that the outside does not need.
- Types are `TName`, classes `TName`, exceptions `EName`, private fields
  `FName`, arguments `ANamed`. That is the house convention and the
  Lazarus one.
- Every `try` that acquires something has a `finally` that frees it.
- `raise` an exception rather than returning an error code; catch only
  what this unit can answer for.
- Free what you create: an owner (a form, a list with `OwnsObjects`) or
  a `try ... finally Free`.

## Shape

- The program file (`.lpr`) wires things together and does nothing else.
- The logic lives in units under `src/`, one concept each.

## Before you finish

- It compiles with no warnings: `fpc -Mobjfpc -Sh -vw` is clean.
- It is formatted: `jcf -clarify -inplace -y -config=jcfsettings.cfg -F`
  on the file leaves it as it is. That is JEDI Code Format, the Lazarus
  IDE's formatter, with this repo's settings.
- No unit in `uses` that is not used.
