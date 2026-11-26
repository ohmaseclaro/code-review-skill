# Review rules

<!--
Template for a repository's own review rules. Copy it to the repository root as
.review-rules.md (or REVIEW.md), fill in what applies and delete the rest.
Keep it short: start with two or three rules that reviewers get wrong today.
A rule that a linter, type checker or CI job can enforce belongs there, not here.
-->

Scope: <whole repository | paths this file governs>. Owner: <team or role>. Last reviewed: <YYYY-MM-DD>.

## What matters most here

<Two or three sentences: what the system does, what a bad merge costs, and who gets paged.>

| Area | Paths | Why it is risky |
| --- | --- | --- |
| <Payments> | `<src/billing/**>` | <Money moves: every write must be idempotent> |
| <Tenant isolation> | `<src/**/repo/*.ts>` | <Every query must filter by tenant from the session> |

## Rules

One concern per rule. State the outcome, not the function to call. Say whether it is mandatory (must, never) or advisory (should, prefer): mandatory rules that protect security, data or a published contract are P0.

### <Short rule name>

- **Rule:** <One sentence. "Handlers must return failures through the shared error helper.">
- **Why:** <The failure it prevents.>
- **Applies to:** `<path glob>`
- **Wrong:**

  ```text
  <minimal example>
  ```

- **Right:**

  ```text
  <minimal example>
  ```

### <Short rule name>

- **Rule:** <...>
- **Why:** <...>
- **Applies to:** `<path glob>`

## Do not flag

- <Things this team has decided are fine: a pattern that looks wrong and is intentional.>
- <Anything enforced by: formatter, linter, type checker, named CI job.>
- <Generated and vendored paths: `<globs>`.>

## Exceptions

Path-scoped and dated. An exception records a reason, not a verdict.

| Rule | Path | Reason | Date | Review by |
| --- | --- | --- | --- | --- |
| <Rule name> | `<path glob>` | <Why the rule does not apply here> | <YYYY-MM-DD> | <YYYY-MM-DD or "permanent"> |

## Verification

| To check | Run |
| --- | --- |
| <Unit tests for one package> | `<command>` |
| <Type check> | `<command>` |
| <Migration safety> | `<command>` |

Checks that gate a merge: <names of the required CI jobs>. Checks that do not run in CI: <which, and when to run them by hand>.

## Rollout notes

- <How migrations are applied and in what order relative to code.>
- <How flags are created, ramped and removed.>
- <Where the release checklist or runbook lives.>

## Review output preferences

- Labels: <default `[P0|P1|P2][type]` | this team's scheme and its mapping>.
- Language: <English | other>.
- Comment budget: <default | lower for this repository>.
- Posting: <drafts only | post as comments, never approve | may approve>.

## Open questions for reviewers to ask

- <A fact that changes the verdict and cannot be read from the code, for example "which consumers still call v1?">
