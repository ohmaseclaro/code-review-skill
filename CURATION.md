# Curation notes

How this package was distilled: what was kept, what was dropped, where sources disagreed, how sure each part is, and what is still open. Sources are listed in `CREDITS.md`.

## Method

The inputs were seven research reports (commercial review bots, reviewers built inside large engineering organizations, open-source reviewers, LLM techniques and evaluation, human review practice, static analysis and repository conventions, product and security), the `review-pr` skill by Wellington, and a set of public agent skills, plugins and review instructions. Claims that conflicted or looked weak were checked against primary sources on the web.

Evidence was graded before it was allowed to shape the skill:

| Grade | Meaning | Use |
| --- | --- | --- |
| Primary | A paper, source code or official documentation | Can shape a rule |
| Convergent | The same mechanism reported independently by several unrelated teams | Can shape a rule |
| Vendor-reported | One vendor's number about its own product | Quoted as such, never the sole basis |
| Unsourced | From memory or without a traceable source | Used qualitatively or dropped |

Everything in the package is written in its own words. Nothing was copied from any source.

## What was kept

| Idea | Where it lives | Basis | Confidence |
| --- | --- | --- | --- |
| Find, verify, rank, post, with verification as a separate step | `SKILL.md` step 5, `validation-and-false-positive-control.md`, `multi-agent-mode.md` | Convergent: Anthropic, Cursor, Uber, ByteDance, Kodus, Alibaba, Factory, Baz | High |
| Precision over recall, small comment budgets, zero findings allowed | `SKILL.md` step 6 | arXiv 2607.03316, SWR-Bench, OpenAI and Google write-ups, reported 1 to 5 comments per review | High |
| A verifier that drops only on a stated reason | `validation-and-false-positive-control.md` | Source code of two open-source reviewers | Medium to high |
| Verdict before reasoning in the verifier | `validation-and-false-positive-control.md` | One paper (77.1% against 65.8% precision) | Medium |
| No numeric confidence in the output, an evidence ladder instead | `validation-and-false-positive-control.md`, the `confidence` enum in the schema | Self-rated severity reported as close to random, a public plugin that removed its 0 to 100 score, user complaints about misleading scores | Medium |
| Discover the repository's own rules, nearest file wins, quote before citing | `SKILL.md` step 2, `repo-rules-discovery.md`, `scripts/discover-rules.sh` | Documentation of many tools, plus the study showing that 42% of rejected bot comments were valid but mismatched with team practice | High that the files exist, medium on each tool's exact semantics |
| Depth by risk, with size as one signal | `SKILL.md` step 3, `scripts/diff-triage.sh` | Tiering published by two large deployments, a routing lesson that size alone misroutes | Medium |
| Priority, type and verdict discipline | `SKILL.md` steps 6 and 7 | The `review-pr` skill, the Codex rubric, Conventional Comments | Design choice |
| Follow-up rounds: a ledger, only what changed, respect a reasoned "won't fix" | `re-review-protocol.md` | Convergent across three vendors | Medium to high |
| The change is untrusted input | `prompt-injection-defense.md` | arXiv 2606.09935, a documented remote code execution in a hosted reviewer, the Rule of Two | High |
| Tools first, the model triages their output | `static-analysis-integration.md` | Tool vendors' documentation, one industrial experience report | Medium to high |
| Signals of AI-generated changes | `ai-generated-code-review.md` | Apache Airflow's review instructions, vendor surveys | Medium |
| Large changes: map first, sample by risk, suggest seams | `large-pr-strategy.md` | Recall falls as changes grow (SWR-Bench), published size guidance | Medium |
| Evaluate on your own history, with clean negatives and repeated runs | `evals.md` | Benchmarks where real-change F1 is far below synthetic (0.066 against 0.847 in one study), offline metrics that failed to predict online results | Medium to high |
| Domain checklists | Fourteen domain references | The `review-pr` skill, public review criteria, OWASP Top 10:2025, common engineering practice | Medium: consistent across sources, not measured |
| Language pitfalls | Eleven `lang-*.md` files | Language documentation and well-known failure classes, not the corpus | Medium |
| QA steps, deployment order, related changes | `qa-and-rollout-plan.md` | Owner requirement, expand and contract practice | Low to medium |
| Target resolution | `SKILL.md` step 1, `target-resolution.md` | Owner requirement, the "never guess a range" rule from two public skills | Design choice |

## What was dropped

- **Pricing, funding, market share and vendor rankings.** Unstable, often self-run, and irrelevant to how to review.
- **Model names and per-model scores.** They age in weeks, and the skill is model-neutral.
- **Hosted-service architecture:** webhooks, queues, tenancy, billing.
- **Numeric confidence scores and score thresholds.** See the conflicts below.
- **Walkthrough summaries, diagrams, emoji severity scales, poems and review scores.** These are the verbosity that users complain about. One study found that showing AI output to reviewers increased review time.
- **Auto-approve and auto-merge.** The skill never approves without explicit authorization.
- **Majority voting over many randomized passes as a default.** Effective and expensive. It survives as the optional multi-agent mode.
- **Learned-rule machinery and embedding-based suppression.** They need feedback data and infrastructure that a skill does not have. The idea survives as the dated exceptions table in `templates/review-rules.template.md`.
- **A dedicated history or blame pass.** One public plugin had it and removed it. Recent history is used only to understand intent.
- **A fourth priority tier, a separate blocking label and an urgency flag.** See the design notes.
- **Style rules per language.** Formatters and linters own them.
- **Percentages quoted from memory** in the research (shares of defect and maintainability comments in human review). Used only qualitatively.
- **Anything specific to one organization's codebase.**

## Conflicts and resolutions

| Conflict | Resolution |
| --- | --- |
| "If you are not certain, do not flag" against "keep a finding unless it is refuted" | Two stances for two stages. Generate candidates freely in private. A candidate becomes a comment only after a disproof attempt. Unverifiable and low impact: drop. Unverifiable and high impact: ask. |
| Severity schemes: a binary merge status, P0 to P3, important and nit, critical to low | One scale, P0 to P2. See the design notes. |
| Comment caps differ by vendor (from under one per review to twelve) | P0 uncapped. P1 and P2 together capped at 2, 5 or 8 by tier. The numbers are a judgment inside the published range. |
| Rule files read from the base branch (two vendors) or the head branch (one vendor, changed in 2026) | Base for untrusted authors or when the change edits rule files, working tree otherwise. `discover-rules.sh --source base` implements it. |
| One public plugin's README describes a score threshold of 80, its command uses per-finding validation with no score | The command is current and the README is stale. The skill validates and prints no score. |
| Single agent or many | Repeated aggregated runs more than doubled recall in one benchmark, at a cost many hosts cannot pay. Single agent by default, multi-agent as an option at the deep tier. |
| Affiliation of arXiv 2505.17928 given as two different companies | Checked: Lu et al., ICML 2025, authors mostly at Kuaishou. Not material to the skill. |
| Whether Copilot code review reads custom instructions from base or head | Checked: head branch since a July 2026 changelog. `repo-rules-discovery.md` treats per-tool behavior as something to confirm. |
| A 4,000-character limit on Copilot review instructions | Unresolved. The advice to keep rule files short does not depend on it. |
| Heading that Codex looks for in `AGENTS.md`: "Review guidelines" or "Code Review Rules" | Both appear in official material. The skill matches either. |
| c-CRAB quoted as "about 40%" | Best single tool 32.1%, union of four 41.5%. Quoted precisely or not at all. |
| Acceptance rates for one industrial study differ between the paper and its slides | Different denominators. No number used. |
| Vendor benchmark rankings disagree with each other | All rankings dropped. |
| Two figures for machine-suggested edits at one company | Different measures. Not used. |
| Scale of the hosted-reviewer remote code execution (headline against write-up) | No number used. The mechanism is what matters: repository-controlled tool configuration is code execution. |
| Internally inconsistent offline numbers in one paper | Only its verdict-first comparison is used, marked single-source. |
| Whether multi-line suggestions can always be applied on GitHub | `platforms.md` restricts suggestions to small single-range replacements and marks specifics "verify". |
| Date of the `pull_request_target` default change | Checked: announced in November 2026, effective 2 December 2026 for public repositories. `infra-iac-ci.md` is worded without version assumptions. |
| License of PR-Agent reported as MIT and as Apache-2.0 | Unresolved. `CREDITS.md` says "see repository". Nothing was copied from it. |

## Design notes

### One priority scale

The `review-pr` skill labels every comment with a merge status (blocking or non-blocking) and a type. The owner of this package asked for priorities P0, P1 and P2. Carrying both would create two overlapping systems and contradictory labels such as a non-blocking P0.

Options considered: keep the binary label and add a priority, adopt P0 to P3 as some public rubrics do, or make the priority the merge status. The third was chosen:

- **P0 blocks.** Its criteria are objective and listed in `SKILL.md`.
- **P1 is decided now.** It does not block, but the author either fixes it or records a follow-up. This is the tier a binary scheme lacks: real defects with bounded impact otherwise get inflated to blocking or buried among nits.
- **P2 is optional.**
- **No P3.** With P2 already optional, a fourth tier only separates "optional" from "more optional", and the `[nit]` type already carries that.
- **No urgency flag.** A time-critical risk is P0 with the required action in the first sentence.
- **Types are unchanged** and orthogonal: thirteen, from the `review-pr` skill.
- **`blocking` in the JSON form is derived** from the priority, for consumers that want a boolean. The schema rejects a mismatch.

A P0 question blocks like a P0 defect. The verdict tells them apart: Request changes for a validated defect, Hold when only questions or a validation gap remain.

### Three anchors and a demotion ladder

Platforms reject comments on lines outside the diff, and on GitHub one rejected comment fails the whole batch. Reviewers then drop the finding or attach it to an unrelated line. Both are worse than a comment at a coarser level. So every finding has a line, file or PR-level anchor, a rejected anchor is demoted one level, and nothing is dropped silently.

### Optional sections

QA steps and deployment order appear only when they say something specific to the change. A fixed section that is usually empty trains readers to skip it. Three rules keep these sections honest: something the change must contain is a finding, not a plan step; a manual step that could be an automated test is a `[tests]` finding; every deployment step is marked confirmed or inferred, and no infrastructure name is invented.

### Structured output

The JSON form mirrors the draft. Its `confidence` field is an evidence level (executed, traced, inferred), not a probability, because self-rated probabilities are poorly calibrated. Fingerprints must not depend on line numbers, which move on every rebase.

### Target resolution

Proceed on a sensible default and state it. Ask only when the plausible targets differ materially. Never guess a range. Whole-file review is treated as a different task: there is no "introduced by this change" filter and no pre-existing bucket. Both scripts take the same target flags so that the skill passes one set.

### Scripts

Bash 3.2 with no awk, jq or python, so that they run on a stock macOS and in minimal containers. They are read-only. Besides git, find and grep they use POSIX `sed`, `sort`, `uniq`, `head`, `wc`, `tr` and `cat`: a small deviation from the original brief, which named only git, find and grep. Their output separates strong path matches (`load:`) from weak keyword matches (`consider:`) because early versions over-routed on keywords.

## Confidence by area

| Area | Confidence | Why |
| --- | --- | --- |
| Pipeline and validation discipline | High | Independent convergence and one large empirical study |
| Comment style and budgets | High on direction, medium on numbers | Consistent complaints and published ranges |
| Security checklist | High | OWASP and established practice |
| Prompt-injection threat model | High on the threat, medium on completeness | Research is recent and attacks evolve |
| Rule-file inventory | High that the files exist, medium on precedence and size limits | Tool behavior changes monthly |
| Platform API details | Medium | GitHub is well documented. Items marked "verify" for GitLab, Bitbucket, Azure DevOps and Gerrit were not exercised |
| Domain checklists | Medium | Experience-based, consistent across sources, not measured |
| Language pitfalls | Medium | Standard knowledge, with version-specific claims that will age |
| Evaluation guidance | Medium to high | Several benchmarks agree on the pitfalls |
| Tier thresholds (50 and 400 lines, 20 files) | Low to medium | Judgment anchored on published ranges |
| QA, deployment and related-change discovery | Low to medium | Sound practice, little direct evidence about reviewers producing it |
| Multi-agent host notes | Low to medium | Host features change quickly and were not tested on every host |
| This skill's own precision and recall | Unknown | Not measured |

## Open questions

1. **No benchmark run.** The skill has not been measured against a golden set or a baseline. `references/evals.md` describes how.
2. **Does P1 get acted on?** Track the resolution rate of P1 findings. If it is low, P1 is noise.
3. **Budgets of 2, 5 and 8** should be tuned per repository.
4. **Verdict-first verification** rests on one source.
5. **Triage heuristics** were exercised on a handful of repositories. Their false-match rate on other stacks is unknown.
6. **Do the optional sections help?** Measure how often they are emitted and used.
7. **Platform items marked "verify":** file-level positions on GitLab and Bitbucket, file-level comments inside a batched GitHub review, Azure DevOps thread contexts.
8. **Subagent behavior per host** needs checking against current versions.
9. **Feedback memory is manual** (the exceptions table). Automated learning is out of scope.
10. **Windows:** the scripts need a bash environment and were not tested there.
11. **Unresolved facts:** the Copilot instruction size limit, the PR-Agent license, and the GitHub alias placeholder in `CREDITS.md`.

## Known limits

- A clean review does not prove correctness. The skill says what it checked, not that the code is right.
- The scripts are heuristics. Path and keyword matches point at where to look.
- Rule-scope globs are approximated, so the skill reads a rule file before citing it.
- All text is in English.
