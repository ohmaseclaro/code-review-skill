# TypeScript and JavaScript pitfalls

Use when: TypeScript or JavaScript is the dominant language of the changed logic, in Node, a browser or an edge runtime. For UI components open `frontend-a11y.md` as well.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever the project's compiler settings and linter already report.

## Types are erased at runtime

- `any`, `as X`, `as unknown as X`, the non-null `!` and `@ts-ignore` are unchecked claims. Ask what guarantees each one.
- `JSON.parse`, `response.json()`, environment variables, query strings and message payloads typed by annotation only. Nothing validates them unless the code does.
- Optional chaining and `?? default` on a value that is required: the bug moves downstream and loses its cause.
- A `switch` over a union with no exhaustiveness check: a new member falls through silently.
- Index access typed as `T` when the key may be absent (unless `noUncheckedIndexedAccess` is on).
- Two identifiers of the same primitive type swapped at a call site (`userId` and `orgId`).
- Numeric enums accept any number.

## Values

- `if (count)` and `value || fallback` when `0`, `''` or `false` are valid. `??` only covers `null` and `undefined`.
- `==` coercion. `NaN !== NaN`. `typeof null === 'object'`.
- Integers above 2^53 (database ids, snowflakes) lose precision as numbers. Keep them as strings or `BigInt`.
- Floating-point money.
- `sort()` sorts in place and, with no comparator, compares as strings. `reverse()` and `splice()` also mutate.
- Spread and `Object.assign` copy one level. Shared nested objects are still shared. `Array(n).fill({})` is one object n times.
- `Date`: months are zero-based, `YYYY-MM-DD` parses as UTC while a date-time without an offset parses as local time, and arithmetic across daylight-saving changes.
- `JSON.stringify` drops `undefined` and functions, turns `Map` and `Set` into `{}`, and throws on `BigInt`.

## Async

- A promise that is not awaited or returned: its error is lost and ordering breaks.
- `forEach` with an async callback does not wait. `map` with an async callback needs `Promise.all`.
- `Promise.all` rejects on the first failure while the other operations keep running. Over an unbounded list it is also unbounded concurrency.
- `await` inside a loop: sequential when the work is independent, or accidentally parallel when order matters.
- `return promise` inside `try` skips the `catch` and `finally` timing that `return await` gives.
- State read before an `await` and used after it. Other code ran in between.
- An unhandled rejection terminates current Node versions by default.
- Timers and listeners never cleared. Requests with no abort signal or timeout.

## Runtime and modules

- Express 4 does not forward errors from async handlers: they need `next(err)` or a wrapper. A missing `return` after sending a response lets the handler continue.
- Query and body values can be arrays or objects where a string is assumed.
- Synchronous file, crypto or compression calls in a request path.
- Streams with no error handler, or `pipe` where `pipeline` would propagate errors and close both ends.
- Module-level mutable state shared across requests and, on a server, across users.
- Circular imports that yield `undefined` at load time. ESM and CommonJS interop surprises around default exports.
- A method passed as a callback loses `this`.
- A regex with the `g` flag keeps `lastIndex` between `test` calls. `replace` with a string pattern replaces only the first match. User-controlled input against a backtracking pattern.
- Merging user-controlled objects into plain objects (`__proto__`, `constructor`). Use `Map` or null-prototype objects for user-keyed maps.
- `catch (e)` is `unknown`. Non-`Error` values thrown. The original cause dropped when rethrowing.

## Frameworks

- Server-side entry points in full-stack frameworks (server actions, route handlers, loaders, RPC procedures) are public endpoints. Each needs its own authentication, authorization and input validation.
- Secrets imported into client bundles, or exposed through public environment-variable prefixes.
- DTO classes are not enforced unless a validation layer runs. Check that it is enabled and strips unknown properties.
- ORM calls inside loops, raw query helpers with interpolated strings, multi-step writes outside a transaction.

## Verify by

- The type checker with the project's own configuration. Do not assume `strict`.
- The linter. Rules for floating and misused promises need type information to work.
- Running the tests for the changed module.

## Do not flag

- Formatting, `interface` versus `type`, arrow versus function style.
- `any` in test fixtures, unless it hides the behavior under test.
