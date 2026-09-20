# {{PROJECT}} agent guide

The rules to keep in memory before changing this repo. `rustfmt.toml` and
the lints in `Cargo.toml` enforce most of them; when this file and the
tooling disagree, the tooling wins and both get fixed.

## Hard rules

- Rust 2021, stable toolchain. No nightly-only features.
- `cargo clippy --all-targets` is clean before a commit, warnings and all.
- `unsafe` needs a `// SAFETY:` comment saying what upholds the invariant.
- No `unwrap` or `expect` outside tests and `main`; return a `Result` and
  let the caller decide. `?` over matching when the error converts.
- Errors are types, not strings: `thiserror` for a library, `anyhow` only
  at the edges of a binary.
- Public items carry a doc comment; the crate root carries `//!`.
- A test lives beside what it tests in `mod tests`, integration tests in
  `tests/`.

## Shape

- `src/lib.rs` holds the logic and the tests; a binary is a thin wrapper
  in `src/main.rs` that parses arguments and calls into the library.
- One module per concept, `mod.rs` only where a module has files of its
  own.

## Before you finish

- `cargo fmt`, `cargo clippy --all-targets`, `cargo test`.
- No `dbg!`, no commented-out code, no `TODO` without a name beside it.
