# Tests

Use when: tests, fixtures, mocks or snapshots changed, tests were removed or skipped, the change is a bug fix, or new logic arrived without tests.

## The questions

- Would these tests fail if the change were reverted, or subtly broken?
- What behavior could regress without any test noticing?
- Did a failure disappear because the behavior improved, or because the verification got weaker?

## Tests that prove the change

- A bug fix has a regression test that fails before the fix and passes after it.
- Each new branch, boundary and error path is exercised, including negative cases.
- Inverse check: revert only the production hunk. Which new tests still pass? Those are decoration.
- Mutation thinking: flip an operator or delete a guard in the changed code. Does any test fail?

## Weakened verification

Read test changes as carefully as production changes.

- Tests deleted, skipped, focused (`only`), marked expected-to-fail or excluded by a new condition.
- Assertions relaxed: exact match to "contains", equality to "defined", a narrowed list of checked fields.
- Tolerances and timeouts widened. Retries added around a flaky test.
- Expected values edited to match new output. Snapshots regenerated: read the snapshot diff and ask whether it encodes the regression.
- An existing test changed to accommodate new behavior. That may be an intended requirement change, or the test catching a real regression.

## Assertions with signal

- Tautologies: a value compared to itself, a count asserted to be zero or more, a mock asserted to return what it was told to return.
- No assertion at all, or an exception caught and ignored inside the test.
- Only "was called with" on a mock, with no check of the resulting state or output.
- Assertions on private calls or incidental ordering, which break on refactors and pass on bugs.
- A snapshot so large that nobody will read its diff.

## Mock and fake fidelity

- A mock that returns a shape or value the real dependency can never produce.
- Stubs that skip the very thing at risk: authorization, query filters, transactions, serialization, failure behavior.
- Untyped or unspecified mocks that accept any call.
- The unit under test itself mocked.
- Do not infer integration correctness from a permissive stub. Ask for a contract or integration test only when a concrete risk cannot be checked at a simpler level.

## Fixtures that reach the path

- Test data that never triggers the new branch.
- A null or empty input in the fixture where the bug needs a real value.
- Factory defaults that hide a required field. Fixtures shared and mutated across tests.

## Determinism

Real clocks, sleeps, unseeded randomness, reliance on map or database ordering, network calls, shared state between tests, fixed ports, time zone and locale dependence, tests that only pass in a certain order.

## Level, placement and whether it runs

- The test sits at the level the repository uses for this kind of logic.
- **Does it run in CI?** A suite that the pipeline skips or filters out cannot gate a merge. Check the CI config, tags and file-name patterns.
- A slow test added to the fast suite, or logic that deserves a unit test covered only end to end.

## Production code bent for tests

Test-only branches, environment checks, localhost overrides, weakened validation in test mode, fake data paths reachable in production.

## Coverage theater

Tests for trivial accessors, framework or standard-library behavior, and tests that mirror the implementation line by line. Do not ask for these either.

## Asking for a test

Name the behavior to protect, the failure the test would catch and the level it belongs at, and say why existing tests do not cover it. Never write "please add tests".

## Verify by

- Running the changed tests.
- The revert-the-hunk check in a scratch checkout.
- Reading the CI config to see which suites run.
- A mutation tool on the changed lines when the project has one configured.

## Do not flag

- Missing tests for trivial or generated code. A coverage number by itself, unless a repository rule sets one.
- Test style and naming, beyond a rare nit.

## Priority guidance

P0: tests weakened in a way that hides a regression, new logic that handles money, security or data integrity with no test, tests that cannot fail presented as the protection for a critical path, a required test that does not run in CI. P1: important behavior left untested, or a nondeterministic pattern in a new test: name the case. P2: missing coverage for ordinary edge cases.
