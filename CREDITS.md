# Credits

This skill is a synthesis. Every sentence in the package was written for it, in its own words, but the ideas come from many people who published how they review code and how they build reviewers. Where a source shaped a specific part of the skill, that part is named.

Nothing listed here endorses this project. Licenses are noted where they were confirmed, and "see repository" where they were not.

## Primary inspiration

**Wellington (`@NetoRutes`)**, author of the `review-pr` skill that this package started from. It contributed the discipline at the center of the workflow: validate every candidate finding before commenting, label every comment with a merge status and a single type, and reach an explicit verdict with a short review body. The thirteen finding types, the three time horizons, the operating boundaries and the shape of the handoff follow that skill closely. The merge-status label became the `P0`, `P1`, `P2` scale described in `CURATION.md`.

## Open-source projects

| Project | License | What it informed |
| --- | --- | --- |
| [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official): `code-review` and `pr-review-toolkit` plugins | Apache-2.0 | Parallel finders followed by one validator per finding, the high-signal and do-not-flag lists, suggestion-block rules, the silent-failure, test, comment and type-design lenses |
| [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review) | MIT | Exploit scenario required, hard exclusions and precedents for security findings, the three-phase security pass |
| [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) | MIT | Sanitizing untrusted pull request content, CI hardening |
| [apache/airflow](https://github.com/apache/airflow): AI review instructions and criteria | Apache-2.0 | Signals of AI-generated changes, "tests a reviewer cannot fail by reverting the change", path-scoped instruction files |
| [openai/codex](https://github.com/openai/codex): review rubric and review guidelines | Apache-2.0 | Criteria for a finding worth flagging, priority tags, rule attribution, short matter-of-fact comments |
| [google-github-actions/run-gemini-cli](https://github.com/google-github-actions/run-gemini-cli) and [gemini-cli-extensions/code-review](https://github.com/gemini-cli-extensions/code-review) | See repository | Negative-space prompt rules: changed lines only, one issue per comment, no "please verify" |
| [The-PR-Agent/pr-agent](https://github.com/The-PR-Agent/pr-agent) (originally from Qodo) | See repository | Treating change content as untrusted data, comment caps, fallback when an inline anchor is rejected, fingerprints for dedupe |
| [kodustech/kodus-ai](https://github.com/kodustech/kodus-ai) | AGPL-3.0 with additional terms. Ideas only: no code or text reused. | Refute-to-drop verification with explicit drop reasons, guarding against over-merging distinct findings |
| [alibaba/open-code-review](https://github.com/alibaba/open-code-review) | Apache-2.0 | Verifier stance: keep by default, drop only on a stated reason |
| [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog) | MIT | Filtering tool output to changed lines, reporter modes |
| [danger/danger](https://github.com/danger/danger) | MIT | Mechanical pull request checks belong in CI, not in reviewer judgment |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | MIT | Terse one-line findings, with the exception for security and architecture |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | Simplification tags: delete it, the standard library has it, the platform has it, not needed yet |
| GSD (Get Shit Done) workflow and reviewer agents | See repository | Adversarial stance, "how reviewers go soft", failing closed on an unknown range, cross-reviewer consensus |
| gstack plan review | See repository | Shadow paths, interaction edge cases, reversibility against magnitude |
| Open Design review guidelines | See repository | Ownership by path, relevance before implementation review, tautological assertions |
| [conventionalcomments.org](https://conventionalcomments.org) | See site | Label mapping in `comment-style-and-labels.md` |
| [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | GPL-3.0 (used as a tool only) | Checking the two scripts |

## Open standards used by the installers

- [Agent Skills](https://agentskills.io): the skill layout, and the `.agents/skills` cross-client convention from its client implementation guide.
- Official documentation of each supported host, linked per row in `INSTALL.md`.
- [vercel-labs/skills](https://github.com/vercel-labs/skills) (the `skills` CLI): read for its install semantics only; no code reused.

## Vendor documentation and engineering write-ups

Used for mechanisms and for reported numbers. Vendor-reported numbers are marked as such in `CURATION.md`.

- **Anthropic:** Claude Code documentation on code review and the managed Code Review product (find, verify, rank, post; rule files read from the base branch; re-review behavior).
- **OpenAI:** Codex code review documentation and the engineering write-up on verifying code at scale.
- **GitHub:** Copilot code review documentation and changelog, REST and GraphQL documentation for reviews, comments, suggestions and check runs, Actions security hardening guidance.
- **GitLab:** merge request discussions, suggestions and draft notes API documentation, Duo code review instructions.
- **Atlassian:** Bitbucket Cloud and Data Center pull request comment APIs, and the Rovo Dev code review write-up.
- **Microsoft:** Azure DevOps pull request threads and votes documentation.
- **Gerrit:** review input and comment API documentation.
- **Cursor:** Bugbot documentation and engineering posts on multi-pass review, validation and learned rules.
- **Google:** engineering practices for code review, and the AutoCommenter and ML-suggested-edits write-ups.
- **Meta:** write-ups on risk-aware review routing and on AI-assisted review comments.
- **Uber, ByteDance, Cloudflare:** engineering write-ups on running LLM review at scale (generate, grade, filter, dedupe; tiering by size and sensitivity; re-review rules).
- **CodeRabbit, Greptile, Qodo, Graphite, Ellipsis, Cubic, Macroscope, Augment, Baz, Cognition, Factory, JetBrains:** product documentation and engineering posts on noise reduction, rule files, verification passes and comment budgets.
- **Semgrep, Snyk, Sonar:** documentation on triaging static analysis output and on combining tools with LLM review.

## Research

- Independent empirical study of 31,073 review-bot comments across 239 repositories: arXiv 2607.03316.
- "BitsAI-CR: Automated Code Review via LLM in Practice": arXiv 2501.15134.
- Atlassian Rovo Dev code reviewer study: arXiv 2601.01129.
- Lu et al., "Towards Practical Defect-Focused Automated Code Review" (ICML 2025): arXiv 2505.17928.
- AutoCommenter (Google): arXiv 2405.13565.
- RADAR, risk-aware review routing (Meta): arXiv 2605.30208.
- "Impact of LLM-based Review Comment Generation in Practice" (Mozilla and Ubisoft): arXiv 2411.07091.
- "Automated Code Review in Practice": arXiv 2412.18531.
- Ericsson experience report on LLM review with added context: arXiv 2507.19115.
- SWR-Bench: arXiv 2509.01494. c-CRAB: arXiv 2603.23448. CRJudgeBench: arXiv 2609.37216.
- Comparative study of LLM reviewers on real versus synthetic pull requests: arXiv 2606.15689.
- GitInject, prompt injection through repository content: arXiv 2606.09935.
- Kudrjavets et al., "Do Small Code Changes Merge Faster?" (MSR 2022): arXiv 2203.05045.
- Bacchelli and Bird, "Expectations, Outcomes, and Challenges of Modern Code Review" (ICSE 2013).
- Bosu, Greiler and Bird, "Characteristics of Useful Code Reviews" (MSR 2015).
- Mäntylä and Lassenius, "What Types of Defects Are Really Discovered in Code Reviews?" (IEEE TSE, 2009).
- SmartBear and Cisco code review study (review size and rate).

## Security guidance and incident write-ups

- OWASP Top 10:2025, which orders `security.md`.
- Kudelski Security's write-up of remote code execution in a hosted review bot through repository-controlled tool configuration.
- Public research on prompt injection against coding agents through pull request titles, issue text and hidden comments.
- Meta's "Agents Rule of Two" and Simon Willison's writing on the lethal trifecta, behind the rule in `prompt-injection-defense.md`.

## Practice

- Gunnar Morling's code review pyramid, for reading in order of cost to change.
- Gary Klein's premortem, behind the "how would this fail in production" questions.
- The engineers who documented their review habits in public posts and conference talks cited by the sources above.

## Corrections

If you are credited here and want the wording changed, or you see your work used without credit, open an issue. Attribution errors are bugs.
