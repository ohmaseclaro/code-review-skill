# API and contract changes

Use when: the change touches HTTP, RPC or GraphQL interfaces, events, webhooks, a library's exported API, CLI flags, config keys, environment variables or any format another party consumes.

A contract is any shape or behavior that another deployable, team, customer or stored artifact depends on. That includes error codes and bodies, status codes, pagination and ordering, defaults, idempotency behavior, event meaning, analytics events, tables other services read, log lines that tools parse, and metric names that alerts use.

## The questions

- Who consumes this, and how do I know? Name them.
- Is the change compatible in the direction the data flows?
- What happens during the rollout window, and to messages already in flight?
- Did the meaning change even though the type did not?

## Direction decides compatibility

| Change | Inputs (the consumer sends) | Outputs and events (the consumer receives) |
| --- | --- | --- |
| Add an optional field | Safe | Safe, unless consumers reject unknown fields |
| Add a required field | Breaking | Safe |
| Remove a field | Safe if unknown fields are ignored, breaking if rejected | Breaking |
| Rename a field, type, endpoint or topic | Breaking | Breaking |
| Narrow a type or validation | Breaking | Safe |
| Widen a type, add an enum value, make nullable | Safe | Breaking for exhaustive or strict consumers |
| Change a default | Changes behavior for callers who omit it | Changes behavior |
| Change meaning or unit | Silently breaking | Silently breaking |

State the direction in the finding. Most contract mistakes come from applying the input rule to an output or the reverse.

## Checks

**Consumers**
- Search the repository and the other packages of a monorepo. Check schema files, generated clients, docs examples, alert rules and dashboards.
- Outside the repository: other services, mobile apps (old versions live for months), third parties, webhook receivers, analytics pipelines. If you cannot see them, ask who consumes it.
- "No consumers" is a claim that needs evidence.

**A compatibility path for a breaking change**
- Add first, migrate consumers, remove in a later release.
- Versioning (path, header, package major), a deprecation notice with a date, dual-published events.
- A changelog entry and a version bump that matches the change.

**Rollout window**
- Old and new versions run together, in both directions.
- Queued, retried and dead-lettered messages replay against the new schema.
- Cached responses and clients retrying old requests.
- Compatibility must hold at every step, not depend on a deploy-order runbook.

**HTTP specifics**
- Status codes, error body shape, pagination defaults and limits, ordering.
- Null versus absent, an empty list versus not found, date and number formats, enum casing.
- Required scopes or permissions, content types, idempotency of retries.

**Events and messages**
- An event states facts about what happened. It should not carry instructions for one consumer or flags that exist only for one consumer's convenience.
- A consumer special-casing a producer's quirk usually means the producer should be fixed.
- Ordering keys, schema versions, payload size, personal data in payloads.

**Schema languages**
- Protobuf, Thrift, Avro: never reuse or renumber a field. Reserve removed numbers and names. Type changes are rarely wire-compatible. New fields need defaults. Enum zero value and unknown values.
- GraphQL: removing or renaming fields, arguments or enum values. A new required argument. Nullable to non-null and back both have consumers who break. Deprecate first.
- OpenAPI and JSON Schema: `required` lists, nullability and enums that match what the handler and validator really do.

**Library and SDK surface**
- Removed or renamed exports, changed signatures or types, changed defaults, new exceptions.
- Runtime, peer dependency and module-format requirements.
- Accidental new exports: everything public becomes something to support.

**CLI, config and environment**
- Renamed or removed flags and keys with no fallback. Changed defaults. Exit codes.
- Output that scripts parse.
- A newly required environment variable: deployments without it must fail with a clear message, and the rollout must be coordinated.

**Spec and code drift**
- The spec updated to match the handler, and the handler matching the spec. An edited spec is not thereby a correct spec.
- Update or patch schemas that inherit the create schema's required fields while the code treats every field as optional.
- Generated clients regenerated, not edited by hand.

**Storage leaking into the contract**
- An endpoint that returns stored records more or less as they are makes every schema change a contract change. A contract should be expressed in entities and facts, with its own schema, separate from the persistence model.

## Verify by

- A breaking-change detector for the schema language when one is configured: see `static-analysis-integration.md`.
- Diffing the generated client or type declarations.
- Reading one real consumer end to end.
- Contract or pinning tests updated in the same change.

## Do not flag

- Symbols that are internal. Confirm they are not exported or used across packages.
- Additive changes for consumers known to tolerate them.
- A breaking change shipped as a new major version with migration notes.

## Priority guidance

P0: a breaking change with live consumers and no compatibility path, a silent change of meaning, in-flight messages that will fail, a spec that misstates required or nullable fields that generated clients rely on. If consumers are unknown and the change would break them, raise a `[P0][question]` asking for the consumer list. P1: a compatible change that leaves spec and code out of step, or a deprecation with no removal plan. Additive, documented changes need no finding.
