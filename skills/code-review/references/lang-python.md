# Python pitfalls

Use when: Python is the dominant language of the changed logic.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever the project's linter and type checker already report.

## Language semantics

- Mutable default arguments (`def f(items=[])`) and defaults evaluated once at definition (`ts=datetime.now()`). Mutable class attributes shared by all instances.
- Closures created in a loop capture the variable, not its value.
- `is` used to compare values. `if x:` when `0`, `''`, an empty list or a zero duration are valid.
- A generator or iterator consumed twice yields nothing the second time. `zip` stops silently at the shortest input unless `strict=True`.
- `[[0] * 3] * 3` is one inner list three times. `list.sort()` returns `None`.
- Changing a dict or list while iterating over it.
- `str.strip('abc')` removes characters, not a prefix or suffix.
- Float for money. `round` uses banker's rounding. `//` floors toward negative infinity.
- `open()` with no `encoding` depends on the locale.
- `os.path.join(base, user_path)` discards `base` when the second part is absolute.

## Exceptions

- Bare `except:` and `except Exception: pass`. `except BaseException` also catches cancellation and interpreter exit.
- `except A or B:` catches only `A`. It needs a tuple.
- `return` inside `finally` swallows the exception.
- `assert` for validation in non-test code disappears under `-O`.
- Rethrowing a new exception with only the message, losing type and traceback.

## Time

- Naive and aware datetimes mixed. `datetime.utcnow()` returns a naive value.
- `time.time()` for durations instead of a monotonic clock.

## Typing

- Annotations are not enforced at runtime. A value typed `Optional` and used without a check.
- `cast()` and `# type: ignore` with no reason.
- Validation models that coerce silently (the string `"123"` into an integer), or constructors that skip validation.

## Async and concurrency

- Blocking calls inside `async def`: synchronous HTTP clients, `time.sleep`, synchronous database drivers, file I/O, heavy CPU work. They stall the whole event loop.
- A coroutine that is never awaited only produces a warning.
- `asyncio.create_task` with no stored reference can be garbage-collected mid-flight, and its exception is never seen.
- `gather` without a decision on `return_exceptions` and cancellation. Swallowing `CancelledError`.
- The interpreter lock does not make compound operations atomic: `x += 1` and check-then-set on a dict can interleave.
- Fork after threads or open connections exist. Database connections shared across forked workers.
- Module-level state in prefork servers and task workers: per process, not global, and not reset between requests.

## Resources and dangerous calls

- Files, sockets and sessions opened without `with`.
- HTTP requests with no `timeout`.
- `subprocess` with `shell=True` and interpolated input, with no timeout, or with the return code ignored.
- `pickle`, unsafe YAML loaders and `eval` on untrusted data. Archive extraction without path checks.
- `random` for tokens instead of `secrets`. `==` for comparing secrets instead of a constant-time comparison.
- `lru_cache` on methods keeps `self` alive. Unbounded caches keyed by user input grow forever. Cached mutable results are shared between callers.
- SQL built with f-strings or `%` formatting.

## Imports

- Circular imports. Network or database work at import time. A local module that shadows a standard library name.

## Django and Django REST Framework

- Lazy querysets inside loops (`select_related`, `prefetch_related`). `len(qs)` loads every row where `count()` would not.
- `QuerySet.update()` and `bulk_create()` skip `save()`, signals and `auto_now`.
- `obj.counter += 1; obj.save()` is a lost-update race. Use an `F` expression.
- Catching an exception inside `transaction.atomic()` and carrying on leaves a broken transaction.
- Tasks enqueued before commit run before the row is visible. Use `transaction.on_commit`.
- Views with no permission classes when the project default is permissive. `fields = '__all__'` exposing or accepting too much.
- `get_object_or_404(Model, pk=...)` with no owner or tenant filter.
- Data migrations that import models directly instead of using the historical model registry, or that have no reverse.

## SQLAlchemy and API frameworks

- A session shared across threads or requests. Lazy loads after the session closed, or implicit I/O inside async code.
- A helper that commits a transaction its caller owns.
- An `async def` endpoint that calls blocking code. Background-task errors that nobody observes. A new router with no auth dependency.

## Task queues

- Tasks must be idempotent when delivery is at least once.
- ORM objects passed as arguments instead of ids.
- Retry on every exception, with no backoff. A visibility timeout shorter than the task, which makes it run twice.

## Verify by

- Running the touched tests. The configured type checker and linter.
- A short REPL session to confirm a semantic you are unsure of.
- Treating warnings as errors to surface un-awaited coroutines.

## Do not flag

- Formatting and import order. Missing type hints where the repository does not require them. Comprehension versus loop taste.
