# Ruby and Rails pitfalls

Use when: Ruby is the dominant language of the changed logic, with or without Rails.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever the project's linters already report.

## Language semantics

- Only `nil` and `false` are falsy: `0`, `""` and `[]` are truthy.
- `@value ||= compute` recomputes every time when the result is `nil` or `false`.
- `Hash.new([])` shares one default array between all keys. Use the block form.
- String keys versus symbol keys after JSON parsing or parameter handling.
- Bang methods and `<<` mutate arguments that the caller still holds. Constants holding mutable objects.
- `rescue => e` catches `StandardError` only. `rescue Exception` also swallows interrupts and exit.
- The inline `rescue` modifier hides every standard error. `retry` with no limit.
- `return` inside `ensure` discards the exception.
- `Timeout.timeout` can interrupt code anywhere, including cleanup.
- `&.` chains on a value that is required: the nil travels and the cause is lost.

## Dangerous calls

- `send`, `public_send`, `constantize` and `const_get` with user input.
- `eval` and `instance_eval` with strings. `Kernel#open` with a user-controlled path can start a process.
- `system` and backticks with interpolation. Use the multi-argument form.
- `YAML.load` and `Marshal.load` on untrusted data.
- Regular expressions that validate with `^` and `$`: those match line boundaries. Use `\A` and `\z`.
- User-controlled paths in file reads and `send_file`.

## ActiveRecord

- N+1 queries in loops and views. `present?` or `length` loading a whole relation where `exists?` or `count` would do.
- `update_all`, `delete_all`, `update_column`, `insert_all` and `upsert_all` skip validations, callbacks and usually timestamps.
- `save`, `update` and `create` return false or an unsaved record on failure. An unchecked result is a silent failure.
- **A uniqueness validation is not a constraint.** Without a unique index, two concurrent requests both pass. The same race exists in `find_or_create_by`.
- Read-modify-write on a counter or balance with no lock and no atomic update.
- `after_save` callbacks that enqueue jobs or call services run before commit: the job may not see the row. Use `after_commit`.
- External calls, emails and job enqueues inside a transaction that may roll back.
- `rescue` inside a transaction block that swallows the error and lets a partial write commit. `ActiveRecord::Rollback` raised inside a nested transaction without `requires_new` is ignored.
- `dependent: :destroy` on a large association loads every record.
- `enum` declared as an array: reordering changes the stored meaning. Use explicit values.
- `default_scope` surprises. `NOT IN` with a NULL in the list returns nothing.
- SQL fragments with interpolation in `where`, `order`, `pluck`, `joins` or `find_by_sql`.
- Iterating a whole table with `all.each` instead of `find_each`.

## Rails migrations

Rollout rules are in `data-migrations-compat.md`. Rails specifics:

- Adding an index without the concurrent algorithm on a large PostgreSQL table.
- Removing a column that running code still reads: the model must ignore it first.
- A data migration that uses application models breaks when those models change later.
- A `change` method that cannot be reversed automatically.
- Unrelated changes in `schema.rb` or `structure.sql`, which mean the file came from a different database state.

## Controllers and security

- Strong parameters that permit role, ownership or foreign-key fields, or `permit!`.
- A new action with no authentication or authorization callback, or a broad `skip_before_action`.
- `Model.find(params[:id])` instead of a lookup scoped to the current user or tenant.
- `html_safe`, `raw` and unescaped output. `link_to` with a user-supplied URL. `redirect_to` with a parameter.
- `render` with a parameter choosing the template or file.
- `to_json` or `as_json` serializing every attribute.
- New sensitive parameters missing from log filtering.
- Forgery protection skipped on a state-changing action that uses cookie authentication.

## Background jobs

- Jobs are retried, so they must be idempotent.
- Arguments must be simple serializable values. A record passed by reference may be gone when the job runs.
- A job enqueued inside a transaction can start before the commit.
- Rescuing without re-raising disables retries.

## Concurrency and memory

- Class-level and global mutable state under threaded servers and job processors. Thread-local data leaking between requests.
- Constants and file names that violate the autoloader's naming rules fail only when eager loading, which usually means production.
- `Time.now` and `Date.today` versus the zone-aware `Time.current` and `Time.zone.today`.
- Float for money. Month arithmetic at month ends.

## Verify by

- Running the specific spec or test file.
- The configured linter and, for Rails, the configured security scanner.
- Reading the schema file diff next to the migration.
- The autoloader check task after renaming files or constants.

## Do not flag

- Style the linter governs. Guard clause versus conditional taste. Metaprogramming that follows the codebase's established pattern.
