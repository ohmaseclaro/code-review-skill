# PHP pitfalls

Use when: PHP is the dominant language of the changed logic, with or without a framework.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Skip whatever the project's static analyzer already reports at its configured level.

## Comparisons and types

- Loose `==` and type juggling. `in_array` and `array_search` without the strict flag. `switch` compares loosely, `match` strictly.
- A token or hash compared with `==`, or compared against JSON input that can be `true` or `0`. Use `hash_equals`.
- `strpos(...) == false` is also true for a match at position 0.
- `empty()` treats `"0"` and `0` as empty.
- Without `declare(strict_types=1)` scalar arguments are coerced, and the setting is per calling file.
- Casting a non-numeric string to a number yields 0 silently.
- Float for money.

## Arrays and references

- `foreach ($items as &$item)` leaves a live reference after the loop. The next loop that reuses the variable corrupts the last element. `unset` it.
- Objects are passed by handle: a callee that mutates one mutates the caller's.
- `array_filter` keeps the original keys, so the result encodes as a JSON object instead of a list. Use `array_values`.
- `array_merge` renumbers numeric keys. The `+` operator keeps the left side on key conflicts.
- `array_merge` inside a loop is quadratic.

## Failure reporting

- Functions that return `false` or `null` on failure and go unchecked: `file_get_contents`, `json_decode` (use `JSON_THROW_ON_ERROR`), `preg_match`, `strtotime`, `curl_exec`.
- `preg_replace` returns `null` on an internal error, which can silently erase the string.
- The `@` operator hiding failures.
- `catch (Exception $e)` inside a namespace, with no import and no leading backslash, matches nothing.
- `catch (\Exception $e)` does not catch `\Error`, which includes type errors.
- Byte functions (`strlen`, `substr`) on multibyte text.

## Security

- SQL built by interpolation or concatenation. Column and direction names taken from input need an allow-list.
- `unserialize` on untrusted data. File functions given user-controlled paths, including stream wrappers.
- `include` or `require` with input. `eval`. `extract()` on request data. Variable variables.
- Command execution with interpolated arguments. Escape each argument or avoid the shell.
- Output with no escaping. Raw output directives in templates.
- `header('Location: ...')` with no `exit` after it: the script keeps running.
- Redirect targets taken from input.
- Uploads: trusting the client-supplied type or extension, storing under the web root with an executable extension.
- `md5` or `sha1` for passwords instead of `password_hash`. `rand`, `mt_rand` and `uniqid` for tokens instead of `random_bytes`.
- Outbound requests to user-supplied URLs. TLS verification disabled.
- Session id not regenerated at login.

## Laravel

- `Model::create($request->all())` with a loose `$fillable` or an empty `$guarded`. Use validated data.
- A route outside the authenticated group, or an action with no policy or gate check.
- Route model binding that does not scope the record to its owner or tenant.
- Lazy loading in loops. Filtering in PHP after `get()` what the query could filter.
- `chunk` while updating the column being filtered skips rows. Use `chunkById`.
- `firstOrCreate` and `updateOrCreate` race without a unique index.
- Jobs, events and listeners dispatched inside a transaction run before commit unless configured to wait.
- Raw expressions (`whereRaw`, `orderByRaw`, `DB::raw`) with interpolated input.
- Validation rules `exists` and `unique` with no tenant scope.
- **`env()` outside config files returns null once the config is cached.**
- Queue job `timeout` must be shorter than the connection's `retry_after`, or the job runs twice.
- A queued job that carries a model fails if the record was deleted before it runs.
- Scheduled tasks with no overlap protection, or running on every server.
- `$hidden` missing for sensitive attributes that are serialized.
- From Laravel 11, changing a column drops every modifier that the migration does not restate.
- Query-builder updates skip model events. Removed global scopes drop tenant filtering.

## Runtime model

- Under long-running workers (application servers that keep the framework in memory, queue workers, daemons) static properties and singletons persist between requests. Request or user data captured there leaks to the next request.
- Queue workers keep running old code until they are restarted on deploy.
- HTTP clients with no timeout wait forever.
- `DateTime` and mutable date libraries change the original object. Prefer immutable variants.
- Adding a month to the 31st overflows into the following month.
- Default file sessions lock per session, so one slow request blocks the user's other requests.

## Composer

- `composer.lock` not updated with the manifest, or updated wholesale.
- Branch versions and lowered minimum stability.
- Newly allowed plugins and scripts execute code at install.
- A raised PHP requirement that the runtime image does not meet.

## Verify by

- `php -l` on the changed files.
- The configured static analyzer at the repository's level.
- The specific test with the framework's runner.
- `composer validate` and `composer audit` when dependencies changed.

## Do not flag

- Formatting standards the fixer enforces. Array syntax. Facade versus injection taste.
