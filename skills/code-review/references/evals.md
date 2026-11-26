# Evaluating a reviewer

Use when: you measure or tune this skill, compare reviewers, or decide whether a prompt, rule or model change helped.

Start from this: vendor benchmarks are self-run, self-defined and unstable, and every vendor wins its own. Leaderboard positions shift within months and the top tools sit within noise of each other. Build a small evaluation from your own changes.

## 1. What to measure

| Metric | Definition | Watch out for |
| --- | --- | --- |
| Precision | Valid findings divided by posted findings | Needs a validity judgment per finding |
| Recall by priority | Known issues found divided by known issues, reported per priority | An average hides misses on P0 issues |
| Comments per clean change | Findings posted on changes known to be fine | The most direct noise measure, and missing from most public benchmarks |
| Addressed or resolution rate | Share of findings the author fixed before merge | Rewards easy findings. Cannot measure what was never found. |
| Outdated rate | Share of comments whose flagged lines changed afterwards | A proxy, not proof of cause |
| Verifier kill rate | Candidates dropped by validation | Too high means noisy finders. Zero means the verifier agrees with everything. |
| Guardrails | Time to merge, human review time, cost and latency per review | One company rolled back showing AI output to reviewers after it added about 5% to review time |

Report precision and recall separately. A single F-score hides the trade-off that matters to a noise-sensitive team.

## 2. Build a golden set

Start with 30 to 50 changes from your own repositories.

- **Positives:** changes where a human review comment led to a code change, changes later reverted or hotfixed (trace the fix back to the change that introduced the bug), security fixes.
- **Negatives:** changes that merged cleanly and stayed stable for 90 days or more.
- **Label each known issue:** file and symbol, description, priority, type, evidence (the fixing commit or failing test), acceptable paraphrases.
- Two annotators on a sample, with agreement recorded. Keep a hold-out that is never used for tuning. Refresh periodically: public repositories leak into training data.

Injected bugs are cheap and useful for regression checks, but they are not distributed like real defects. Do not headline them.

## 3. Run protocol

- Pin base and head SHAs, tool versions and the model.
- Run each case at least three times. Reviews are not deterministic.
- Run an A/A pair (the same configuration twice) to learn the noise floor before reading any difference as an improvement.
- Keep transcripts and tool calls for failure analysis.

## 4. Judging

- Judge per item with explicit criteria: "was golden issue X covered: yes or no, with the quote" and "is finding Y valid: yes or no, with evidence". Holistic one-to-ten scoring agrees poorly with humans.
- Use a judge from a different model family than the system under test. Calibrate it on at least 100 human-labeled items and report agreement.
- Track two views: grounded (only golden issues count) and augmented (extra findings count when verified as valid). Otherwise real discoveries are scored as noise.
- When a finding's validity is unresolved, report precision as a range: unresolved counted as wrong, and as right.
- Text similarity to human comments is a weak metric. Prefer outcomes.

## 5. Test the rules

For every rule in a repository rule file, keep three small cases: a change that violates it, a safe counterexample, and an unrelated change. This measures recall, restraint and non-regression in one pass. A rule that fires on the counterexample or the unrelated case is noise: narrow or delete it.

## 6. Online signals

- **Resolved by merge.** Was the flagged problem fixed in the merged code? A model can judge this at merge time if you spot-check it against authors.
- **Code changed after the comment.** Cheap to compute, no clicks needed.
- **Explicit reactions.** Sparse: published figures are in the low single digits to about 10% of comments. Written replies carry more information.
- **Human comments on what the reviewer missed.** The best recall signal you will get in production.
- **Dismissal reasons.** Feed durable ones into the exception list of the rule file.

## 7. Avoid gaming yourself

- Resolution rate rises if you only flag trivial, always-fixed things. Pair it with priority-weighted recall.
- Address rate rises if you simply post less. Pair it with findings per change.
- Precision rises if the verifier drops everything uncertain. Check recall on the golden set after every filter change. A published account describes a real vulnerability dismissed by a security filter as a false positive.

## 8. Reference points

Ranges from published reports. They use different definitions and most are self-reported, so treat them as orientation, not targets.

- About a third of human review comments were classified as not useful in one large study.
- Authors acted on roughly 44% to 51% of human comments in two industrial reports.
- For automated reviewers, reported shares of comments acted on run from about 39% to about 78%, depending on the tool and on who measured.
- An executable benchmark that turns human review comments into tests found the best single tool passing about 32% and four tools combined about 42%.
- Industrial teams have used targets of 50% precision for suggested edits and 65% to 80% "useful" for comments.

## 9. Release gate

Gate a change to the reviewer on non-regression of precision and of P0 recall, not on an average score. Run new versions in shadow mode first: drafts that a human approves before anything is posted.

## 10. Log per finding

Identifier, content fingerprint, priority, type, anchor kind, evidence level, rule cited, whether it was posted or why it was dropped, outcome (resolved, dismissed with reason, ignored), and the reviewed SHA.

## Minimal starter

1. Pick 20 past changes with known review outcomes and 10 clean ones.
2. Label the known issues.
3. Run the reviewer three times on each.
4. Count valid findings, misses by priority and comments on the clean ones.
5. Change one thing, rerun, and compare against the A/A noise floor.
