# Go pitfalls

Use when: Go is the dominant language of the changed logic.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever `go vet` and the project's linters already report.

## Errors

- Ignored errors: `_ =`, an unchecked `Close` on a written file, `rows.Err()`, `tx.Commit()`.
- `err` shadowed by `:=` in an inner scope, so the outer `err` stays nil.
- `%v` instead of `%w` when wrapping, which breaks `errors.Is` and `errors.As`. Errors compared with `==`.
- A nil pointer of a concrete type returned as `error` is a non-nil interface.
- `defer` inside a loop holds every resource until the function returns. Deferred arguments are evaluated when `defer` runs, not when the function exits.
- A panic in a goroutine crashes the process. `recover` works only in a deferred call in that same goroutine.
- `log.Fatal` and `os.Exit` skip deferred cleanup.

## Nil, slices and maps

- Writing to a nil map panics. A nil slice encodes as JSON `null`, an empty one as `[]`.
- `append` may share the backing array with the original slice: a write through one is visible through the other.
- A small slice of a large array keeps the whole array alive.
- Copying a struct copies slice and map headers, not their contents.
- Map iteration order is random. Concurrent map access is a fatal error that cannot be recovered.
- `for _, v := range items { v.x = 1 }` modifies a copy.
- Loop variables captured by closures and goroutines: each iteration has its own variable only when `go.mod` declares Go 1.22 or later.

## Goroutines, channels and context

- Goroutine leaks: a send or receive with nobody on the other end, or no cancellation path.
- One goroutine per item with no bound. Use a pool or a limited `errgroup`.
- `WaitGroup.Add` called inside the goroutine it counts.
- Closing a channel twice, sending on a closed channel, or closing from the receiving side.
- `select` with a `default` case spinning in a loop.
- `context.Background()` in a request path, a dropped `ctx` parameter, a `cancel` function never called, a context stored in a struct.
- A mutex copied by value with its struct. A lock not released on an early return. Atomic and plain access mixed on one variable.

## HTTP and I/O

- `http.Get` and a zero-value `http.Client` have no timeout. A server with no read, header and write timeouts.
- A response body that is not closed. `defer resp.Body.Close()` placed before the error check dereferences nil.
- The status code is not checked. A non-2xx response is not an error.
- `io.ReadAll` on a body with no size limit.
- JSON: unexported fields are skipped silently, `omitempty` drops meaningful zero values, numbers decoded into `any` become `float64`, key matching is case-insensitive.

## database/sql

- `rows.Close()` and `rows.Err()`. `sql.ErrNoRows` treated as a failure, or as success.
- `defer tx.Rollback()` missing, so an early return leaks the transaction.
- A query issued through `db` inside a transaction block runs outside the transaction.
- Scanning NULL into a non-nullable type.
- Calls without the `Context` variants ignore cancellation.

## Types, time and API

- Integer conversion that truncates or changes sign.
- `time.Duration(n) * time.Second` versus a bare integer treated as nanoseconds.
- `==` on `time.Time` values instead of `Equal`. Wall clock versus monotonic readings after serialization.
- A method with a value receiver that mutates its copy.
- Exported identifiers changed or removed in a module others import. A `v2+` module needs the version in its import path.
- `replace` directives left in `go.mod`.

## Verify by

- `go build ./...` and `go vet ./...`.
- `go test -race` on the touched packages.
- The configured linter, and `govulncheck` when dependencies changed.

## Do not flag

- Anything `gofmt` owns. The verbosity of `if err != nil`. Interface-first or generics preferences.
