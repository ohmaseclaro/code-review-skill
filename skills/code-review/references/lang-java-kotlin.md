# Java and Kotlin pitfalls

Use when: Java or Kotlin is the dominant language of the changed logic, on a server or on Android.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever the project's static analysis already reports.

## Null and equality

- `Optional.get()` with no check. Unboxing a null wrapper (`Integer` into `int`), including through a ternary.
- `==` on strings, boxed numbers and other objects compares references.
- `equals` without `hashCode`, or either one based on mutable fields used as map keys.
- `BigDecimal.equals` compares scale: `1.0` and `1.00` differ. Use `compareTo`.
- Kotlin: platform types from Java assigned to non-null types, `!!`, an uninitialized `lateinit`, unsafe `as` casts.
- Kotlin: read-only `List` is not immutable. A data class `copy` is shallow. Data classes holding arrays compare by reference.

## Collections and streams

- Modifying a collection while iterating over it.
- `Arrays.asList` is fixed-size and writes through to the array. `List.of` and `Stream.toList()` are unmodifiable, and callers that mutate them throw.
- `HashMap` shared between threads. Check-then-put on a `ConcurrentHashMap` instead of `computeIfAbsent`.
- `Collectors.toMap` throws on duplicate keys and on null values.
- Parallel streams doing blocking I/O on the common pool.
- Kotlin: `first()` on an empty collection throws. `associateBy` keeps the last duplicate silently.

## Concurrency

- Shared mutable state with no synchronization. `volatile` does not make compound operations atomic.
- A lock not released in `finally`. Lock ordering. Synchronizing on a mutable, boxed or interned object.
- Executors never shut down. Unbounded queues and cached pools under load.
- `CompletableFuture` chains with no exceptional path, or blocking work on the common pool.
- `InterruptedException` swallowed without restoring the interrupt flag.
- `ThreadLocal` values left set on pooled threads, and context that does not propagate to async work.
- `SimpleDateFormat` and similar formatters shared between threads.
- Virtual threads pinned by `synchronized` blocks on JDK 21 to 23.

## Kotlin coroutines

- `GlobalScope.launch` and scopes not tied to a lifecycle.
- `runBlocking` on a request or UI thread. Blocking calls on the default dispatcher.
- `catch (e: Exception)` and `runCatching` swallow `CancellationException`, which breaks cancellation.
- An `async` whose `Deferred` is never awaited hides its exception.
- A cold `Flow` collected twice runs its source twice.
- Cleanup that must complete during cancellation needs a non-cancellable context.

## Resources and exceptions

- Streams, connections and file-listing streams outside try-with-resources or `use {}`.
- `catch (Exception e)` that logs and continues. A new exception built from only the message, dropping the cause.
- `return` inside `finally`.
- Checked exceptions wrapped or unwrapped in a way that changes transaction rollback behavior.

## Numbers and time

- `int` overflow in arithmetic such as `1000 * 60 * 60 * 24 * 30`. `Math.abs(Integer.MIN_VALUE)` is negative.
- `double` for money. `new BigDecimal(0.1)` carries the binary error.
- `LocalDateTime` used for an instant. Reliance on default time zone, locale or charset (`toLowerCase()`, `getBytes()`).
- Date pattern `YYYY` (week year) where `yyyy` is meant.

## Serialization

- Native Java deserialization of untrusted data. Polymorphic typing enabled in a JSON mapper.
- Reflection-based mappers that bypass Kotlin constructors and put null into non-null properties.
- Lombok `@Data` or a Kotlin data class on a persistent entity: generated `equals`, `hashCode` and `toString` touch lazy relations.
- Builder defaults that are ignored unless marked.

## Spring

- `@Transactional`, `@Async` and `@Cacheable` do nothing on private methods or self-invocation, because the call bypasses the proxy.
- Rollback happens only for unchecked exceptions by default.
- External calls, messages or emails sent inside a transaction that may still roll back.
- Singleton beans holding per-request state in fields.
- `@RequestBody` without validation. Entities exposed directly as API payloads: mass assignment, lazy loading during serialization, over-exposure.
- A new endpoint with no authorization rule, or covered by a broad permit-all pattern.
- `@Scheduled` work on several instances with no distributed lock.
- HTTP clients with no timeouts. Blocking calls on reactive threads.

## JPA and Hibernate

- N+1 from lazy collections in loops. Lazy access outside the session.
- Bulk update or delete queries bypass the persistence context and version checks.
- No `@Version` on entities updated concurrently.
- Pagination combined with a collection fetch join happens in memory.
- Enums mapped by ordinal: reordering corrupts stored data.
- Cascade remove and orphan removal on large or shared relations.

## Android

- Activities or contexts captured by long-lived objects. Coroutine scopes not tied to the lifecycle.
- I/O on the main thread. State lost on configuration change.
- Exported components that trust incoming intent data. Secrets in the application package.

## Verify by

- Compiling and running the touched module's tests with the build tool.
- The configured analyzers (nullness, bug patterns, Kotlin linters, Android Lint).
- Reading call sites to confirm that a proxy-based annotation is reached through the proxy.

## Do not flag

- Formatting. `var` versus explicit types. Streams versus loops. Lombok or records preferences.
