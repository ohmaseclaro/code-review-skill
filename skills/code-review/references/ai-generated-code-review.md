# Reviewing AI-generated changes

Use when: the author is a coding agent or bot, the description says the change is AI-assisted, or the change shows the signals below.

Stance: same bar, different failure distribution. Do not block a change because it was generated, and do not wave it through because it looks tidy. Every material behavior must be explainable from the code. If essential behavior stays unexplained after inspection, raise a `[P0][question]`.

## Signals (they redirect attention, they are not findings)

- A polished description that is generic or does not match the diff.
- Files touched that have nothing to do with the stated purpose.
- Comments that narrate the code or the change history.
- A new helper next to an existing one that does the same thing.
- Tests whose structure mirrors the implementation line by line.
- A style that differs from the neighboring files.
- Claims of verification with no evidence ("tested locally", "all checks pass").

Never write "this looks AI-generated" as a finding. Name the concrete defect.

## Failure patterns and how to check each

| Pattern | Check |
| --- | --- |
| **Invented APIs.** Methods, options, config keys, CLI flags, environment variables or enum values that do not exist | Resolve every new external symbol against the pinned version: lockfile, then the package's types, source or docs. Confirm each new config key or env var is read somewhere. |
| **Invented or look-alike packages** | For each new dependency: does it exist in the registry, who publishes it, how old is it, does the name match the import? See `dependencies-supply-chain.md`. |
| **Plausible but wrong logic** | Trace concrete boundary values through the code. Inverted conditions, off-by-one and unit mix-ups survive a casual read. |
| **Tests weakened to pass** | Deleted or skipped tests, loosened assertions, widened tolerances, regenerated snapshots, expected values copied from actual output, exceptions swallowed inside tests. See `tests.md`. |
| **Tests that cannot fail** | Assertions on mock calls only, tautologies, tests that re-implement the function under test. Ask: which test fails if the production hunk is reverted? |
| **Production code bent for tests** | Branches on a test environment flag, localhost overrides, stubs and fake data returned outside tests. |
| **Errors made to disappear** | Broad catch returning a default, `?? []`, optional chaining over data that must exist, retry-until-green, `|| true`, new `any` casts and lint or type suppressions. |
| **Over-engineering** | A new layer, option, flag, cache, lock or generic framework for a requirement that needs ten lines. Ask for the smallest change that meets the requirement. |
| **Under-integration** | Existing helpers ignored, local conventions ignored, a new pattern beside the old one, callers or docs not updated, old and new paths both alive. |
| **Collateral edits** | Reformatting, renames, unrelated fixes, dependency bumps, removed comments or license headers, and above all edits to CI, lint config or rule files that make a failing check pass. |
| **Stubs presented as done** | `TODO`, `pass`, `NotImplemented`, hard-coded returns, placeholder data, commented-out code. |
| **Convenience security regressions** | TLS verification off, wildcard CORS, widened IAM, an auth check removed to fix a test, an inlined secret, a debug endpoint, string-built SQL or shell. |
| **Unsupported claims** | "No behavior change", "backward compatible", benchmark numbers. Check each claim against the diff, or ask for the evidence. |
| **Internal inconsistency** | Two files in the same change that disagree on a default, a type or a name. Half-finished renames. |
| **Environment assumptions** | Hard-coded local paths, ports, tool versions or OS-specific commands. |
| **Happy-path concurrency and data handling** | Check-then-act, missing transactions, auto-generated migrations with no thought for locks, backfills or rollback. |

## Process adjustments

- **Run it.** Generated changes are often never executed. Run the tests and the changed path in an isolated checkout. If the author says the tests cannot be run, that is a material validation gap, and the verdict is Hold.
- **Demand a reproduction for bug fixes.** A test that fails before and passes after, or a recorded repro.
- **Mind the size.** Agent changes tend to be large. Apply `large-pr-strategy.md` and ask for a split early.
- **Stay independent.** Do not review with the session or context that wrote the code. A fresh context, and where possible a different model for verification, avoids shared blind spots.
- **Check for an owner.** Someone accountable should be able to explain the change. If nobody can, ask who owns it.

## Writing findings for an agent author

- Be self-contained: file, lines, required outcome, how to verify. See the fix-request block in `comment-style-and-labels.md`.
- State the outcome you need, not only the symptom. Agents comply literally.
- Watch the next round for over-correction: the "fix" that deletes the failing test, adds a special case for the reviewer's example, or wraps the problem in a catch.
- Bound the review and fix loop. After three rounds, escalate to a human.

## Do not

- Lower the bar for boilerplate or raise it for style.
- Ask for a hand rewrite as a matter of principle.
- Trust a confident description over the diff.
