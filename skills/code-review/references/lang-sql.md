# SQL pitfalls

Use when: raw SQL, query-builder calls, views, stored procedures, triggers, policies or index definitions change. Schema rollout is in `data-migrations-compat.md`, injection in `security.md`, query cost in `performance.md`.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Engine behavior differs: confirm against the engine and version the repository targets.

## NULL

- `NOT IN (subquery)` returns no rows when the subquery yields a NULL. Use `NOT EXISTS`.
- `col <> 'x'` and `NOT (a = b)` exclude NULL rows. `= NULL` is never true.
- `COUNT(col)` skips NULLs. `SUM` over no rows is NULL, not 0.
- String concatenation with NULL yields NULL in most engines.
- A unique constraint usually allows several NULLs.
- `CHECK (x > 0)` passes when `x` is NULL.
- NULL ordering differs between engines.

## Joins

- **Fan-out.** Joining two one-to-many relations multiplies rows and inflates `SUM` and `COUNT`. Aggregate before joining.
- `DISTINCT` added to hide duplicate rows from a wrong join.
- A filter on the right-hand table in `WHERE` turns a `LEFT JOIN` into an inner join. Move it into `ON`.
- `COUNT(*)` after a `LEFT JOIN` counts 1 for parents with no children.
- A missing or incomplete join predicate.
- `SELECT *` in views and in `INSERT ... SELECT`: a new column changes the result or breaks the statement. In PostgreSQL a view keeps the column list it had when created.

## Grouping, ordering and ranges

- Columns that are neither grouped nor aggregated return arbitrary values in permissive modes.
- `LIMIT` with no `ORDER BY`, or ordered by a non-unique column: pages overlap and skip rows. Add a unique tiebreaker.
- The default window frame ends at the current row and includes its peers, which surprises `LAST_VALUE` and running totals.
- `BETWEEN` on timestamps includes both ends, so boundary rows are counted twice across adjacent ranges. Use `>= start AND < end`.
- Integer division. Implicit casts between strings and numbers.
- Date truncation and `CURRENT_DATE` depend on the session time zone. Timestamp types with and without zone behave differently.
- Case sensitivity, collation and trailing-space handling differ by engine and column.
- `LIKE` with user input: unescaped `%` and `_` are wildcards.

## Writes

- `UPDATE` or `DELETE` with a missing or wrong predicate. Check the affected row count against a `SELECT` with the same predicate.
- An update joined to a non-unique match picks an arbitrary row.
- Upserts: which unique index decides the conflict, what happens with several unique keys, and what is returned when nothing was written.
- Replace-style statements delete and reinsert, firing cascades and changing generated ids.
- Insert-ignore modes swallow truncation and constraint errors along with duplicates.
- `MAX(id) + 1` and other read-then-insert id schemes race. Sequences are not gapless.
- Silent truncation of overlong strings in non-strict modes.

## Transactions and locking

- Read-modify-write with no lock. Prefer one atomic statement (`UPDATE t SET n = n - 1 WHERE id = ? AND n > 0`) and check the affected rows.
- A unique constraint is the only reliable guard against duplicate inserts. Check-then-insert races.
- Isolation defaults differ. Read committed allows a value to change between two statements. Serializable requires retry on failure.
- `SELECT ... FOR UPDATE` locks the rows it finds, not rows inserted later. Lock in a consistent order.
- Long transactions hold locks and block cleanup.
- DDL commits implicitly in some engines, ending the surrounding transaction.
- Session state (`SET`, advisory locks, temporary tables) leaks or breaks through a connection pooler in transaction mode.
- A foreign key with no index on the referencing column makes parent deletes slow and lock-heavy. PostgreSQL does not create that index for you.
- Triggers and cascades with effects the diff does not show.

## Query cost

Raise only with a table size or a plan.

- Predicates that cannot use an index: a function on the column, an implicit cast, a leading wildcard.
- Composite index column order versus the query's filter and sort.
- A new filter, join or sort on a large table with no supporting index.
- Deep `OFFSET` pagination. Exact counts over large tables for page totals.
- Large `UPDATE` or `DELETE` in one statement: lock time, log volume, replication lag. Batch it.
- Reads sent to a replica right after a write: replication lag breaks read-your-writes.

## Schema objects

- A function declared immutable or deterministic that is not: indexes and cached plans built on it return wrong results.
- Definer-rights functions with no fixed search path.
- Dynamic SQL inside procedures built by concatenation.
- Row-level security: a new table without it where its siblings have it, a policy that filters reads and does not check writes, roles that bypass policies.
- Grants and ownership of new objects.
- 32-bit auto-increment keys on tables that will grow large.
- Identifier length limits that truncate silently.

## Verify by

- `EXPLAIN` on the engine in use. `EXPLAIN ANALYZE` executes the statement: never run it on production data, and wrap writes in a transaction that you roll back.
- Running the query against a local database seeded with NULLs, duplicates, ties and an empty set.
- Printing the SQL that an ORM or query builder actually generates.
- The configured SQL or migration linter.

## Do not flag

- Keyword case, alias and comma style.
- `SELECT *` in ad hoc or test code. Missing indexes on small lookup tables.
- Portability to engines the repository does not target.
