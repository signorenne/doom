# {{PROJECT}} agent guide

The rules to keep in memory before changing this repo. `.clang-format` and
`.clang-tidy` enforce most of them; when this file and the tooling disagree,
the tooling wins and both get fixed.

## Shape

C++23 application. The logic lives in headers under `include/{{PROJECT}}/`
that the tests link, `src/main.cpp` only wires it; tests in `tests/` with
doctest.

## Hard rules

- C++23, `CXX_EXTENSIONS OFF`, standard library before custom code.
- snake_case for every name; PascalCase only for template parameters;
  `m_` on private and protected members.
- Trailing return types, braced initialization, east const, `const` by
  default. No `T x(...)`, no `auto x = expr`.
- Every header opens with `#pragma once` and a Doxygen `@file` block.
- Every symbol, public or internal, carries a `/** ... */` block: `@brief`,
  `@tparam`, `@param`, `@return`, `@pre`, `@post`, in that order. No HTML,
  no backticks; use `\c` for inline code.
- Recoverable errors return `std::expected<T, error>`. Throwing is for the
  cases that cannot report otherwise, such as a constructor.
- Every value type exposes `using value_type = ...` first.
- No em dash or en dash anywhere: code, comments, docs or commit messages.
- No license or author banners in files; they live in LICENSE and git.
- Commit subjects are `type(scope): description`, one sentence, no body.

## Validation

Run the narrow command while iterating, then widen before finishing.

```sh
cmake --preset dev && cmake --build --preset dev && ctest --preset dev
cmake --preset ci  && cmake --build --preset ci  && ctest --preset ci
cmake --preset asan && cmake --build --preset asan && ctest --preset asan
clang-format -i $(git ls-files '*.hpp' '*.cpp')
run-clang-tidy -p build/dev -quiet '^(?!.*/build/).*/(src|include|modules|tests|examples)/'
```

One suite while iterating:

```sh
./build/dev/bin/{{PROJECT}}_tests --test-case="*options*"
```
