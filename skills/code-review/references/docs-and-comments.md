# Documentation and comments

Use when: documentation, READMEs, API descriptions, changelogs, runbooks, decision records, code comments or docstrings change, or a behavior change leaves existing text wrong.

Core fact: a changed document is not a correct document. Documentation is a set of claims. Check each claim against the code at the head revision.

## The questions

- Is every statement true of the code as it is after this change?
- Who follows this text, and what breaks for them if it is wrong?
- Which existing document, comment or example did this change make false?

## Accuracy

- Commands, flags, paths, environment variable names, defaults, version numbers and endpoints: verify each against code or config. Run commands when that is safe.
- Code samples: imports exist, the sample would compile or run, the shown output matches.
- Links and anchors resolve, including relative paths to renamed files.
- Steps are complete and in a working order: no missing prerequisite, no step that depends on a later one.

## Drift caused by the change

Search for the old name, flag, default or endpoint in: README, docs, examples, help text, API descriptions, sample config files, error messages that tell users what to do, upgrade notes and comments.

- A public behavior change with no changelog entry or upgrade note, where the repository keeps one.
- A deprecation stated without its replacement and timeline.
- The change description itself: it must describe the final state of the change, not an earlier draft.

## Comments and docstrings

- **A comment that contradicts the code beneath it.** Decide which one is wrong. Sometimes the comment states the intent and the code is the bug.
- Docstring parameters, return values and raised errors that no longer match the signature.
- Comments that restate the code, narrate the edit ("added to fix the bug") or record history that belongs in the commit message.
- TODO and FIXME with no owner or condition. Commented-out code.
- A non-obvious constraint with no comment: a `[suggestion]` to record why the obvious approach was not taken.

## Generated and specification documents

- Generated documents edited by hand will be overwritten. The source must change instead.
- API descriptions that disagree with handler behavior: see `api-contracts.md`.

## Runbooks and operational documents

- Steps executable in order by someone under pressure. Destructive steps marked. Rollback included. Contacts and links current.
- A wrong runbook is worse than none: treat errors here as defects, not polish.

## Decision records

- Context, decision and consequences are present, and the status is set.
- The code in this change actually follows the decision it cites. A superseded record is marked.

## Security and privacy in text

- Real secrets, tokens, internal hostnames or customer data in examples, screenshots and pasted logs. Use placeholders.
- Instructions that tell readers to disable a protection or pipe a download into a privileged shell.

Instruction files for AI agents are rule files: review edits to them as rule changes, and open `prompt-injection-defense.md` if they contain hidden or reviewer-directed text.

## Verify by

- Searching the repository for the old identifiers.
- Running the documented command or example in a sandbox.
- The documentation build or link checker, when the repository has one.
- Checking that tables and code fences close when rendered.

## Do not flag

- Wording, tone and punctuation taste.
- Typos one by one: batch them in a single `[nit]`.
- Missing documentation for internal code, unless a repository rule requires it.
- "Add more documentation" without a named reader and a named failure.

## Priority guidance

P0: text that causes harm when followed (a destructive or wrong command in a runbook or install guide), a secret committed in an example, a published API description that misstates the contract. P1: documentation made false by this change, a missing upgrade note for a breaking change, a comment that now contradicts the code. P2: clarity, batched typos, comment hygiene.
