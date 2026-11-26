# Observability and operations

Use when: logging, metrics, tracing or alerts change, the change adds or alters a production path or background work, or failure handling changes what operators can see.

## The test

For each materially changed production path: how would an operator **detect** a bad outcome, **diagnose** its cause and **verify** recovery? Inspect the instrumentation and platform signals that already exist before asking for more. Do not demand logs, metrics or traces for every change.

## Checks

**Detection and outcomes**
- Signals exist for failure, latency, traffic and saturation where they matter, and for the domain outcome (orders placed, messages delivered, records synced).
- Success is recorded at the boundary its name promises. "Accepted" or "queued" is not "completed". An HTTP 200 or a success log does not prove a background task finished.
- Silent drops, skipped items, stale data and missing progress are visible. Filtered or rejected items are counted.

**Logs**
- Structured fields, an operation name and an outcome. Useful error detail: cause and safe identifiers.
- Correlation: a request or job identifier that survives service and queue boundaries.
- Levels follow the repository's convention. Expected retries and cancellations are distinct from terminal failures.
- An error is logged once, at the boundary that handles it, not at every layer on the way up.
- No secrets, tokens, raw payloads or personal data. No log lines inside tight loops.
- Log text that alerts or queries match on is a contract: search before changing it.

**Metrics**
- The unit is clear. Counter, gauge and histogram are used for what they mean.
- Label values are bounded: no user ids, request ids, raw URLs or error messages as labels.
- Renaming or removing a metric breaks dashboards and alerts. Search for its consumers.

**Traces**
- Context propagates across async boundaries: queues, thread pools, callbacks.
- Spans end on the error path. Sampling does not hide the rare failure you would need.

**Async lifecycle**
- Queue age or lag, retries versus exhausted retries, dead-letter contents, stalled jobs, time of the last successful run.
- A worker or scheduler that reports healthy while doing no useful work.

**Alerts and response**
- For a consequential failure, an existing alert or workflow reaches an owner who can act.
- Thresholds come from documented objectives and expected volumes. Do not invent them.
- No alert without an action, no duplicate of an existing alert. Recovery guidance exists when recovery is not obvious.

**Safety and cost**
- Redaction, access and retention of telemetry.
- Volume in hot paths. Exporters that block the request path.
- A telemetry failure must not break business processing, unless an audit or fail-closed requirement says otherwise.

**Rollout**
- Flags and config defaults are safe. An operator can tell a regression from normal behavior with views that exist.
- When it is safe and proportionate, exercise one representative failure and look at the signal it emits.
- In the handoff, separate signals you observed at runtime from signals you inferred by reading code.

**Removed telemetry**
- A deleted log line, metric, span or alert: who was using it?

## When you cannot see the monitoring

Ask, do not assert. "Which alert or dashboard would show terminal failures of this job?" is a question. "There is no monitoring" is a claim you cannot support from the diff.

## Do not flag

- The absence of logs or metrics in code with no consequential failure mode.
- Extra diagnostic convenience as if it were required.
- "Add tracing" with no failure scenario behind it.
- Wording of log messages.

## Priority guidance

P0 only when a demonstrated gap materially conceals a consequential failure, when a failed outcome is reported as success, when sensitive data is emitted, or when a documented operational requirement is violated. Explain the failure, the missing or misleading signal and the operational consequence. P1 when a likely failure would be detected late or be hard to diagnose. Everything else is P2. When a reliability problem and an observability gap share one root cause and one fix, write one finding.
