# Correctness and logic

Use when: the change contains non-trivial logic in any language.

## The questions

- For each changed function: what is the full range of each input, and is every branch right for every part of that range?
- What did the old code guarantee that the new code no longer does?
- Does the diff implement each stated requirement, and is each one exercised by a path you can point at?

## Method

Pick the two or three functions that carry the behavior. For each, write a small private table of inputs, expected results and what the code actually does, including at least: absent, empty, one, many, boundary, duplicate, malformed, and upstream failure. A data flow has one happy path and several shadow paths. Review the shadow paths.

## Red flags

**Intent and equivalence**
- An acceptance criterion with no code path behind it, or a behavior in the diff the description never mentions.
- "Refactor, no behavior change" that changes evaluation order, side-effect order, short-circuiting, laziness, defaults or which errors escape.

**Boundaries and conditions**
- Off-by-one, inclusive versus exclusive ends, `<` versus `<=`, the last page, the empty range, the first and last element.
- Inverted or partially negated compound conditions, operator precedence, a missing `else`, switch fallthrough, no default branch.
- A new enum value or state: search every switch, match and lookup table that must now handle it.
- Integer division, modulo of negatives, overflow and truncation (32-bit ids, milliseconds versus seconds), float equality, rounding mode.

**Absent and default values**
- A default that masks missing data: `|| 0` where zero is valid, `?? ""`, a fallback object.
- Optional chaining or null-safe calls that turn a real error into a silent no-op.
- Truthiness tests on values where `0`, `""` or an empty collection are legitimate.
- Sentinel values (`-1`, `"N/A"`, epoch zero) whose meaning changed or is no longer checked.

**State and ordering**
- State machines: a transition that should be impossible, a missing terminal state, a status set before the work that justifies it.
- Order of operations: write before validate, publish before commit, cache update before the source of truth.
- Fields that must change together updated in separate steps.
- Mutating a shared default, a parameter the caller still uses, or a collection during iteration. Shallow copies treated as deep.

**Time, units, money, text**
- Time zones and daylight saving, naive versus aware datetimes, month ends and leap days, wall clock used to measure elapsed time.
- Unit mismatches at an interface: milliseconds and seconds, bytes and kilobytes, cents and currency units.
- Floating point for money. Rounding applied per line item versus on the total.
- Locale-dependent casing, sorting and number parsing. String length in bytes versus characters. Case-sensitive comparison of identifiers that are not.

**Collections and algorithms**
- Sort comparators that are inconsistent, a default sort that compares as strings, reliance on unspecified iteration order.
- Dedup or lookup keyed on the wrong field or on object identity.
- `find` when all matches are needed. Slices with the wrong end. An accumulator with the wrong initial value.
- Cursors or offsets that skip or repeat rows when data changes between pages.

**Error paths**
- A new failure mode: who catches it, what does the user see, what state is left behind?
- Loops and batches: does the first failure abort, skip or poison the rest? Is partial success reported?
- Cleanup skipped by an early return or exception. An error mapped to the wrong type or status.

**Callers**
- Changed signature, default, return shape, nullability or thrown error: search all callers, including dynamic ones (reflection, dependency injection, string names, serializers, templates).
- A parameter or flag whose meaning changed while its type did not.
- A removed export still imported by another package.

**Configuration and flags**
- Behavior when the setting is unset. Environment strings parsed as booleans (`"false"` is truthy in many languages).
- Each flag state, and a flag flipping while work is in flight.

**Copy, paste and naming traps**
- The same variable used twice where two were meant, the wrong sibling (`width` for `height`), a stale variable after a rename, shadowing, a loop variable captured by a closure.

**Parsing and matching**
- Regex: missing anchors, greedy matches, unescaped dots, partial match where a full match was intended, patterns that can backtrack catastrophically.
- Serialization: 64-bit integers through JSON, date formats, unknown enum values, renamed fields.

**Deletions**
- A removed branch, validation, default or early return: is the case it handled still handled somewhere?

## Verify by

- Tracing concrete values through the code, and writing down the path with file and line.
- Running the existing tests for the touched module, or a five-line scratch repro.
- Grepping every caller and every switch over a changed enum.
- For regexes, parsers and pricing or date logic: a before and after table of inputs and outputs.

## Do not flag

- Defensive checks for states the type system or the only caller makes impossible. Verify that first.
- Inputs no caller can produce.
- Alternative implementations that are merely different.

## Priority guidance

P0: a wrong result or side effect on a realistic input, a missed acceptance criterion, a broken caller, corrupted or lost data. P1: an edge case with a bounded, visible, low-cost failure. P2: a clearer structure with no behavior at stake.
