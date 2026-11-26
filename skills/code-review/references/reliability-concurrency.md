# Reliability and concurrency

Use when: the change touches threads, locks, async code, queues, workers, schedulers, retries, transactions, calls to other systems, or error handling and fallbacks.

## The questions

- What happens if this runs twice? Half-runs? Runs concurrently with itself?
- What happens when the dependency is slow, down or returns garbage?
- What if messages arrive late, duplicated or out of order?
- If the process dies between these two lines, what state is left?
- If this fails, who finds out?

## Calls to other systems

- **Timeouts.** Is one set, for connect and for read? Many client libraries default to none. Is cancellation propagated (context, abort signal, deadline)?
- **Retries.** Bounded, with backoff and jitter, only on retryable errors, and only for idempotent operations or with an idempotency key. Retries nested at several layers multiply.
- **Responses.** Status checked, body validated, partial and oversized responses handled.
- **Pools.** Connections returned on every path. Pool exhaustion under slow dependencies.

## Delivery semantics and idempotency

- Webhook, queue and cron handlers that assume exactly-once. At-least-once is the norm: look for a dedupe key, an upsert or a conditional write.
- Out-of-order delivery: can an older event overwrite newer state? Look for a version or timestamp check.
- Redelivery after a visibility timeout while the first attempt is still running.
- Acknowledging before processing (loss) versus after (duplicates). Which does the code do, and is that intended?
- Poison messages: a maximum receive count and a dead-letter path.
- Batch handlers: one bad item failing or silently dropping the batch.
- Dual writes: a database commit and a publish are not atomic. Look for an outbox or an after-commit hook.

## Transactions and consistency

- Boundaries too wide (a network call inside a transaction holding locks) or too narrow (an invariant split across two commits).
- Read-modify-write without a lock, a version check or an atomic statement: lost updates.
- Check-then-act on uniqueness, quota or balance: enforce with a constraint or an atomic operation.
- Inconsistent lock or update order across code paths: deadlocks.
- A callee committing or rolling back a transaction its caller owns.
- Side effects (emails, events, external calls) before commit, or jobs enqueued before the data they need is visible.
- Rollback that leaves caches, files or external systems updated.

## Concurrency primitives

- Shared mutable state reachable from concurrent requests: module-level variables, singletons, class attributes, memoization maps.
- A lock held across I/O or an await. A lock not released on the error path. Double-checked locking.
- Compound operations on concurrent collections that are not atomic as a whole.
- Unbounded parallelism: one task per item with no pool or semaphore.
- Fire-and-forget tasks with no error handling. A missing await. A dropped task or join handle.
- Blocking calls inside an event loop or async runtime.
- Leaks: a goroutine, thread or task with no exit path, blocked forever on a channel or queue. Timers and listeners never cleared.
- Distributed locks: expiry while the holder is still working, release by a non-owner, reliance on synchronized clocks.

## Silent failure audit

For every new or changed `catch`, `except`, `rescue`, `recover`, error callback, fallback or default-on-error, ask:

1. Which unexpected errors would this also swallow? List them.
2. Is the failure logged with enough context to debug it later?
3. Does the caller or user learn that it failed?
4. Is the fallback an explicit requirement, or is it hiding the problem?

Patterns to flag:

- Empty catch. Catch-all that logs and continues where the operation must fail.
- Returning `null`, an empty list or a default on error, so callers cannot tell "nothing" from "failed".
- A fallback to a stub, mock or cached value that nobody is told about.
- Retries exhausted, then success reported anyway.
- Swallowing cancellation or interrupts. A `finally` block that overrides the exception.
- Ignored exit codes in scripts. Exceptions lost in background tasks.
- A default substituted for a required configuration value. Validation and security paths must fail closed and loudly.

## Scheduled and background work

- Overlapping runs when the previous one has not finished. Catch-up storms after downtime.
- Cron expressions and time zones, including daylight saving.
- Re-running a job: is it idempotent? Do retries repeat non-idempotent effects such as emails or charges?
- Long jobs without checkpoints. Payload shape changes for jobs already queued: see `data-migrations-compat.md`.

## Resources and limits

- Files, sockets, cursors, locks, temporary files and subscriptions closed on every path.
- Unbounded growth: in-memory queues, caches without eviction or TTL, maps keyed by user input.
- No backpressure between a fast producer and a slow consumer.
- Shutdown: in-flight work drained, new work refused, signals handled.

## Caches and fan-out

- Every write path invalidates or updates the cache. Keys include tenant, locale, version and anything else that changes the answer.
- Stampedes when a hot key expires. Stale values served during errors: intended or not?
- All-or-nothing fan-out that rejects on the first failure while other calls keep running, or settle-all that ignores failures.

## Verify by

- Writing two interleavings side by side and stepping through them.
- Finding where the idempotency key is stored and which constraint enforces it.
- Checking the client library's default timeout and retry behavior for the pinned version.
- Running the race detector or sanitizer when the project has one.

## Do not flag

- A theoretical race with no shared state or no concurrent caller.
- Missing retries on non-idempotent or interactive paths. A missing circuit breaker in a codebase that has none.
- "Add a timeout" without having checked the client's default.

## Priority guidance

P0: lost or duplicated money or data under a realistic retry or interleaving, a failure reported as success, a deadlock or leak on a hot path, unbounded growth reachable by normal traffic. P1: a failure that is bounded and visible today but will recur, such as a missing timeout on a non-critical call. P2: resilience improvements with no failure demonstrated.
