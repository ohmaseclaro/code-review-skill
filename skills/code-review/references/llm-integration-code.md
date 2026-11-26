# LLM integration code

Use when: the change calls a model API, edits prompts, defines agent tools, handles model output, builds retrieval or embeddings, or adds evals.

Core fact: a model call is a nondeterministic network dependency whose output is untrusted input. Review it under both sets of rules: reliability of an external call, and security of user-controlled data.

## The questions

- What can reach the prompt, and who controls it: user text, retrieved documents, tool results, file contents, web pages?
- What can the output cause: text shown, code or SQL executed, a tool called, money spent, a message sent?
- What happens when the call fails, times out, is refused, is cut off or returns a different shape?
- What evidence shows the change made results better and not worse?

## Output handling

- Output is parsed and validated against a schema at runtime before use. "The prompt says to return JSON" is not validation. Structured-output features reduce errors and do not remove the need to validate.
- Output that reaches a sink (HTML, SQL, shell, file paths, URLs, templates, deserializers) is handled like any untrusted input.
- The stop or finish reason is checked before parsing. A response cut off at the token limit is not a complete answer.
- Refusals and empty responses are a distinct outcome, not a success.
- Identifiers, URLs, paths and citations produced by a model are checked against the source of truth before anything acts on them.
- Decisions about money, permissions or irreversible actions are not taken from model output alone.

## Prompt construction

- Untrusted content is kept apart from instructions: separate roles or clear delimiters, never concatenated into the system prompt.
- No secrets, other tenants' data or unneeded personal data in prompts. Prompts go to a third party and usually into logs.
- Template variables that render as an empty string, `undefined` or `None` without failing.
- Unbounded inputs: count tokens and define what is truncated or summarized when the context is full.
- Few-shot examples containing real customer data.

## Agents and tools

- Each tool validates its own input. The model is the caller, and it is not a trusted one.
- Authorization uses the end user's identity. Tenant and user scope come from the session, never from model-supplied arguments.
- Tools with side effects (send, pay, delete, deploy) need confirmation, idempotency keys and limits.
- Loops are bounded: steps, tokens, cost and wall-clock time. A retry after a tool error must not repeat a side effect.
- Tool results can carry instructions. One session should not combine untrusted content, sensitive data and the ability to act externally: see `prompt-injection-defense.md`.
- Tool descriptions and schemas match the implementation. Errors returned to the model are informative and contain no secrets.
- Memory persisted across sessions: poisoning, leakage between users, and compatibility of stored state after a deploy.
- Newly added tool servers or plugins: what can they read and do, and are they pinned?

## Reliability and cost

- Timeouts. Retries with backoff for rate-limit and overload errors only. A fallback or a clear failure for the user.
- Streaming: partial output, cancellation, and stopping generation when the client disconnects.
- Per-user or per-tenant quotas, so that one caller cannot exhaust the budget.
- Calls inside loops or per row. An output token limit. Conversation context that grows without bound.
- Response and prompt caches keyed by everything that changes the answer, including model and prompt version.
- Model identifiers in one place. Parameters valid for the configured model. Do not claim from memory that a model name or parameter is invalid: check the provider's documentation for the pinned SDK version.

## Retrieval and embeddings

- Access control is applied at retrieval time. The tenant filter is part of the vector query, not a post-filter in application code.
- Changing the embedding model requires re-embedding everything. Mixed vectors in one index fail silently.
- Chunking or metadata changes come with a reindex plan. Deleted sources are removed from the index.
- Citations come from the retrieved set.

## Evals and tests

- A change to a prompt, model, retrieval parameter or tool is a behavior change. It needs before-and-after results on a fixed set that includes failure cases.
- Eval items leaking into prompts or few-shot examples. Thresholds lowered to pass. A judge prompt with the generator's blind spots.
- Unit tests fake the model with realistic shapes: malformed output, a refusal, a truncated response, a tool error.
- Tests that assert exact strings from a live model, or live-model tests on the merge-gating path.

## Privacy and logging

- Prompts and completions logged with personal data or secrets: redaction and retention.
- Data sent to a new provider or region: ask whether that is permitted for this class of data.

## Verify by

- Tracing one untrusted input from entry to prompt, and one output from response to sink.
- Feeding a malformed and a truncated response through the parser.
- Running the evals, or reading their output if the author ran them.

## Do not flag

- Prompt wording taste with no eval result or concrete failure.
- Model choice preferences. Nondeterminism as such. "Add guardrails" with no path named.

## Priority guidance

P0: output reaching a dangerous sink or an action with no validation or authorization, retrieval that crosses tenant or permission boundaries, secrets or regulated data sent to a provider or logged, an agent loop with side effects and no bound or confirmation, a path from untrusted content to privileged tools. P1: no handling of truncated, refused or malformed output on a user path, a prompt or model change with no eval evidence, unbounded cost per request, an embedding model switch with no reindex plan. P2: prompt hygiene and caching opportunities.
