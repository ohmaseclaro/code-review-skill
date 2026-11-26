# Static analysis integration

Use when: linter, type-checker, test, SAST or CI output is available or needed, and before a deep review in a repository that has such tooling.

Principle: deterministic tools go first. The reviewer triages and explains their output and covers what tools cannot see (intent, cross-file reasoning, design). Never repost raw tool output, and never spend comments on what a tool already reports.

## 1. Use what the repository already has

1. Prefer existing CI results: `gh pr checks <n>`, `gh run view <id> --log-failed`, or `glab ci status`.
2. If CI has not run, or you are reviewing locally, run the project's own commands (package scripts, Makefile, task runner, pre-commit) and limit them to changed files where the tool allows.
3. Order: format check, lint, type check, tests for the touched modules, then security and dependency scans if configured.
4. Run only tools that are installed and configured in the repository. Do not install tooling or add configs during a review. Suggest them instead.

| Ecosystem | Typical commands |
| --- | --- |
| JS and TS | `npx eslint <files>`, `npx tsc --noEmit`, `npx biome check <files>` |
| Python | `ruff check <files>`, `mypy <pkg>` or `pyright`, `pytest <path> -q` |
| Go | `go vet ./...`, `staticcheck ./...`, `golangci-lint run --new-from-rev=<base>`, `go test -race ./<pkg>/...` |
| Rust | `cargo clippy --all-targets -- -D warnings`, `cargo test -p <crate>` |
| JVM | `./gradlew :<module>:check`, `detekt`, SpotBugs or Error Prone if configured |
| .NET | `dotnet build -warnaserror`, `dotnet format --verify-no-changes` |
| Ruby, PHP | `bundle exec rubocop <files>`, `phpstan analyse <paths>` |
| Shell, Docker | `shellcheck <files>`, `hadolint Dockerfile` |
| SQL migrations | `squawk <files>` for Postgres |
| IaC and CI | `terraform validate`, `tflint`, `checkov -d .` or `trivy config .`, `actionlint`, `zizmor`, `kubeconform` |
| Contracts | `oasdiff breaking <base> <head>`, `buf breaking --against <ref>`, `cargo semver-checks` |
| Dependencies and secrets | `osv-scanner`, `npm audit`, `pip-audit`, `govulncheck ./...`, `cargo audit`, `gitleaks` |

## 2. Safety

Tool configuration is code. JavaScript lint and format configs, analyzer plugin lists, test bootstrap files, package scripts, git hooks and Makefiles all execute repository-controlled code. A published incident in 2025 turned an analyzer config inside a pull request into remote code execution on a review service whose environment held its signing key.

- For changes from untrusted authors: do not run repository-configured tools on the change. Use CI results, or read-only analysis, or a sandbox with no credentials and no network.
- Never run tools with secrets in the environment.
- `npm install` and its equivalents run install scripts. Do not install a change's new dependencies outside a sandbox.

## 3. Triage tool output

- Keep only findings on lines this change added or modified. Many tools support this directly (`--new-from-rev`, baseline files, diff filters).
- Confirm each finding against the code before mentioning it. Drop false positives silently.
- CI already reports it to the author: do not repeat it. Mention a failing check once in the handoff when nobody has diagnosed it, or inline when it reveals a deeper defect.
- You ran the tool and nothing else surfaces the finding: include it, cite the tool and rule id, quote the tool's severity, set the priority yourself from the impact, and add the fix.
- Your own finding duplicates a tool finding: keep the tool's rule id, which is stable and suppressible, with your explanation.
- Tool findings on untouched lines of touched files are out of scope. One handoff line at most.
- A compile or type error in changed code is a `[P0][bug]` unless CI shows the build passing. In that case your local environment differs: say so and do not post it.

## 4. Suppressions and weakened gates in the diff

Every new suppression needs a narrow scope and a reason: `eslint-disable`, `@ts-ignore`, `# noqa`, `# type: ignore`, `//nolint`, `#[allow(...)]`, `@SuppressWarnings`, `NOLINT`, coverage-ignore pragmas.

- Work out what the suppression hides. If it hides a real error, flag the error, not the comment.
- File-level, rule-less or unexplained suppressions are findings.
- An existing, explained suppression on unchanged code is a recorded decision. Leave it alone.

Config changes that weaken a gate count as removed protections: a rule switched off, a threshold lowered, a path added to an ignore list, a CI job deleted or marked `continue-on-error`, `|| true` after a check, a test command narrowed.

## 5. Let tools verify your claims

| Claim | Verify with |
| --- | --- |
| "This will not compile or type-check" | The type checker or build |
| "This can be null here" | Strict types, or a five-line test |
| "This breaks the API" | `oasdiff`, `buf breaking`, API extractor, semver checker |
| "This migration takes a blocking lock" | A migration linter, or the database's documented lock behavior |
| "This test does not test the change" | Revert the production hunk in a scratch checkout and run the test: it should fail. Or run a mutation tool on the changed lines if one is configured. |
| "This version is vulnerable" | An advisory database lookup for the exact version |
| "My suggested patch is correct" | Re-run the same checks on the patch, or say it was not executed |

## 6. When there is no tooling

- Say so once in the handoff ("no linter or type check configured; style was not reviewed"). Do not compensate by policing style by hand.
- When the same mechanical review comment keeps recurring, recommend a lint rule or a custom pattern rule. A deterministic rule beats a prose rule and beats a reviewer.

## 7. Keeping structure

When collecting tool output, keep tool, rule id, severity, file, line and message. SARIF is the common interchange format. Findings outside the diff belong in a summary, not inline.
