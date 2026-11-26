# Shell pitfalls

Use when: shell scripts, Makefile recipes, CI `run:` blocks, Dockerfile `RUN` lines, git hooks or container entrypoints change.

These are patterns to check, not findings. Each needs a trigger and a consequence in this change. Shell fails quietly and destructively: the realistic trigger is usually an empty variable, a space in a path or a command that failed earlier.

## Quoting and word splitting

- Unquoted expansions split on spaces and expand globs. `rm -rf $DIR/` with an empty `DIR` is `rm -rf /`. Quote, and guard with `${DIR:?}`.
- `$@` and `$*` unquoted. Use `"$@"`.
- `[ $x = y ]` breaks when `x` is empty. `[ -n $x ]` is always true when unquoted.
- `for f in $(ls)` and `$(find ...)` break on spaces. Use globs, `find -print0 | xargs -0`, or `while IFS= read -r`.
- `read` without `-r` eats backslashes.
- A command built in a string and run with `eval` or unquoted. Use an array.
- `eval` with any external input.
- An unquoted heredoc delimiter expands variables and commands inside it.

## Failure handling

- No stated policy for errors, unset variables and pipelines. `set -e` alone is not one:
  - It does not fire inside `if`, `&&`, `||` or a function called from a condition.
  - `local x=$(cmd)` and `export x=$(cmd)` hide the command's status.
  - Without `pipefail` only the last command of a pipeline counts, so `cmd | tee log` hides a failing `cmd`.
- With `set -e`, a `grep` that finds nothing and `((i++))` evaluating to zero both end the script.
- With `pipefail`, a reader that exits early (`head`, `grep -q`) makes the writer fail on a closed pipe.
- `cd "$dir"` unchecked, followed by a destructive command in the wrong directory.
- `cmd || true` swallowing every failure.
- Background jobs with no `wait`, or a `wait` that only sees the last status.
- No `trap` to clean up temporary files, locks and child processes.
- `[ "$a" > "$b" ]` is a redirection that creates a file. Use `-gt` for numbers.
- Numbers with leading zeros are octal in arithmetic: `08` is an error.

## Portability

- `#!/bin/sh` with bash features: `[[ ]]`, arrays, `source`, process substitution, `&>`, `${var,,}`. On many systems `sh` is not bash.
- macOS ships bash 3.2: no associative arrays, `mapfile`, `${var^^}` or `wait -n`, and an empty array is an error under `set -u`.
- BSD versus GNU tools: `sed -i` needs an argument on BSD, `grep -P`, `date -d`, `readlink -f`, `stat` flags, `xargs -r`, `base64` flags and `timeout` differ or are absent.
- Minimal container images have no bash and reduced tool flags.
- CRLF line endings break the interpreter line. A lost executable bit breaks the hook or entrypoint.
- Paths relative to the current directory instead of the script's directory.
- A minimal `PATH` and no terminal under cron, CI and service managers. Prompts hang.
- Sorting and character ranges depend on the locale.

## Security

- Secrets on a command line are visible in the process list and in CI logs. `set -x` prints them too.
- Environment dumps (`env`, `printenv`, `set`) in logs.
- `curl ... | sh`. `curl` without `-f` treats an HTTP error page as success and pipes it onward. TLS checks disabled.
- Predictable names under `/tmp`. Use `mktemp`.
- File names from outside: leading dashes (`rm -- "$f"`), newlines, globs.
- `find -exec sh -c "... {}"` splices file names into code. Pass them as arguments.
- `ssh host "cmd $var"` is parsed again by the remote shell.
- `source` on a file that is data. `export $(cat .env | xargs)` breaks on spaces and quotes.
- Untrusted archives extracted without path checks.
- `chmod 777`, world-writable outputs, a permissive `umask`.

## Concurrency and idempotence

- Two instances running at once (cron overlap, CI retry) with no lock.
- Files written in place while others read them. Write to a temporary file and `mv` it on the same filesystem.
- `sort file > file` empties the file before reading it.
- Appending to a config file on every run.
- Fixed `sleep` instead of polling for readiness with a timeout.
- Variables set inside `cmd | while read` are lost after the loop in bash.
- An entrypoint that does not `exec` the final command: the application never receives termination signals.

## Make

- Each recipe line runs in its own shell: a `cd` on one line does not affect the next.
- Shell variables need `$$`.
- A target with no `.PHONY` stops running once a file of that name exists.
- The default shell is `sh`. Partial outputs survive a failed recipe unless `.DELETE_ON_ERROR` is set.

## Verify by

- `shellcheck`, with every finding fixed or suppressed with a stated reason.
- `bash -n` for syntax.
- A run in a temporary directory under `bash -x` with an empty variable, a value containing spaces, a value starting with a dash and a missing file.
- A run under the oldest shell the script claims to support.
- A workflow linter for `run:` blocks.

## Do not flag

- `[[ ]]` versus `[ ]` under a bash interpreter line. Backticks versus `$( )` beyond a nit.
- Portability to shells and systems the repository does not target.
- A blanket demand for `set -euo pipefail`: name the failing command that would go unnoticed.
