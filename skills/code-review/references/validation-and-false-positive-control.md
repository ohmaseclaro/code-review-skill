# Validation and false-positive control

Use when: a candidate finding is P0, security-related or about code outside the changed lines, when more than five candidates survive the review pass, or when you are unsure whether to keep one.

Why: precision, not recall, is what limits automated review. In one large study of a review bot, 43% of rejected comments were plain false positives. Vendors report that telling a model to "be careful" or to rate its own severity barely helps; a separate verification step does.

## Two stances, in order

1. **Find adversarially.** Assume the change has defects. Trace edge values through real code paths. Produce candidates freely.
2. **Validate skeptically.** Assume each candidate is wrong and try to prove that. Only survivors become comments.

Reviewers go soft in predictable ways: stopping at surface issues and assuming the rest is sound, accepting plausible logic without tracing boundary values, treating "it compiles" or "tests pass" as proof, reading only the changed file, and downgrading a real P0 to avoid seeming harsh. Check yourself against that list before finishing the find pass.

## Refutation checklist: where counterevidence hides

| Look at | Question |
| --- | --- |
| Call sites | Does any caller actually pass the triggering value? Search all of them. |
| Upstream guards | Validation middleware, schema parsers, early returns, decorators, router-level auth, type narrowing |
| Downstream guards | Database constraints, transactions, idempotency keys, unique indexes |
| Types | Does the type system forbid the case? A cast, `any` or `unsafe` voids that protection. |
| Framework behavior | Auto-escaping, parameterized queries, default timeouts, built-in retries. Verify in the docs or source for the pinned version, not from memory. |
| Tests | Is there an existing test that drives exactly this path and passes? |
| Configuration | Is the path enabled? What are the defaults and flag states? |
| Recorded decisions | ADRs, a comment giving a reason, a listed exception, an earlier review thread |
| History | `git log -S'<symbol>'` and blame: deliberate, or older than this change? |
| The rest of the diff | Is the "missing" piece in another file of the same change? |

## Drop, keep or ask

Drop a candidate when any of these is true:

- Its root cause is factually wrong.
- The failure path is impossible: an upstream guard, an unreachable branch, a type that forbids it.
- It is style or naming with no written rule behind it.
- It is a generic "missing X" with no concrete code path that suffers.
- The behavior is documented as intended by a comment, a doc or a test.
- It repeats a finding already addressed or dismissed earlier in this change.
- It existed before this change and the change does not worsen or expose it.

These are not reasons to drop:

- It is about concurrency or timing and therefore hard to reproduce.
- The root cause sits in another file than the one that shows the symptom.
- The line is not literally in the diff, but the diff changes what reaches it.
- "I recall the library handles this." Check.

Ask instead of asserting when the impact would be high and one fact is missing that the code and docs cannot give you. State the fact, what depends on it and what answer would settle it.

## Evidence ladder

| Level | Meaning | Good enough for |
| --- | --- | --- |
| Executed | You ran a test, repro or command and observed the result | Any finding |
| Traced | You followed the path with file and line for each step | Any finding, P0 included |
| Inferred | You reasoned from reading, with at least one unverified link | P1 and P2 findings. At P0, only as a `[P0][question]` |

Cheap executions worth doing in an isolated checkout: run the existing tests for the touched module, run the type checker or linter on changed files, write a five-line repro in a scratch file, grep every caller. Say "traced, not executed" in a comment when the difference matters. A design finding does not need a runtime repro. It needs the code relationship that causes the cost.

## Do not flag by default

- Pre-existing problems, generated or vendored code, lockfile noise.
- Anything a configured formatter, linter, type checker or CI job reports.
- Style, naming or structure preferences with no written rule.
- "Might", "could potentially", "consider" with no scenario.
- Intentional behavior changes, and code silenced with an explained suppression.
- "Add tests", "add docs", "add logging" without naming the behavior or failure they protect.
- Hypothetical scale, micro-optimizations, speculative future requirements.
- Restatements of what the code does, and requests to "verify" or "double check" something you could have checked.
- Versions, dates, APIs or model names you believe do not exist. Your knowledge has a cutoff. Check the lockfile, registry or docs before claiming something is invalid.

A repository's rule file can turn any of these back on. Then cite the rule.

## Confidence without numbers

Do not print a confidence score on a comment or on the review: readers over-trust it and self-rated numbers are poorly calibrated. Decide from observable facts: evidence level, a concrete trigger, the outcome of the refutation attempt, agreement between independent passes if you ran several, and how this kind of finding fared before in this repository.

## Dedupe

- One comment per root cause. If one fix resolves five symptoms, write it once and list the other locations.
- Do not merge two different defects because they share a line or vocabulary. Different trigger or different fix means different finding.
- Check existing threads, CI output and earlier rounds before posting.

## Calibrating priority

The criteria for each tier are in `SKILL.md`. Tests for the borderline cases:

- **P0 or P1?** P0 needs a realistic trigger on required behavior and a consequence that is costly or hard to undo. Bounded impact, low likelihood or an easy recovery makes it P1.
- **P1 or P2?** P1 names a cost someone will pay soon: a likely failure, a maintenance task made harder, important behavior left unprotected. If ignoring it only leaves the code slightly worse, it is P2.
- **P2 or nothing?** If the author could reasonably answer "no, thanks" and be right, drop it.

Rules of thumb:

- Weigh impact, likelihood and reversibility. Confidence is a reason to verify more, not a priority.
- When torn between two levels, choose the lower one and say what evidence would raise it.
- Self-healing ("it retries", "it is recomputed next run") lowers the priority. It does not remove the finding. Lead with what the user or operator sees first.
- A consequential failure that would be invisible or reported as success is P0 even when its trigger is rare.
- Time-critical harm (an exposed credential, an active data-loss path) is P0 with the required action in the first sentence. Never raise a priority to get attention.

## Budget and ranking

Order P0 findings by impact, then P1 and P2 by how likely the author is to act on them. Past the budget in `SKILL.md`, drop the weakest instead of appending them. Reviewers that keep precision high post few comments: published figures range from about 1 to 5 per review, and a clean review with zero comments is common.

## Single-agent verifier pass

1. Write the candidate list privately: claim, location, trigger, evidence so far.
2. For each one, run the refutation checklist as if someone else had written it.
3. Mark each KEEP, DROP or ASK with a one-line reason.
4. Write comments only for KEEP and ASK.
5. Optionally report in the handoff how many candidates were dropped.

If the host supports subagents, run step 2 in a fresh context that sees only the claim and the code: see `multi-agent-mode.md`.

## When you cannot verify

No checkout, private dependencies, monitoring you cannot see, production data you cannot query: say so in the handoff as a limitation. Missing evidence is a reason to hold approval or ask, never a proven defect.
