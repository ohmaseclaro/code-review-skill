# Review summary templates

Layouts for the whole review output. Delete every section and line that has nothing specific to say. Rules: `../SKILL.md`. Machine-readable form: `findings.schema.json`.

## Draft output

````markdown
## Verdict: <Approve | Approve with comments | Request changes | Hold>

<One to three sentences: what was validated and how, or why changes are requested.>

## Findings

### P0: must fix before merge

**[P0][<type>] <Title>**
Location: `<path>:<start>-<end>`

<Body.>

### P1: fix here or track

**[P1][<type>] <Title>**
Location: `<path> (file)`

<Body.>

### P2: optional

**[P2][<type>] <Title>**
Location: `PR-level: <what is affected>`

<Body.>

## Recommended QA steps

1. <Scenario> [manual | automated] (covers: <risk or finding title>)
   - Setup: <data, account, flag state, environment>
   - Do: <action>
   - Expect: <observable result>
   - Watch: <signal that would show a failure>

## Recommended deployment steps and order

Before deploy:
- <Config key, secret, flag or infrastructure that must exist> (confirmed | inferred)

Order:
1. <Step> because <reason>. Verify: <check before the next step>. (confirmed | inferred)
2. <Step> because <reason>.

Rollback: <how to undo each step>. Point of no return: <step, and why>.

Watch after deploy: <specific signal>, for <how long>.

Follow-ups: <flag removal, contract step, cleanup>, tracked in <where>.

Related changes (searched: <platform | local branches only | not checked>):

| Change | Relation | Basis | Order |
| --- | --- | --- | --- |
| <org/repo#n> | <what it does for or against this change> | <stated, same ticket, same files, shared contract, inferred> | <must land first, after, together, either> |

## Handoff

- **Target:** <target as resolved>, <base sha>..<head sha><, plus uncommitted changes>. Assumption: <if the target was not named>.
- **Intent:** <claimed purpose>. <Matches the diff | differs in: ...>.
- **Reviewed:** <files or areas read in full>. **Not reviewed:** <what, and why>.
- **Validation:** executed <commands and results>. CI: <state at the head sha>. By reading: <what was traced>.
- **Not available:** <CI results, threads, related changes, surrounding code>.
- **Operational readiness:** <rollout, detection and recovery in one or two lines>.
- **Evolution:** <the one or two concerns that will matter in later changes>.
- **Pre-existing:** <at most two notable problems the change did not introduce>.
- **Posting:** <nothing posted | posted n comments as <account>; demoted: <list>; failed: <list>>.
````

## Review body when posting

The body is short. Findings live in their own comments, except PR-level findings on platforms where the body is the only place for them.

**Approve**

```markdown
Approved. Checked <what>, by <running the suite | tracing the callers | reading>. <CI state>.
```

**Approve with comments**

```markdown
Approved with comments. Checked <what>, by <how>.
P1 items: fix here or track.
```

**Request changes**

```markdown
Requesting changes: see P0 findings.
<At most one sentence of framing.>
```

**Hold**

```markdown
Holding approval pending clarification: see P0 questions.
```

**With PR-level findings** (append to any of the above)

```markdown
PR-level findings:

**[P0][<type>] <Title>**
<Body.>

**[P1][<type>] <Title>**
<Body.>
```

## Follow-up round

```markdown
## Verdict: <verdict> (round <n>, reviewed <old sha>..<new sha>)

<One or two sentences on what changed since the last round.>

### Earlier findings

| Finding | State | Evidence |
| --- | --- | --- |
| [P0][<type>] <title> | Resolved | <what the new code does, path:line> |
| [P1][<type>] <title> | Still open | <what remains> |
| [P1][<type>] <title> | Accepted risk | <who accepted it and why> |
| [P2][<type>] <title> | Withdrawn | <what showed it was wrong> |

### New findings in this round

<Only problems introduced or exposed by the new commits. Same format as a first review.>

### Handoff

<Same fields as a first review, limited to what changed.>
```

## Whole-file review

Same layout as the draft output, with these differences:

- Heading: `## Assessment: <no P0 or P1 found | P1 items to decide | P0 defects | open P0 questions>`.
- No deployment section unless the files themselves define a rollout.
- No pre-existing bucket: everything in the files is in scope.
- In the handoff, state what you sampled and what you skipped.

## No findings

```markdown
## Verdict: Approve

No findings. Checked: <what and how>. Not checked: <what and why>.
```
