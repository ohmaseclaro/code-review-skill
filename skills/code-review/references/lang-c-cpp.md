# C and C++ pitfalls

Use when: C or C++ is the dominant language of the changed logic.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Two rules of priority differ here: a memory-safety defect reachable from untrusted input is a `[security]` finding, and undefined behavior that "works today" is still a `[bug]`, because the next compiler or optimization level may change it.

## Bounds and sizes

- Copies and formats with no bound: `strcpy`, `strcat`, `sprintf`, `gets`, `scanf("%s")`. `strncpy` does not always terminate. `snprintf` truncation goes unnoticed unless the return value is checked.
- Lengths read from a file or the network and used before validation against the remaining buffer.
- `n * sizeof(T)` overflowing before an allocation, which then is too small.
- Unsigned wraparound: `len - 1` when `len` is 0, and `for (size_t i = n - 1; i >= 0; i--)`.
- Signed overflow is undefined, so a check written as `a + b < a` can be removed by the compiler.
- Narrowing and sign changes: `size_t` to `int`, comparisons between signed and unsigned.
- Small unsigned types promote to `int`: `uint16_t * uint16_t` can overflow as a signed multiplication.
- `sizeof` on a pointer or a decayed array. Wrong format specifiers for `size_t` and fixed-width integers.
- A negative `char` passed to `<ctype.h>` functions.
- User input as a format string.

## Lifetime and ownership

- Use after free and dangling references: a pointer or reference to a local, an iterator or reference after `push_back`, `erase` or rehash, a `string_view` or span over a temporary, `c_str()` after the string changes.
- A lambda that captures by reference and outlives its scope: callbacks, threads, async work.
- Leaks on early-return and exception paths. `p = realloc(p, n)` loses the block on failure.
- Double free. `new[]` paired with `delete`. `malloc` results not checked.
- Uninitialized variables and members. Struct padding copied out to a file, a socket or another privilege domain.
- A class that owns a raw resource and keeps the default copy operations.
- A polymorphic base class with no virtual destructor. Slicing by passing a derived object by value.
- `shared_ptr` cycles. Two control blocks created from one raw pointer.
- `auto x = f()` copying where a reference was intended, and `auto` bound to a proxy object.

## Undefined and surprising behavior

- Type punning through pointer casts instead of `memcpy` or `bit_cast`. Unaligned access.
- A dereference before the null check lets the compiler delete the check.
- Shifts by a negative amount or by the type's width or more.
- A sort comparator that is not a strict weak ordering (`<=`), or `a - b` as a comparator result.
- `operator[]` on a map inserts a default element.
- Erasing from a container inside a loop without using the returned iterator.
- `std::vector<int>{10, 0}` versus `(10, 0)`: two elements versus ten.
- Use after `std::move`. A `const` object "moved" is copied.
- An exception leaving a destructor or a `noexcept` function terminates the program.
- Inline functions, templates or struct layouts that differ between translation units.
- `assert` with side effects, or used for input validation: it vanishes with `NDEBUG`.

## Concurrency

- A data race is undefined behavior, not only a stale value. That includes plain `bool` flags and one `shared_ptr` instance used from two threads.
- Lock ordering, a lock not held in every accessor, manual unlock on some paths instead of a guard.
- Condition variable waits with no predicate, or state changed without holding the mutex.
- A joinable `std::thread` destroyed. Detached threads using objects that are gone.
- Check-then-act on atomics. `volatile` used as if it were atomic.
- Signal handlers calling functions that are not async-signal-safe.
- Non-reentrant library functions (`strtok`, `localtime`, `rand`, `getenv` with `setenv`).

## System interfaces

- Unchecked results: short `read` and `write`, `EINTR`, `close` and `fclose` after writing, `setuid` and other privilege drops.
- File descriptors leaked on error paths, or inherited by child processes.
- Check-then-open races on paths. Predictable temporary file names.
- `system` and `popen` with constructed strings.
- Permissions of created files.
- Layout assumptions in wire and disk formats: endianness, packing, `long` width, `char` signedness, `time_t` size.
- Locale-dependent number parsing and formatting in protocols and config files.
- Unbounded recursion on untrusted input.

## Build and ABI

- A header change that alters struct layout, virtual tables, inline functions, default arguments or enum values breaks prebuilt consumers of a shared library.
- Hardening or warning flags removed. New warning suppressions.
- Platform branches behind `#ifdef` that CI never builds.
- Exceptions crossing a C boundary.
- Build files that fetch dependencies from a moving branch.

## Verify by

- Building with the repository's warning flags.
- Running the touched tests under address and undefined-behavior sanitizers, and the thread sanitizer for concurrency changes, when the build supports them.
- The configured static analyzer.
- A short run of the fuzz target when a parser changed and one exists.

## Do not flag

- Formatting. Modernization of untouched code. Micro-optimizations with no profile. "Use smart pointers" where the codebase follows another documented ownership convention.
