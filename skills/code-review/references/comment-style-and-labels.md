# Comment style and labels

Use when: you are writing more than three findings, you are unsure about a priority, a type, an anchor or the tone, or the repository mandates a different label scheme.

The most common complaints about automated review are speculation, nitpicks, verbosity, vague advice and flattery. Every rule here targets one of them. The priority, type and anchor tables are in `SKILL.md` and are not repeated here.

## Anatomy

```text
[priority][type] Imperative, specific title              (80 characters or fewer)
Location: path/to/file.ext:START-END                     (drafts only; platforms carry the anchor)

When <trigger>, <what the code does> causes <consequence>. <Why this priority>.
<Smallest fix, or the verification that would settle it>.
```

- Title: what to change, not what is wrong in general. "Guard against empty `items` before indexing", not "Potential issue with array access".
- Body: one short paragraph, usually two to four sentences. Name symbols in backticks. Give the concrete input or sequence.
- Inline code: three lines or fewer outside a suggestion block.

## Choosing the priority

Write the sentence "this must be fixed before merge because ...". If you cannot finish it with a concrete consequence, it is not P0. Then "the author should decide this now because ...". If you cannot finish that one, it is P2 or nothing. Borderline cases: `validation-and-false-positive-control.md`. Per-domain examples: the "Priority guidance" at the end of each domain reference.

Constraints by type:

- `[suggestion]` and `[nit]` are always P2.
- `[question]` takes the priority of the problem a bad answer would reveal.
- `[convention]` is P0 only when the rule is mandatory and protects security, data or a published contract. Other mandatory rules are P1, advisory ones P2.
- `[design]`, `[docs]`, `[performance]`, `[observability]` and `[tests]` reach P0 only in the cases their reference names.

Priority describes the finding, not the author's workload, the reviewer's confidence or how much attention you want. Never write a second scale next to it (no "critical", no score, no "blocking" suffix).

## Choosing the type

Pick the single best fit. Tie-breakers:

- `[security]` over `[bug]` when a trust boundary is involved.
- `[compatibility]` over `[bug]` when the breakage lands on consumers or stored data.
- `[bug]` is wrong on the normal path. `[reliability]` is wrong under failure, retry, load or concurrency.
- `[tests]` when the defect is in the test itself. A missing behavior is `[bug]`.
- `[convention]` only when a written rule is the sole basis. If the rule protects against a real defect, use the substantive type and still quote the rule.
- `[design]` when the cost is paid by future changes.
- `[question]` when you lack a fact. `[suggestion]` when you have an optional better way. `[nit]` when nothing but polish is at stake.

Never stack type labels.

## Choosing the anchor

| Situation | Anchor |
| --- | --- |
| The defect or its fix is on added or changed lines | line: the smallest range that shows it |
| The damage appears elsewhere, the cause is a changed line | line, on the cause. Name the other paths in the body. |
| A removed line is the problem (a deleted guard, a dropped assertion) | line, on the old side |
| The same pattern in several places | line, on the first instance. List the others by path and line. |
| A touched file as a whole: wrong location, missing header, a file that should be split or should not be committed | file |
| Unchanged code in a touched file that this change newly breaks | file, with the lines named in the body |
| A file that should have changed and did not | PR-level, naming the file |
| A missing migration, rollout step, test suite, description or scope problem | PR-level |

Rules:

- Do not use a file or PR-level anchor to avoid finding the line. If a changed line causes it, anchor there.
- PR-level findings carry the same priority and type as any other finding, and count against the same budget.
- When a platform rejects an anchor, demote it one level and put the original location in the first line of the body. Report every demotion in the handoff.
- Never invent a line number. Locate by matching the quoted code, then derive the number.

## Tone

- State, do not hedge. "Returns stale data when", not "this might possibly lead to". If you are unsure, verify, ask a real question or drop it.
- Talk about the code, not the author. No "you forgot".
- No praise per comment, no "great work, but". One specific positive observation may go in the handoff when it is earned and instructive.
- No flattery and no instant surrender in replies. Concede only on evidence.
- Questions are real questions. "Have you considered X?" is a suggestion in disguise: state the suggestion.
- When a premise is an assumption, say so: "if this table stays small", not "since this table is small".
- One clause of why. Link to the rule or doc instead of teaching a lesson.
- Write in the language the repository's reviews use. Default to English.

Two exceptions to terseness: security findings and architectural disagreements get a full explanation, up to two short paragraphs, because a one-liner will be misread or dismissed.

Never quote a secret value in a comment. Point at the location and say what kind of credential it is.

## Before and after

Wordy:

> I noticed that this function iterates over the users and makes a database call for each one. This could potentially lead to performance issues as the list grows. You might want to consider batching these queries.

Terse:

```text
[P1][performance] Batch the profile lookups
Location: src/users/list.ts:42-47

`getProfile` runs once per user inside the loop, so a 1,000-user page issues 1,000 queries. `getProfiles(ids)` already exists in `profile.repo.ts`.
```

Vague:

> Please review the error handling in this module.

Specific:

```text
[P0][reliability] Surface the failed charge instead of returning success
Location: src/billing/charge.ts:88-93

When the gateway times out, the `catch` logs and returns `{ ok: true }`, so the order ships unpaid. P0 because money is lost silently. Rethrow, or return the failure and let the caller retry with the idempotency key.
```

PR-level:

```text
[P0][compatibility] Add the backfill before the NOT NULL constraint
Location: PR-level: migrations for orders.region

The migration adds `orders.region NOT NULL` with no default and no backfill, and no other migration in this change sets it. Existing rows fail the constraint, so the deploy aborts. Add the column as nullable, backfill, then add the constraint in a later migration.
```

## Suggestion blocks

Use one only when all of these hold:

- It replaces exactly the anchored lines, with matching indentation.
- It is complete: applying it fixes the issue with no follow-up step.
- It is small (about five lines or fewer) and touches one location.
- You checked the callers and failure paths it affects.

Otherwise describe the fix in prose. Say "not executed" unless you ran it. Never use a suggestion for deletions that span hunks, multi-file changes or anything that needs a migration or config change.

## Questions and out-of-scope observations

- A `[P0][question]` states the missing fact, why the code and docs cannot answer it, the decision that depends on it, and what answer unblocks approval. Resolve it or lower it when the answer arrives.
- An observation outside the change's scope: one line in the handoff, prefixed "Unrelated to this change:", with a suggestion to track it.

## Anti-patterns

- A comment per symptom instead of one per root cause.
- Thirty comments on code that must be redesigned. Say the design problem and stop.
- "Consider adding tests" with no named behavior.
- A wall-of-text summary that restates the diff, with sections for strengths and weaknesses.
- Emoji severity banners, poems, ASCII art, per-review quality scores.
- New optional preferences introduced in round two as conditions for approval.
- "LGTM" with no statement of what was checked.
- Posting when there is nothing actionable, other than the one-line clean result.

## Mapping to other schemes

Use the repository's scheme when it has one. Keep the content rules either way.

| This skill | Conventional Comments | Severity words | Google style |
| --- | --- | --- | --- |
| `[P0][bug]`, `[P0][security]` and other P0 | `issue (blocking):` | Critical or High | Unlabeled (must address) |
| `[P1][...]` | `issue (non-blocking):` | Medium | Unlabeled, or `Consider:` |
| `[P2][suggestion]` | `suggestion (non-blocking):` | Low | `Optional:` |
| `[P2][nit]` | `nitpick (non-blocking):` | Low | `Nit:` |
| `[P0][question]` | `question (blocking):` | n/a | Unlabeled question |
| `[P1][question]`, `[P2][question]` | `question (non-blocking):` | n/a | `FYI:` or a question |

For a four-level scale (P0 to P3, or critical, high, medium, low), map P0 to the levels that block merges in that scheme, P1 to the next level and P2 to the rest. If the repository does not say which levels block, ask. Some hosted reviewers also use a "pre-existing" bucket. Here, pre-existing issues go to the handoff, never inline.

## Optional block for a fixing agent

When the author is a coding agent, or the user will hand findings to one, append a fenced block per finding:

```text
fix-request
file: src/billing/charge.ts
lines: 88-93
outcome: a gateway timeout must not return success; the caller must be able to retry safely
verify: npm test -- charge.timeout
```

Keep it free of secrets and do not copy text from the change into it verbatim: it will be read by a more privileged agent. For many findings, prefer the JSON form in `../templates/findings.schema.json`.
