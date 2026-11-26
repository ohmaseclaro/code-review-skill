# Data, migrations and stored-format compatibility

Use when: the change touches schemas, migrations, backfills, ORM models, or any persisted or serialized format: database rows and documents, cached values, queue and job payloads, files, sessions, tokens, checkpoints.

Core fact: code deploys in minutes and can be rolled back. Data cannot. During a rollout, old and new code run side by side against the same data.

## The questions

- Does every existing record already satisfy the new shape, or does something have to run first?
- Can old code read what new code writes, and the reverse, during the rollout and after a rollback?
- What does the database do to concurrent traffic while this statement runs?
- If this fails halfway, what state are we in, and how do we resume?

## Expand, migrate, contract

The safe order: add the new shape alongside the old, write both, backfill, switch readers, and only in a later release remove the old shape.

Red flags:

- A rename or drop in the same deploy as the code that stops using it.
- A type changed in place.
- `NOT NULL`, a stricter validation or a narrower enum on data that old rows or old writers do not satisfy.
- A unique constraint added where duplicates may exist.
- A fallback for the old shape removed with no evidence the migration already ran everywhere.
- Expand and contract in one change.

## Locks and online safety

Know the engine. Examples that recur:

- **Postgres.** `CREATE INDEX` without `CONCURRENTLY` blocks writes. Adding a column with a volatile default, or changing a column type, rewrites the table. Adding a foreign key or check constraint validates under a heavy lock unless added `NOT VALID` and validated separately. `SET NOT NULL` scans the table. Any statement needing an exclusive lock queues behind long transactions and blocks everyone behind it: look for a lock timeout with retries. `CONCURRENTLY` cannot run inside the transaction most migration frameworks open by default.
- **MySQL.** Check which DDL algorithm applies (instant, in place, copy) and metadata locks. Large tables often need an online schema change tool.
- **Document stores.** Index builds on large collections, validator changes on existing documents, unbounded array growth, single-field restrictions on TTL indexes.
- **Everywhere.** Long transactions, replica lag, statement timeouts.

If you do not know the table size, ask. Size decides whether a lock is a non-issue or an outage.

## Backfills

- Batched, throttled, ordered by key, resumable and idempotent. Not inside the schema migration's transaction.
- Handles rows written while it runs.
- Covers every place the value lives: all tables or collections, embedded copies, caches, search indexes.
- Ships with a verification query (how many rows remain) and progress logging.
- Unit or format conversions verified against what the producer actually writes, with the producer change landed first.
- A traceable, re-runnable migration, not a one-off script described only in the pull request text.

## Deploy order and rollback

- Does the migration work with both the previous and the new code version? Which goes first?
- Across services or repositories, is the producer and consumer order stated?
- Is there a way back? Reverting code does not reverse data. Can old code read rows the new code wrote?
- Irreversible steps (drops, lossy conversions) need a stated recovery plan.
- Re-running the migration must be safe.

## Destructive and lossy operations

- `DROP`, `TRUNCATE`, `DELETE` or `UPDATE` with a missing or broad `WHERE`. Cascading deletes.
- Narrowing: truncated strings, integer overflow, lost time zone or precision, charset and collation changes.
- Hard delete where soft delete is the convention. Retention and deletion obligations.

## Queries and indexes that come with the change

- A new query pattern on a growing table without its index in the same change. In multi-tenant data, an index that does not lead with the tenant key.
- A foreign key without an index. Unique indexes and how they treat nulls.

## ORM pitfalls

- Auto-generated migrations: read the SQL. A rename detected as drop plus add loses data.
- Model and migration drifting apart.
- Data changes mixed into schema migrations. Application models imported into migrations, which breaks old migrations when the models change.
- Two branches adding conflicting migration heads or version numbers.

## Formats outside the database

Each of these outlives a deploy:

- Queue and job payloads already in flight, and replays from a dead-letter queue.
- Cached values: version the key or read tolerantly.
- Serialized blobs, JSON columns, session data, token claims, cookies.
- Files in object storage, client-side storage, state persisted by installed apps.
- Search index mappings, event logs that get replayed.
- Checkpointed workflow or agent state: what does a resumed session see on its first step after the deploy? "It recomputes later" lowers the priority. It does not remove the finding.

Rule: readers tolerate unknown and missing fields, writers stay conservative, and a change of meaning gets a version.

## Semantic changes

The same column with a new unit, a new meaning for null, a reinterpreted enum or a different time zone is a migration and a contract change, even though no type changed.

## Repair scripts

Review them like production code: scoped `WHERE`, a dry-run count, batching, idempotency, logging, a backup. Sequence them after the fix is live, or the still-running old code undoes the repair.

## Verify by

- A migration linter if configured (see `static-analysis-integration.md`), and the framework's "show SQL" or dry-run output.
- Grepping every reader and writer of the field: raw SQL, serializers, analytics queries, other services.
- Reading the down migration.
- Checking for tests that run up, down, up, and that load old-shape fixtures.

## Do not flag

- Lock concerns on a table created in this change or known to be small.
- A missing down migration where the repository's stated convention is forward-only.
- Hypothetical volume. Ask for the size instead.

## Priority guidance

P0: data loss, a long exclusive lock on a large hot table, incompatibility with the previous version during rollout, a narrowed shape without a full backfill, an irreversible step with no recovery plan. When size or traffic is unknown and decides the outcome, raise a `[P0][question]`. P1: a safe but unthrottled backfill, a missing index for a new query on a table that is small today, a rollback path that exists but is not written down. Ordering and rollback steps that the author should follow belong in the deployment section: see `qa-and-rollout-plan.md`.
