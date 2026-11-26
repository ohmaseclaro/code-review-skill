# Platform mechanics

Use when: you fetch a change from a hosting platform, post comments, resolve threads, set a status or check, or need to know why a comment was rejected.

Rule zero: post only when the user authorized posting, post once, and report exactly what landed and what failed. API details drift: where a line says "verify", check the platform docs for the version in use.

## Shared model

Keep findings in one internal shape and adapt per platform: `{priority, type, anchor: {kind, path, start_line, end_line, side}, title, body, suggestion?}`, the same shape as `../templates/findings.schema.json`. Design for the weakest platform: plain Markdown comments, no one-click suggestions, no check UI.

| Concept | GitHub | GitLab | Bitbucket Cloud | Azure DevOps |
| --- | --- | --- | --- | --- |
| Inline comment | Review comment with `line` and `side` | Discussion with `position` | Comment with `inline` | Thread with `threadContext` |
| Batch as one review | Yes, one review object | Draft notes, then bulk publish | No | No |
| Suggestion block | Yes | Yes, with line offsets | Verify | Verify |
| Formal verdict | Approve, request changes, comment | Approve, unapprove (request changes: verify version) | Approve, request changes | Vote from 10 to -10 |
| Thread state | Resolved or unresolved | Resolved or unresolved | Resolved (verify) | Active, fixed, won't fix, by design, closed |
| Machine status | Check run or commit status | Commit status, external status check | Build status, code insights report | PR status |

## Anchor kinds per platform

| Anchor | GitHub | GitLab | Bitbucket Cloud | Azure DevOps | Gerrit |
| --- | --- | --- | --- | --- | --- |
| line | Review comment with `path`, `line`, `side`, inside one hunk | Discussion with a `position` of type `text` | Comment with `inline: {path, to}` | Thread with `threadContext` line positions | `comments` entry with `line` or `range` |
| file | Single review comment with `subject_type: "file"`. Not accepted inside a batched review (verify), so post it separately. | Discussion with `position_type: "file"` (GitLab 16.4 or later: verify) | `inline: {path}` with no line (verify) | Thread with `threadContext.filePath` only | `comments` entry with no `line` |
| pr | A list in the review body | Discussion with no position, which stays resolvable | Top-level pull request comment | Thread with no `threadContext` | The review `message`, or a comment on `/PATCHSET_LEVEL` |

Demotion ladder when an anchor cannot be placed: line, then file, then PR-level. A demoted finding keeps its priority and type, and its body starts with the original location and the reason, for example `Location: src/worker.ts:84-88 (not anchored: outside the diff)`. Nothing is dropped, and every demotion is reported to the user.

On GitHub, PR-level findings in the review body are not resolvable threads. Give each its own labeled paragraph so the author can answer one at a time.

## Verdict mapping

Submit a verdict only when the user authorized that exact action. Otherwise post as a plain comment and state the verdict in the body.

| Verdict | GitHub event | GitLab | Bitbucket | Azure DevOps vote |
| --- | --- | --- | --- | --- |
| Approve | `APPROVE` | Approve | Approve | 10 |
| Approve with comments | `APPROVE` | Approve | Approve | 5 |
| Request changes | `REQUEST_CHANGES` | No approval. Request changes where the version has it (verify). | Request changes | -5 |
| Hold | `COMMENT` | No approval | No action | 0 |

## GitHub

### Read

```bash
gh pr view <n> --json number,title,body,isDraft,author,baseRefName,headRefName,baseRefOid,headRefOid,reviewDecision,statusCheckRollup
gh pr diff <n>                       # refused for very large changes (verify: around 300 files)
gh api "repos/{owner}/{repo}/pulls/<n>/files" --paginate   # per-file patches; large or binary files have no patch
gh pr checkout <n>                   # or: git fetch origin pull/<n>/head:pr-<n>
gh api -H "Accept: application/vnd.github.raw+json" "repos/{owner}/{repo}/contents/<path>?ref=<head-sha>"
gh api "repos/{owner}/{repo}/pulls/<n>/comments" --paginate   # existing inline comments
gh pr checks <n>
```

- Pin `headRefOid` for the whole review. Read files at that SHA, not from whatever is checked out locally. For a file deleted by the change, read it at the base SHA.
- For renamed files, look at the old path too: the important history may live there.
- Thread state (resolved, outdated) needs GraphQL: `pullRequest.reviewThreads { nodes { id isResolved isOutdated path line comments(first: 20) { nodes { author { login } body } } } }`.
- A draft pull request gets feedback on direction only: no approval and no request for changes.

### Anchor

- Use `path`, `line` and `side`. `RIGHT` is the new file (added and context lines), `LEFT` is the old file (deleted lines). Multi-line comments add `start_line` and `start_side`. The whole range must sit inside one hunk of the diff at `commit_id`.
- The legacy `position` parameter is an offset inside the file's patch. Avoid it.
- A comment on a line outside the diff is rejected with HTTP 422. One rejected comment fails the entire review request.
- Build a map of commentable lines per file from the hunk headers before posting. Snap a finding to the nearest changed line in the same hunk, or demote it one level. Never post on an unrelated line.
- Models are unreliable at line arithmetic. Locate by quoting the code and matching the text, then derive the line number.

### Post

```bash
gh api "repos/{owner}/{repo}/pulls/<n>/reviews" --method POST --input review.json
```

```json
{
  "commit_id": "<head sha>",
  "event": "COMMENT",
  "body": "Requesting changes: see P0 findings.",
  "comments": [
    { "path": "src/worker.ts", "start_line": 84, "start_side": "RIGHT", "line": 88, "side": "RIGHT",
      "body": "[P0][reliability] Make retry handling idempotent\n\n..." }
  ]
}
```

- One review request means one notification. Do not post comments one by one.
- `event`: use `COMMENT` unless the user explicitly asked you to submit an approval or a request for changes. Omitting `event` leaves a pending review, and only one pending review can exist per user per pull request.
- Fallback ladder on 422: remove suggestion blocks and retry, then post the valid comments and demote the rest. Report every finding that could not be placed.
- File-level comment: `POST repos/{owner}/{repo}/pulls/<n>/comments` with `body`, `commit_id`, `path` and `subject_type: "file"`.
- `gh pr review --comment --body` posts only a body. `gh pr comment` posts to the conversation, not as a review.
- You post as the authenticated identity. Tell the user which account or app that is. A token from a fork is often read-only: then deliver a draft.

### Suggestions

````text
```suggestion
replacement for the whole commented range
```
````

The block replaces every line in the commented range, so the range must equal the lines being replaced and the indentation must match. It cannot be applied to deleted lines or once the thread is outdated.

### Threads, checks, limits

- Resolve with GraphQL `resolveReviewThread`. Only your own threads, only after verifying the fix.
- A check run is the right carrier for a machine-readable verdict: it is tied to a SHA, supports `neutral` for advisory results, and takes annotations (at most 50 per request). Creating one needs an app or Actions token with `checks: write`. Advisory by default: a missing, skipped or failed reviewer run must never block a merge.
- Limits to respect: about 80 content-creating requests per minute and 500 per hour, a 65,536-character comment body, at least one second between writes, and `retry-after` on throttling.
- Permalinks need the full 40-character SHA: `https://github.com/<owner>/<repo>/blob/<sha>/<path>#L10-L15`.
- For a summary that updates in place, put a hidden marker in the comment (`<!-- code-review:summary -->`), find it on the next run and edit it. The last reviewed SHA can live there too.
- Last SHA you reviewed: `gh api "repos/{owner}/{repo}/pulls/<n>/reviews" --jq '[.[] | select(.user.login == "<login>")] | last | .commit_id'`.

## GitLab

```bash
glab mr view <iid> --comments
glab mr diff <iid>
glab api "projects/:id/merge_requests/<iid>/versions"      # base_commit_sha, start_commit_sha, head_commit_sha
glab api "projects/:id/merge_requests/<iid>/discussions" --paginate
```

- Inline comment: `POST projects/:id/merge_requests/:iid/discussions` with `body` and a `position` of type `text` carrying `base_sha`, `start_sha`, `head_sha`, `new_path`, `old_path`, and `new_line` for an added line, `old_line` for a removed line, both for an unchanged line.
- To batch: create draft notes (`.../draft_notes`) and publish them together (`.../draft_notes/bulk_publish`). Verify availability on self-managed versions.
- Suggestions use offsets: ```` ```suggestion:-0+0 ```` replaces the commented line, `-2+1` extends two lines above and one below. Documented limit: 100 lines above and 100 below.
- Resolve: `PUT .../discussions/:id?resolved=true`. Approve and unapprove: `POST .../approve`, `POST .../unapprove`.
- A plain summary: `glab mr note <iid> -m "<text>"`.
- GitLab's own review assistant reads `.gitlab/duo/mr-review-instructions.yaml`. Treat it as a rule source.

## Bitbucket

- Cloud inline comment: `POST /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/comments` with `content.raw` and `inline: { "path": "...", "to": <new line> }` (`from` for a removed line).
- Data Center: `.../pull-requests/{id}/comments` with an `anchor` of `path`, `line`, `lineType` (`ADDED`, `REMOVED`, `CONTEXT`) and `fileType` (`TO`, `FROM`).
- Verdicts: approve and request-changes endpoints exist on Cloud. For bots, build statuses and code insights reports with annotations are the quieter channel.
- Assume no one-click suggestion. Put the replacement in a fenced block inside the comment.

## Azure DevOps

- Thread: `POST .../pullRequests/{id}/threads` with `comments: [{ "content": "...", "commentType": 1 }]`, a `status`, and `threadContext: { "filePath": "/src/x.ts", "rightFileStart": { "line": 84, "offset": 1 }, "rightFileEnd": { "line": 88, "offset": 1 } }`. Use the `leftFile` fields for deleted lines.
- Thread statuses (`active`, `fixed`, `wontFix`, `byDesign`, `closed`) map directly onto the re-review ledger.
- Votes: 10 approved, 5 approved with suggestions, 0 no vote, -5 waiting for author, -10 rejected. Cast one only when authorized.

## Gerrit

One request carries comments and labels: `POST /changes/{id}/revisions/{rev}/review` with a `comments` map of path to entries (`line` or `range`, `message`, `unresolved`) and optional `labels` such as `Code-Review`. Mark P0 findings `unresolved: true`. Never set a vote unless authorized.

## No platform

For a local branch, a working tree, a raw diff or plain files, nothing is posted. Print the draft output with `path:line` locations. Details: `target-resolution.md`.
