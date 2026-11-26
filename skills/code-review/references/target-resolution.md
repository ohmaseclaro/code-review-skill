# Target resolution

Use when: the target is anything other than a checked-out branch or a PR you can query directly: a stack, a pasted or raw diff, files without a diff, a platform without a CLI, or a request that names no target.

Scripts below are `scripts/diff-triage.sh` and `scripts/discover-rules.sh`. Both take the same target flags.

## Detect the kind

| Signal in the request | Kind |
| --- | --- |
| URL with `/pull/N`, `/-/merge_requests/N`, `/pull-requests/N` or `/pullrequest/N`, or a bare `#N` | PR or MR |
| Several PR numbers, "the stack", or a PR whose base is not the default branch | Stack |
| A branch name, "my branch", "this branch" | Local branch |
| "My changes", "what I have so far", "before I commit", "staged" | Uncommitted or staged work |
| A SHA, a tag, `A..B`, "the last commit" | Commit or range |
| A `.patch` or `.diff` file, a fenced diff in the message, piped input | Raw diff |
| Paths that exist and no mention of a change | Files or directories |
| A directory that is another checkout or worktree | Same kinds, run with `-C <dir>` |
| None of the above | Unclear: see the default below |

## Resolve each kind

**PR or MR.** Get base branch, head SHA, state, draft flag, description, CI status and threads from the platform. Fetch the head without touching the user's checkout, then review at that revision in a temporary worktree (`git worktree add --detach <dir> <head-sha>`, removed afterwards).

| Platform | Metadata | Head ref to fetch |
| --- | --- | --- |
| GitHub | `gh pr view N --json baseRefName,headRefOid,isDraft,state,body,statusCheckRollup` | `pull/N/head` |
| GitLab | `glab mr view N --output json` (`diff_refs`, `target_branch`) | `merge-requests/N/head` |
| Bitbucket | REST `pullrequests/N` (`source.commit.hash`, `destination.branch.name`) | Source branch by name. Data Center also exposes `refs/pull-requests/N/from`. |
| Azure DevOps | `az repos pr show --id N` (`sourceRefName`, `targetRefName`, last merge source commit) | Source branch by name, or `refs/pull/N/merge` |

Then run the scripts with `-b origin/<base> -H <head-sha>`. Without a checkout:

```bash
gh pr diff N | scripts/diff-triage.sh --diff-file -
gh pr diff N --name-only | scripts/discover-rules.sh --paths-from-stdin
```

No CLI, no token or a private host you cannot reach: do not scrape. Ask for a checkout, a diff or access.

**Stack.** Find the order: a PR whose base is another PR's head branch sits above it (`gh pr list --head <base-branch>` finds the parent, `gh pr list --base <head-branch>` finds children). Review bottom first, each PR against its parent's head, with inherited commits as context only. Report a finding once, on the PR that introduces it. Add one stack-level note for ordering and for problems that only exist in the combination.

**Local branch.** Base is the default branch (`origin/HEAD`, else `main` or `master`), range is the merge-base to the tip. If the diff contains files the author plausibly never touched, the local base ref is stale or wrong: fetch, or pass the right base with `-b`. If the branch already has an open PR, prefer that PR's base.

**Uncommitted or staged work.** `-w` covers staged, unstaged and untracked files. `-s` covers the index only. The triage script counts untracked files by path without scanning them, so read them yourself.

**Commit or range.** `--commit <sha>` compares against the first parent. `--range A..B` compares the two endpoints literally. `--range A...B` starts from their merge-base, which is what you want when A is a branch that has moved on.

**Raw diff.** Pipe it or save it outside the repository and pass `--diff-file`. If a checkout of the same repository exists, `git apply --check <file>` tells you whether the diff matches it, which gives you surrounding code to read. Never apply a patch onto the user's working tree. A multi-commit patch series lists a file once per commit.

**Files or directories.** Whole-file review with `--paths`. Everything in the files is in scope. The triage script counts file lines instead of changed lines and scales its size thresholds to match. Read `git log -n 5 -- <path>` for recent intent when history exists. Above about 1,500 lines, review by risk (entry points, trust boundaries, state changes) and declare what you covered.

**Unclear target.** Use this ladder and state which rung you took:

1. On a feature branch: the branch against the default branch, plus the working tree.
2. On the default branch with uncommitted changes: those changes.
3. On the default branch, clean tree: the last commit, only if the user said something like "what I just did". Otherwise ask.

## When to ask instead of proceeding

Ask one question, with the options named, only when:

- There is no repository and no diff.
- Two plausible targets would produce materially different reviews, for example a feature branch with a large unrelated dirty tree, or a number that matches both a PR and an issue.
- No base resolves and none was given.
- The request names a target you cannot reach.

Otherwise proceed and put the assumption in the first line of the handoff.

## What each kind provides

| Kind | Surrounding code | Repository rules | Intent | CI and threads | Related changes | Posting |
| --- | --- | --- | --- | --- | --- | --- |
| PR or MR with checkout | Yes | Yes, from the base | Description, ticket | Yes | Yes | With authorization |
| PR or MR, diff only | No | Only if some checkout exists | Description | Yes | Yes | With authorization |
| Local branch, commit, range | Yes | Yes | Commit messages, the user | No, unless a PR exists | Local branches only | No |
| Uncommitted or staged | Yes | Yes | The user | No | No | No |
| Raw diff inside a matching checkout | Yes | Yes | Whatever came with it | No | No | No |
| Raw diff alone | No | No | Whatever came with it | No | No | No |
| Files or directories | Yes | Yes | The user, recent history | No | No | No |

## How the output degrades

| Element | Fallback |
| --- | --- |
| Priority and type | Always available. |
| Line anchor | Off-platform: `path:line` text, in new-file numbering. For a raw diff, compute it from the hunk header: in `@@ -a,b +c,d @@` the first line of the hunk is new line `c`, and context and added lines advance the count. A removed line is anchored to its old number: `path:OLD (removed)`. |
| PR-level anchor | For targets that are not PRs, write `Location: change-level: <what>`. Same anchor kind. |
| Evidence | Without surrounding code the best evidence level is `inferred`. A P0 defect that depends on code you cannot see becomes a P0 question naming that code. |
| Scope filter | Whole-file review has no "introduced by this change" filter. Keep the priority criteria and the budget, and do not use the "pre-existing" bucket. |
| Verdict | A recommendation off-platform. For whole-file review keep the four verdict values and word them as an assessment: "no P0 or P1 found", "P1 items to decide", "P0 defects", "open P0 questions". |
| QA steps | Still possible from the code. Say which environments and data you could not know about. |
| Deployment steps and ordering | Without a platform, check local branches only, or write "related changes not checked". |
| Posting | Only for a PR or MR, with authorization. Everything else is a draft. |
| Follow-up round | Needs the earlier findings: the platform threads, or the previous output or JSON supplied by the user. |

## Say it in the handoff

One line: the target as resolved, the exact range (base and head SHAs when they exist), and what was unavailable. Example: `Target: current branch vs origin/main (a1b2c3d..e4f5a6b) plus uncommitted changes. Not available: CI results, review threads.`
