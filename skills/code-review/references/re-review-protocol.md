# Re-review protocol

Use when: new commits arrived after your review, the author replied to findings, you are asked for a follow-up round, or threads need a status.

The failure modes this prevents: findings drip-fed across pushes, fresh nits on every push, contradictory comments between runs, approvals that outlive the code they covered, and flipping position the moment someone objects.

## 1. Establish what changed

```bash
git diff <last-reviewed-sha>..<head>                      # normal push
git range-diff <base>..<last-reviewed-sha> <base>..<head> # after a rebase or force-push
```

- Find the last reviewed head from your earlier review, a state marker or the platform's review record.
- Force-push where the old SHA is gone: review the full merge-base diff again and reconcile with the earlier findings.
- A push that leaves the change's own added and removed lines identical (clean rebase, merge of the base branch, empty commit): keep the previous result and say "no new changes since `<sha>`".
- A merge from the base branch with conflicts: review the conflict resolutions.

## 2. Walk the ledger of earlier findings

Give every earlier finding one state:

| State | Meaning |
| --- | --- |
| Resolved | You read the new code and the problem is gone |
| Still open | The code still has it |
| Superseded | The code it referred to was removed or redesigned |
| Withdrawn | New evidence showed it was wrong |
| Accepted risk | A P1 or P2 item the author declined with a reason, or a P0 that a human owner explicitly accepted |
| Not verifiable | You cannot check it from here; say why |

- A reply or a green pipeline is not a resolution. Read the code.
- Review the fix like new code, including the callers it touches. Fixes introduce regressions.
- Accept a correction that meets the required outcome even when it differs from your suggestion.

## 3. What a later round may raise

| Raise | Do not raise |
| --- | --- |
| Material defects introduced by the new commits | New style or architecture preferences on code you already reviewed |
| Material defects you missed earlier, stated plainly as missed, with why they matter | Nits on untouched lines |
| Anything that became worse | A finding the author declined with a reason that still holds |

- Keep acceptance criteria stable. Do not move the goalposts between rounds.
- In round one, report everything valid you found. Holding findings back for later rounds forces extra push and wait cycles.
- Halve the P1 and P2 budget in each later round.

## 4. Replies and pushback

- Judge the argument, not the tone. If the author is right, say so in one line and withdraw.
- If the author is wrong, restate the trigger and the evidence once. Do not repeat the same argument a third time.
- Never reverse a finding without new evidence, and never defend one without rechecking the code first.
- "Won't fix" or "acknowledged" on a P1 or P2 item closes it, unless a later commit makes it materially worse.
- Disagreement on a P0: evaluate the reasoning. If the owner accepts the risk knowingly, record it as accepted risk and report it to the user. The human decides.
- After three rounds without convergence, or when the count of open P0 findings stops falling, stop iterating and summarize both positions for a human decision.

## 5. Threads

- Continue the existing thread. Do not open a duplicate for the same finding.
- Resolve only threads you started, only after verifying the fix, and only when you are authorized to act on the platform. Otherwise report thread status in the handoff.
- Never resolve another reviewer's thread.
- When resolving, leave one line naming the commit that fixed it.
- "Outdated" on a platform means the anchor moved, not that the problem is fixed.
- Do not delete earlier comments. Deletion destroys the replies under them.

## 6. Verdict hygiene

- Recheck the head SHA immediately before any approval. Never approve a revision you have not reviewed.
- If you approved and a later commit adds a P0, say that the approval no longer stands, and withdraw it if you are authorized to.
- Distinguish in the round summary: required checks pending, relevant failures, unrelated infrastructure failures.

## 7. Matching findings across rounds

Line numbers shift. Identify a finding by its path, the normalized text of the flagged code and its root-cause statement. When you re-emit a finding that is still open, keep its title wording unchanged so people and tools recognize it. In the JSON form this identity is the `fingerprint` field.

## 8. Round summary

Report, in this order: range reviewed (`<old>..<new>`), resolved, still open (titles), new, withdrawn, accepted risk. A form is in `../templates/review-summary-templates.md`.
