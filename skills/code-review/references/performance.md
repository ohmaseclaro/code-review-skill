# Performance and resource use

Use when: the change touches queries, loops over data, caches, hot paths or payload sizes, or it claims a performance improvement.

Ground rule: a performance finding needs an execution path and a realistic size. Without both it is a guess.

## The questions

- How often does this run, and over how many items, today and at the growth the system already expects?
- What grows with N here: queries, memory, network calls, lock time?
- What is the worst input a user can cause, on purpose or by accident?

## Red flags

**Data access**
- A query or remote call inside a loop, including lazy loads triggered from a serializer, template or property access.
- Unbounded reads: no limit or pagination, loading every row or a whole file into memory.
- Fetching rows and then filtering, sorting, joining or counting in application code.
- A new filter, sort or join column with no supporting index. A function or implicit cast applied to an indexed column. A leading-wildcard match.
- Deep `OFFSET` pagination. A full count on a large table per request.
- The same query repeated within one request. Row-by-row writes where a bulk operation exists.

**Algorithms**
- Nested loops over user-sized collections. A linear search (`includes`, `find`, `in list`) inside a loop where a set or map belongs.
- Sorting, regex compilation or invariant computation repeated inside a loop.
- String building in a loop in languages where that is quadratic.
- Regular expressions that can backtrack catastrophically on crafted input.

**Memory**
- Accumulating full result sets. Reading large bodies or files fully instead of streaming.
- Caches and maps with no bound or eviction. Copies of large arrays in a loop.

**Concurrency and I/O**
- Sequential awaits for independent calls, or the opposite: unbounded parallel fan-out.
- Blocking I/O or heavy CPU work on an event loop or in an async runtime.
- Work done under a lock that does not need it. Connection pool starvation.

**Network and payload**
- Over-fetching fields. One call per item where a batch endpoint exists.
- Large serialized payloads with no pagination or compression.

**Caching**
- A cache with no invalidation path: that is a correctness bug first.
- Key cardinality that grows without bound. Per-user data in a shared cache.
- A cache added for something cheap: complexity with no measured gain.

**Startup and cost**
- Heavy imports or client initialization at module load in short-lived processes.
- Calls to paid services or models per request or per item with no cap.
- Log lines or high-cardinality metrics emitted in hot loops.

## Claims of improvement

When the description claims a speedup, ask for the method: what was measured, on what data, before and after. Complexity added for an unmeasured gain is a `[design]` finding.

## Verify by

- Counting queries on the path: a test with a query counter, or the query log.
- An execution plan on a development database with realistic volume, when that is safe.
- Reading the real N from code or config: page sizes, batch sizes, fan-out limits.
- Asking for table or collection sizes when they decide the outcome.

## Do not flag

- Micro-optimizations and loop style.
- Cold paths, admin scripts, tests and one-off jobs, unless the volume is clearly large.
- Hypothetical scale with no growth path. "Add a cache" as a reflex.

## Priority guidance

P0: a regression that makes a user-facing path time out or fail at current real sizes, unbounded memory or reads that a user can trigger, a query without an index on a large table in a hot path. P1: a measurable regression that stays within limits today, with the path and the size stated. P2: a cheaper equivalent with no measured need.
