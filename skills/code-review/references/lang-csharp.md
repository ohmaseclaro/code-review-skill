# C# and .NET pitfalls

Use when: C# is the dominant language of the changed logic.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever the project's analyzers already report.

## Async

- `async void` outside event handlers: exceptions cannot be caught by the caller and can end the process.
- `.Result`, `.Wait()` and `GetAwaiter().GetResult()` on asynchronous code: deadlocks under a synchronization context, thread-pool starvation elsewhere.
- A task that is not awaited. An async lambda passed where an `Action` is expected, as in `List.ForEach(async x => ...)`.
- `Parallel.ForEach` with async lambdas does not wait for them. Use `Parallel.ForEachAsync`.
- A `CancellationToken` accepted and not passed on.
- `Task.WhenAll`: awaiting rethrows only the first exception.
- `lock` cannot contain `await`. `SemaphoreSlim` must be released in `finally`.
- `using` where `await using` is required for asynchronous disposal.
- Timer callbacks that overlap when one run outlasts the interval.
- A new `HttpClient` per request exhausts sockets. Use the client factory. Responses and streams left undisposed.

## Null, types and values

- Nullable reference types are compile-time hints. Deserialized objects can hold null in non-nullable properties. `!` and `#nullable disable` hide it.
- Mutating a struct returned from a property or a list element changes a copy.
- Records compare collection members by reference. `with` is a shallow copy.
- `double` for money. Integer overflow is unchecked by default.
- `DateTime.Now` versus `UtcNow`, conversions of unspecified `Kind`, and `DateTimeOffset` for instants.
- Culture-sensitive parsing, formatting and comparison for values that are persisted or sent over the wire. Use invariant culture and ordinal comparison for identifiers.
- Any integer can be cast to an enum. A switch expression without a default arm throws on the unexpected value.

## LINQ and collections

- Deferred execution: a query enumerated twice runs twice, and one returned after its context is disposed fails later.
- `First` versus `FirstOrDefault` versus `Single`: each one encodes an assumption about cardinality.
- Modifying a collection during enumeration.
- A `for` loop variable captured by a closure is shared across iterations.
- `Dictionary` written from several threads can corrupt itself. A `ConcurrentDictionary.GetOrAdd` factory may run more than once.

## Entity Framework Core

- Queries inside loops and lazy loading. Several collection `Include`s multiplying rows.
- `DbContext` is not thread-safe: parallel tasks on one context fail. A scoped context captured by a singleton.
- Multi-step writes with no transaction. `SaveChanges` inside a loop.
- Raw SQL with interpolated or concatenated strings instead of parameters.
- Bulk `ExecuteUpdate` and `ExecuteDelete` bypass change tracking and concurrency tokens.
- No concurrency token on entities updated by several users.
- Global query filters (tenant, soft delete) bypassed by `IgnoreQueryFilters` or raw SQL.
- Migrations: destructive operations, missing `Down`, and automatic migration at startup with several instances racing. Read the generated SQL.

## ASP.NET Core

- A new endpoint with no authorization, or an added `[AllowAnonymous]`. Role checks with no ownership check on the resource.
- Model binding straight onto entities allows over-posting.
- A scoped service injected into a singleton. `HttpContext` captured by background work.
- Middleware order: exception handling, authentication, authorization, CORS.
- CORS allowing any origin together with credentials.
- An unhandled exception in a hosted background service stops the host by default.
- User-specific responses cached without a per-user key.

## Resources, text and security

- `IDisposable` values not disposed, or injected dependencies disposed by code that does not own them.
- `throw ex;` resets the stack trace. `catch (Exception)` that swallows. Cancellation logged as an error.
- A regular expression with no timeout on user input.
- JSON deserialization with type-name handling enabled on untrusted input. `BinaryFormatter`.
- `Path.Combine` drops the first argument when the second is rooted.
- `Random` for security decisions. Non-constant-time comparison of secrets.

## Library compatibility

- Optional parameter defaults and `const` values are compiled into callers: changing them needs a recompile of every consumer.
- New overloads that make existing calls ambiguous. Changed nullability annotations on public APIs.

## Verify by

- `dotnet build` with the repository's warning settings and `dotnet test --filter` for the touched area.
- The enabled analyzers, including threading analyzers when present.
- The SQL script generated for a migration.

## Do not flag

- `var`, expression-bodied members and naming that the editor config governs.
- `ConfigureAwait(false)` in application code with no synchronization context, unless a repository rule asks for it.
