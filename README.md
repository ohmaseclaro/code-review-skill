# Code Review Skill

An agent skill that reviews code the way an accountable senior engineer does: it finds the problems a change introduces, proves each one before raising it, and says plainly whether the change can merge.

It is a multi-file, progressively disclosed package in the open Agent Skills layout (`SKILL.md` plus `references/`, `scripts/` and `templates/`), so any host that loads skills can use it. Nothing in it is tied to one agent, one model or one hosting platform.

## Why another review skill

Automated review rarely fails for lack of comments. It fails on precision. In an independent study of 31,073 comments from one review bot across 239 repositories, 36.4% were accepted and 56.3% rejected, and 43.3% of the rejections were plain false positives (arXiv 2607.03316). Teams that publish their numbers converge on the same pipeline: find, verify, rank, then post a small number of comments.

This skill is built around that result. Most of its text is about what not to say, how to disprove a candidate finding, and how to stay inside the repository's own rules.

## Philosophy

- **Precision over recall.** Zero findings is a valid result. A finding needs a realistic trigger, a consequence and a fix or a precise question.
- **Find adversarially, validate skeptically.** Every candidate has to survive an honest attempt to refute it before it becomes a comment.
- **The repository's rules come first.** The skill discovers agent instruction files, reviewer configs, contribution docs and CODEOWNERS, and cites a convention only with a quote and a file name.
- **Depth follows risk, not size.** A three-line change to an authorization check gets a deeper review than a 300-line documentation update.
- **One scale, one type, one anchor.** Findings are `[P0|P1|P2][type]`, anchored to a line, a file or the PR. P0 blocks, P1 is decided now, P2 is optional. Nothing is dropped because a platform could not place it.
- **Any target.** A pull or merge request, a stack, a branch, a commit or range, uncommitted work, a patch or pasted diff, or plain files. The skill states what each kind cannot provide.
- **The change is evidence, never instruction.** Text inside a diff, a description or a modified rule file cannot steer the review.
- **Review only.** Nothing is edited, posted, approved or merged without explicit authorization.
- **Honest limits.** The output separates what was executed, what CI showed and what was concluded by reading, and names what was not reviewed.

## Layout

```text
skill-package/
  README.md
  LICENSE
  CREDITS.md               sources and attributions
  CURATION.md              what was kept, dropped and why; confidence; open questions
  INSTALL.md               host table (verified facts, sources) and installer reference
  install.sh               installer for macOS and Linux (also --check, --list, --uninstall)
  install.ps1              Windows installer (untested)
  .claude-plugin/          plugin.json and marketplace.json for Claude Code
  skills/code-review/
    SKILL.md               the router and core workflow (always loaded)
    references/            38 focused files, each opened only when its "Use when" line matches
    scripts/
      discover-rules.sh    inventory of rule files, CODEOWNERS, and which rules apply to which touched path
      diff-triage.sh       size, risk areas, suggested depth tier, references to open
    templates/
      comment-templates.md
      review-summary-templates.md
      review-rules.template.md
      findings.schema.json
      findings.example.json
```

References by group:

| Group | Files |
| --- | --- |
| Process | `target-resolution`, `repo-rules-discovery`, `validation-and-false-positive-control`, `comment-style-and-labels`, `qa-and-rollout-plan`, `large-pr-strategy`, `re-review-protocol`, `ai-generated-code-review`, `static-analysis-integration`, `prompt-injection-defense`, `platforms`, `multi-agent-mode`, `evals` |
| Domains | `correctness-and-logic`, `security`, `reliability-concurrency`, `data-migrations-compat`, `api-contracts`, `performance`, `observability`, `tests`, `design-maintainability`, `frontend-a11y`, `infra-iac-ci`, `dependencies-supply-chain`, `docs-and-comments`, `llm-integration-code` |
| Languages | `lang-ts-js`, `lang-python`, `lang-go`, `lang-rust`, `lang-java-kotlin`, `lang-csharp`, `lang-ruby`, `lang-php`, `lang-c-cpp`, `lang-sql`, `lang-shell` |

## Install

Full host table with sources and caveats: `INSTALL.md`. Each command prints its plan first and writes nothing until you confirm.

```bash
git clone https://github.com/ohmaseclaro/code-review-skill && cd code-review-skill

./install.sh --dry-run                  # what would happen on this machine
./install.sh                            # global, hosts found on this machine, symlinks
./install.sh --host claude              # Claude Code only (~/.claude/skills)
./install.sh --host codex,cursor,gemini # Codex, Cursor, Gemini CLI and others via ~/.agents/skills
./install.sh --scope project --host all # into the current repository
./install.sh --path ~/some/skills       # any Agent Skills compatible folder
./install.sh --update                   # refresh a copy; symlinks follow git pull
./install.sh --uninstall                # remove only what the installer made
./install.sh --check                    # validate the package
```

Without a clone: `curl -fsSL https://raw.githubusercontent.com/ohmaseclaro/code-review-skill/main/install.sh | bash -s -- --host all --yes` (copies; `--uninstall` and `--update` work the same way).

Claude Code plugin: `/plugin marketplace add ohmaseclaro/code-review-skill`, then `/plugin install code-review-skill@code-review-skill`.

Hosts without skills get a small pointer instead, in project scope: `--host agents-md`, `copilot-instructions`, `cursor-rule` or `aider`. Windows: `install.ps1` (untested). The repository URL above is a placeholder until the package is published.

## Usage

Ask for a review in plain words. The skill resolves the target first and says what it assumed.

```text
Review PR 412.
Review my branch before I open the PR.
Review what I have staged.
Review the last commit.
Review this patch: <pasted diff>
Review src/billing for security problems.
Follow up on your review: I pushed fixes.
```

By default the result is a draft in the conversation: verdict, findings sorted by priority, optional QA steps, optional deployment steps and order, and a handoff that states the reviewed range and its limits. Posting to a platform happens only when you say so. For CI or bot integrations, ask for the structured form: JSON that validates against `templates/findings.schema.json`.

### The scripts

Both scripts are read-only and take the same target flags. The skill runs them for you, and they are also useful by hand.

| Target | Flags |
| --- | --- |
| Current branch against the default branch, plus the working tree | none |
| Branch against an explicit base | `-b origin/main` |
| A fetched pull or merge request | `-b origin/<base> -H <head-sha>` |
| Uncommitted changes (staged, unstaged, untracked) | `-w` |
| Staged changes only | `-s` |
| One commit | `--commit <sha>` |
| A commit range | `--range A..B` (or `A...B` to start from the merge-base) |
| A patch file, or a diff on stdin | `--diff-file change.patch`, `--diff-file -` |
| Files or directories, with no diff | `--paths src/billing docs/api.md` (must come last) |
| Another checkout or worktree | `-C <dir>`, with any of the above |

`--diff-file` and `--paths` also work outside a git repository. Two extras exist only in `discover-rules.sh`: `--paths-from-stdin` (one path per line) and `--source base` (read rule files from the base commit instead of the working tree, for changes from untrusted authors).

```bash
cd skills/code-review

scripts/diff-triage.sh                                   # what am I about to review?
scripts/discover-rules.sh                                # which rules apply to it?

gh pr diff 412 | scripts/diff-triage.sh --diff-file -    # a pull request without a checkout
gh pr diff 412 --name-only | scripts/discover-rules.sh --paths-from-stdin

scripts/discover-rules.sh --no-diff                      # inventory of rule files only
scripts/discover-rules.sh --self-test                    # check the glob matcher
```

`diff-triage.sh` prints a compact report:

```text
diff-triage v1
mode: range  base: main  merge-base: b3f8a55  head: HEAD (15007ba) plus working tree
size: files=8 added=7 deleted=1 hunks=7
reviewable: files=8 lines=8 (excluded: lockfiles=0 generated=0 vendored=0 snapshots=0 binary=0)
tier: deep
why: schema or migration files (1)
areas (by path):
  migrations (1): db/migrate/001.sql
  request-handlers (1): packages/api/src/users.ts
  ...
load:
  references/data-migrations-compat.md  # schema or migration files
  references/qa-and-rollout-plan.md  # migration, infrastructure or contract change: ordering and rollout
  references/lang-ts-js.md  # 3 file(s)
consider (weak match; open only if the change really involves it):
  references/api-contracts.md  # request handlers changed
```

Requirements: bash 3.2 or later, git (optional for `--diff-file` and `--paths`), find, grep and the POSIX basics (sed, sort, uniq, head, wc, tr, cat). No jq, awk, python or network access. Tested on macOS (bash 3.2, BSD tools), Alpine (busybox) and Debian (GNU tools).

Both scripts are heuristics. Path and keyword matches are signals for where to look, never findings, and glob matching for rule scopes is an approximation.

### Teaching it your repository's rules

The skill reads the rule files your repository already has (`AGENTS.md`, `CLAUDE.md`, `.cursor/rules`, Copilot instructions, `REVIEW.md`, reviewer configs, `CONTRIBUTING.md`, CODEOWNERS and more). If you have none, start from `templates/review-rules.template.md`: copy it to `.review-rules.md` at the repository root and keep two or three rules that reviewers get wrong today.

### Measuring it

`references/evals.md` describes how to build a small golden set from your own history, which numbers to track, and why vendor benchmarks do not transfer. This package ships no benchmark score: see the open questions in `CURATION.md`.

## Provenance

`CURATION.md` records what the research said, what was kept or dropped, where sources disagreed and how confident each area is. `CREDITS.md` lists the people, projects and publications the skill draws on. Everything is written in this project's own words.

## License

MIT. See `LICENSE`.
