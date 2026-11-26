# Comment templates

Fill-in forms for single findings and replies. Replace everything in angle brackets and delete lines that do not apply. Rules for priority, type, anchor and tone: `../SKILL.md` and `../references/comment-style-and-labels.md`.

The `Location:` line belongs to drafts. When posting, the platform carries the anchor, so drop that line unless the anchor was demoted.

## Defect on changed lines

```text
[<P0|P1>][<bug|security|reliability|compatibility|performance|observability>] <Imperative title>
Location: <path>:<start>-<end>

When <realistic trigger>, <what the code does> causes <consequence>.
<Why this priority>. <Smallest fix, or the outcome a fix must achieve>.
```

## Defect with a ready replacement

Only when the replacement is complete, small and covers exactly the anchored lines.

````text
[<P0|P1|P2>][<type>] <Imperative title>
Location: <path>:<start>-<end>

When <trigger>, <behavior> causes <consequence>. <Why this priority>. Not executed.

```suggestion
<replacement for the whole anchored range>
```
````

## Removed protection

```text
[<P0|P1>][<security|reliability|tests>] Restore <the guard, check or assertion> or state why it is no longer needed
Location: <path>:<old line> (removed)

This change deletes <what was removed>. It protected against <failure>. Nothing in the diff replaces it: <where you looked>.
<What must be true before it can go>.
```

## Convention

```text
[<P0|P1|P2>][convention] <Imperative title>
Location: <path>:<start>-<end>

<Rule file>, "<section>": "<exact quote>"
<How these lines differ from the rule>. <The compliant form>.
```

## Tests

```text
[<P0|P1|P2>][tests] Cover <the behavior> at the <unit|integration|end-to-end> level
Location: <path>:<start>-<end>

<The behavior> is not protected: <which existing test comes closest and why it does not fail>.
A test that <setup and action> and asserts <observable result> would fail if <the regression>.
```

## Question

```text
[<P0|P1|P2>][question] <The decision that is open, as a question>
Location: <path>:<start>-<end>

<The missing fact>. I could not determine it from <what you checked>.
If <answer A>, <consequence and what changes>. If <answer B>, this is fine as written.
```

## File-level

```text
[<P0|P1|P2>][<type>] <Imperative title>
Location: <path> (file)

<What is wrong with the file as a whole, or with which unchanged lines>. <Consequence>. <Fix>.
```

## PR-level

```text
[<P0|P1|P2>][<type>] <Imperative title>
Location: PR-level: <what is affected>

<What is missing or cross-cutting, and where you looked for it>. <Consequence>.
<What the change must add, or the decision the author must record>.
```

For a target that is not a PR, write `Location: change-level: <what is affected>`.

## Repeated pattern

```text
[<P0|P1|P2>][<type>] <Imperative title>
Location: <path>:<start>-<end>

<The problem, explained once on this first instance>.
Also at: <path>:<line>, <path>:<line>, <path>:<line>.
```

## Demoted anchor

```text
[<priority>][<type>] <Imperative title>

Location: <original path>:<start>-<end> (not anchored: <reason, for example outside the diff>)
<Body as usual>.
```

## Reply: fix verified

```text
Verified at <short sha>: <what the new code does>. Resolving.
```

## Reply: still open

```text
Still open at <short sha>: <what the code still does, with path and line>.
<What remains to be done>.
```

## Reply: the author disagrees

```text
<Restate the author's point in one sentence>.
<The evidence that decides it: a trace, a test result, a quoted rule>.
<Outcome: withdrawn | lowered to <priority> because <reason> | still <priority> because <reason>>.
```

## Reply: withdrawn

```text
Withdrawn: <what I missed, with path and line>. No change needed.
```

## Clean result

```text
No findings. Checked: <what you validated and how>. Not checked: <what you could not>.
```
