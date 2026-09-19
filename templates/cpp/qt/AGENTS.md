# {{PROJECT}} agent guide

The rules to keep in memory before changing this repo. `.clang-format` and
`.clang-tidy` enforce most of them; when this file and the tooling disagree,
the tooling wins and both get fixed.

## Shape

A Qt Quick application in MVVM. Three layers, one direction of knowledge:

- `src/model/` owns the data and the rules. Plain C++ and Qt containers, no
  QObject, no signals, nothing about the view. Testable on its own.
- `src/viewmodel/` adapts the model for the screen: `Q_PROPERTY` for
  everything the view shows, slots for everything the view does, signals when
  state changes. It knows the model, never the view.
- `qml/` binds. Layout and bindings only; no business rule, no C++ object
  built in QML.

`src/main.cpp` is the composition root: it builds the repository and the view
model and passes the view model to the engine as an initial property.

## Hard rules

- C++23 with Qt 6.5 or newer, `CXX_EXTENSIONS OFF`.
- Qt naming: `PascalCase` types, `camelCase` functions and properties, `m_`
  on members, `lower_case` namespaces.
- Qt pointer placement: `QObject *parent`, `const QString &text`.
- `#pragma once` and a Doxygen `@file` block at the top of every header.
- Every class and member function carries a `/** ... */` block: `@brief`,
  `@param`, `@return`. No HTML, no backticks.
- View models register themselves with `QML_ELEMENT`, so no
  `qmlRegisterType` calls anywhere.
- A view model never includes a QML or widget header, and QML never calls
  into the model.
- Every property the view reads has a `NOTIFY` signal, even a computed one.
- No em dash or en dash anywhere: code, comments, docs or commit messages.
- Commit subjects are `type(scope): description`, one sentence, no body.

## Adding a screen

1. Model: extend or add a repository under `src/model/`.
2. View model: a `QObject` under `src/viewmodel/` with `QML_ELEMENT`, the
   properties the screen shows and the slots it calls.
3. View: a `.qml` file under `qml/`, added to `QML_FILES` in `CMakeLists.txt`.
4. Test: a case in `tests/`, driving the view model with no window.

## Validation

```sh
cmake --preset dev && cmake --build --preset dev && ctest --preset dev
cmake --preset ci  && cmake --build --preset ci  && ctest --preset ci
clang-format -i $(git ls-files '*.hpp' '*.cpp')
run-clang-tidy -p build/dev -quiet '^(?!.*/build/).*/(src|include|modules|tests|examples)/'
```

The tests run headless through `QT_QPA_PLATFORM=offscreen`.
