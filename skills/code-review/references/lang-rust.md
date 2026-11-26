# Rust pitfalls

Use when: Rust is the dominant language of the changed logic.

These are patterns to check, not findings. The compiler already rules out a great deal: spend the time on what it cannot see. Each item needs a trigger and a consequence in this change.

## Panics on production paths

- `unwrap()`, `expect()`, slice indexing, string slicing off a character boundary, division by zero, a second `RefCell` borrow.
- Arithmetic overflow panics in debug builds and wraps in release builds. `usize` subtraction is the usual case. Use checked, saturating or wrapping operations on purpose.
- `as` casts truncate and change sign silently. Use `try_from`.
- A panic crossing an FFI boundary, a panic inside `Drop`, a panic while holding a lock (poisoning).
- A panic in a spawned task ends only that task. If nobody awaits the handle, nobody finds out.

## Errors

- `let _ = result;` and `.ok()` discarding a failure, especially on `send`, `write` and `flush`.
- `?` passing an error upward with no context about what was being attempted.
- `unwrap_or_default()` turning a failure into a plausible value.
- `BufWriter` and files dropped without an explicit `flush` or `sync_all`: errors at drop are ignored and data can be lost.

## Unsafe

- Every `unsafe` block states the invariant it relies on. If no comment says why it is sound, ask.
- Aliasing a `&mut`. Lifetimes extended through raw pointers. `transmute`. Uninitialized memory. Length and alignment passed to `from_raw_parts`.
- Hand-written `Send` or `Sync` implementations.
- FFI: who owns and frees each pointer, a `CString` temporary dropped while its pointer is in use, layout attributes, nul termination.
- A safe public function that is unsound for some inputs because of the `unsafe` inside it.

## Async

- Blocking in async code: a standard-library mutex held across `.await`, `std::thread::sleep`, synchronous I/O, heavy CPU work.
- Any guard held across an `.await`.
- **Cancellation safety.** A future can be dropped at any `.await`, for example in a `select!` branch or under a timeout. Work in progress and partially filled buffers are lost.
- Detached tasks whose handles and errors are dropped. Unbounded channels and one spawn per item, with no backpressure.
- `block_on` inside an async context. Cleanup that needs `.await` cannot run in `Drop`.

## Locks and lifetimes of guards

- `let _ = mutex.lock();` releases immediately. `let _guard = ...` holds.
- A temporary guard inside a `match` or `if let` scrutinee lives until the end of the whole expression.
- Lock ordering. Re-entrant read locks. `Ordering::Relaxed` used where synchronization is required.
- `Rc` cycles leak. Use `Weak` for back references.

## API and compatibility for libraries

- Breaking changes that compile locally: a new field on a public struct without `#[non_exhaustive]`, a new enum variant, a new required trait method, a returned future that stops being `Send`.
- Types from a dependency in your public API: its major bump becomes yours.
- Features that are not additive. A raised minimum supported Rust version.
- `#[derive(Debug)]` on a struct holding secrets prints them in logs.
- Serde attribute and rename changes are wire-format changes: see `api-contracts.md`.

## Build

- `build.rs` and procedural macros execute at build time: review them as executable code.
- Git dependencies not pinned to a revision. `Cargo.lock` missing for a binary.
- `#[cfg]` branches that CI never compiles. Invariants enforced only by `debug_assert!`.

## Verify by

- `cargo check` and `cargo clippy --all-targets` with the repository's configuration.
- `cargo test -p <crate>`. Miri for unsafe code when available.
- A semver checker for published crates. `cargo audit` or `cargo deny` when dependencies changed.

## Do not flag

- Formatting. Lints the repository does not enable. `clone` on cheap handles. Iterator chain versus loop taste.
