# Large change strategy

Use when: the change has more than about 400 reviewable lines or 20 files, mixes unrelated concerns, or is too big to hold in context at once.

Why: review quality falls with size for humans and models alike. A vendor study on Cisco data found defect detection dropping past 200 to 400 lines per sitting, a Microsoft study found the share of useful comments falling as changes grow and for files later in the list, and a 2025 benchmark of automated reviewers saw recall fall as files and lines increased.

## 1. Decide before reading everything

- **Is the approach right?** Read the description and the two or three central files first. If the design is wrong, say that and stop.
- **Is it one change?** A refactor mixed with a behavior change, unrelated fixes, formatting sweeps or dependency churn hide the real change. Recommend a split and name the seams (three sub-changes at most). By itself this is a PR-level P1. It becomes a Hold when the mix prevents you from verifying a risky part.
- **Is it mostly mechanical?** Then verify the mechanism, not every line (section 2).

Common split seams: pure moves and renames, formatting only, dependency bumps, schema expansion, backend contract, consumers, cleanup and removal, test fixtures.

## 2. Shrink what must be read

- Exclude lockfiles, generated, vendored, minified and snapshot files. The triage script lists what it excluded.
- Never skip: migrations, dependency manifests, CI and infrastructure files, rule files, deleted files that contained guards or tests.
- Mechanical changes (codemods, renames, formatter runs): confirm the command or tool named in the description, re-run it when cheap, sample files from different areas, and grep for stragglers and for hand edits hidden among the mechanical ones.
- Moves: confirm moved code is unchanged, then review only what was modified.

```bash
git diff -M -C --stat <merge-base>                # renames and copies
git diff --color-moved=dimmed-zebra <merge-base>  # moved blocks versus real edits
git diff -w --word-diff <merge-base> -- <path>    # ignore whitespace, show token changes
git diff <merge-base> -- <path>                   # one file at a time
```

## 3. Build a map

Group files by responsibility, not directory: contracts and schema, domain logic, wiring and config, UI, tests. Aim for three to five clusters. Inside a cluster, start with the file a reader must understand first. For each cluster, write one private sentence: what it does and what could go wrong. For each behavior change, trace one path end to end from entry point to persistence.

## 4. Spend attention by risk

| Depth | What |
| --- | --- |
| Deep | Risk areas from triage, the largest logic churn, new files with logic, files with a history of fixes, deleted guards and tests |
| Standard | Wiring, configuration, adapters |
| Skim | Mechanical edits, docs, test data |

- Review the riskiest cluster first, not the first file alphabetically.
- Attention decays: give the last files you read a second look, or hand them to a fresh subagent.
- Finish with a cross-cluster pass: contract changed in one place and every consumer updated, defaults that agree across files, flags used consistently, migration and code ordered safely.

## 5. Context management

- Past roughly 2,000 changed lines, do not load the whole diff. Work from the triage output, `--stat`, and per-cluster diffs. Keep short private notes per cluster.
- Quality degrades as the context fills. One published reviewer design warns its coordinator past half of the window. Prefer one subagent per cluster with a shared brief: see `multi-agent-mode.md`.
- Hosting platforms truncate or refuse very large diffs. Use a local checkout or per-file patches: see `platforms.md`.

## 6. Coverage accounting

Never imply complete coverage. In the handoff, state:

- Reviewed in depth: which clusters or paths.
- Skimmed: which, and why that was enough.
- Not reviewed: which, and why.

If a risky part could not be verified, the verdict is Hold, not Approve. Recommend what would close the gap: a local run of a named scenario, a walkthrough with the author for an architectural change, a staged rollout.

## 7. Comments on a large change

- Lead with design-level findings. One comment per root cause, with the other locations listed.
- Keep the P1 and P2 budget at eight. Size is not a license for more nits.
- If you recommend a split, say which finding would be easier to verify afterwards.

## Size reference points

Common guidance treats about 100 changed lines as comfortable and 1,000 as usually too large, with exceptions for automated refactors and pure deletions. These are signals for depth and for suggesting a split, not automatic P0 findings.
