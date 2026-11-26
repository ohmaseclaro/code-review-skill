# Infrastructure, IaC and CI

Use when: the change touches Terraform or other infrastructure code, Kubernetes manifests, Helm charts, Dockerfiles, compose files, CI workflows, deploy scripts or environment configuration.

Core fact: these files run with more privilege than the application and usually have no tests. One line can delete data, open a network path or hand a secret to untrusted code.

## The questions

- What happens to resources that already exist: updated in place, replaced or destroyed?
- What new permission, network path or secret exposure appears, and for whom?
- If the apply or rollout fails halfway, what state is left and how is it undone?
- Does the pipeline still enforce everything it enforced before this change?

## Terraform and other infrastructure code

- **Read the plan, not only the diff.** Look for `destroy`, `must be replaced` and `forces replacement` on stateful resources: databases, buckets, volumes, queues, DNS records. Ask for the plan output if you cannot produce it.
- Renamed or moved resources without `moved` blocks or state moves become destroy and create.
- `count` or `for_each` keys that shift resource addresses and recreate unrelated resources.
- Deletion protection, `prevent_destroy`, backups or versioning removed, or absent on a new stateful resource.
- IAM: wildcard actions or resources, wildcard principals, broad trust policies, role-passing permissions.
- Network: ingress from `0.0.0.0/0`, public IPs, public buckets, TLS disabled.
- Secrets in variables, defaults, outputs, user data or committed variable files. State stores them in plain text.
- Provider and module versions pinned. Module sources pinned to a tag or commit. Lock file updated.
- `ignore_changes` hiding drift. `local-exec` and similar provisioners running arbitrary commands.
- A change applied to one environment's files only. Hard-coded account ids and regions.
- Backend or workspace changes that point at a different state.

## Kubernetes and Helm

- Requests and limits present and consistent with the runtime's own memory settings.
- Probes: a liveness probe that depends on downstream services causes restart storms. Missing readiness or startup probes send traffic too early.
- Rollout safety: `maxUnavailable`, disruption budgets, a single replica with `Recreate`, graceful shutdown (termination grace period, SIGTERM handling, preStop).
- Selector and label changes on Deployments and Services: selectors are immutable, and a mismatch orphans pods or drops traffic.
- Security context: root user, privileged mode, host network or host paths, added capabilities, writable root filesystem, automounted service account tokens.
- RBAC: cluster-wide roles, wildcard verbs, read access to secrets.
- Images by mutable tag (`latest`) instead of a version or digest.
- Secrets in ConfigMaps or plain values files. Environment variables renamed without the matching application change in the same rollout.
- An autoscaler and a fixed `replicas` value fighting each other.
- Jobs and CronJobs: concurrency policy, backoff limit, deadline, time zone.
- Helm: every environment's values updated, hooks with side effects, CRD changes that an upgrade does not apply. Render the chart and read the output.

## Dockerfiles and images

- Base image from a trusted registry, pinned by version and, for production, by digest.
- Secrets in `ARG`, `ENV` or copied files persist in image layers. Use build secret mounts.
- A non-root `USER`. Build tools kept out of the final stage.
- `COPY . .` that pulls in `.git`, `.env` or credentials: check `.dockerignore`.
- `curl | sh` or `ADD <url>` with no checksum.
- `ENTRYPOINT` in exec form so signals reach the process. A shell wrapper needs `exec`.
- Package index update and install in the same layer, with versions pinned where reproducibility matters.

## CI and automation workflows

- **Who can trigger it, with which token, running whose code?** Triggers such as `pull_request_target`, `workflow_run` and `issue_comment` combined with a checkout or execution of the contributor's code give untrusted code a privileged token.
- `permissions:` missing or broader than needed. Newly added `contents: write`, `id-token: write`, `pull-requests: write` or `secrets: inherit`.
- Third-party actions not pinned to a full commit SHA. New actions from unknown publishers.
- Script injection: event fields (title, body, branch name, commit message) interpolated into `run:` blocks. Pass them through `env:` and quote them.
- Secrets echoed, written to artifacts or caches, passed on a command line, or available to jobs that run fork code.
- Caches and artifacts shared between untrusted and privileged jobs.
- Checkout that keeps credentials in the workspace of a job running untrusted code (`persist-credentials: false` prevents it).
- Self-hosted runners reachable from public contributions.
- **Weakened gates:** `continue-on-error`, `|| true`, `allow_failure`, an always-false condition, a removed required job, path filters that skip checks, lowered thresholds, deleted test steps.
- Deploy jobs: environment protection, concurrency groups so that two deploys cannot race, cloud trust conditions scoped to the right branch or environment.
- Missing timeouts on jobs that can hang.

The same questions apply to other CI systems: protected variables exposed to unprotected branches, includes from mutable refs, rules that silently skip jobs.

## Configuration and environment

- A new required key exists in every environment, is documented, and its absence fails at startup with a clear message.
- Changed defaults: who relied on the old one?
- Timeouts, pool sizes and limits that must agree with the systems on either side.
- Production endpoints or credentials in non-production config, and the reverse.

## Verify by

- The plan or a rendered manifest per environment: `terraform plan`, `helm template`, a client-side dry run, a schema validator.
- Linters the repository already configures for workflows, Dockerfiles and infrastructure code.
- Reading the workflow as an attacker: open a pull request from a fork, name a branch with shell metacharacters, and follow what runs.
- Never run `apply`, deploy steps or anything that needs real credentials as part of a review.

Ordering, rollback and what to watch after deploy belong in the deployment section: see `qa-and-rollout-plan.md`. When the workflow under review runs an AI reviewer, also open `prompt-injection-defense.md`.

## Do not flag

- HCL or YAML style and key order.
- Missing hardening in files the change did not touch, beyond one line in the handoff.
- Cost concerns with no size attached.

## Priority guidance

P0: a stateful resource destroyed or replaced with no recovery plan, public exposure or wildcard privileges, a secret exposed in layers, logs, state or to fork-triggered jobs, untrusted code running with write permissions or secrets, a merge gate removed or neutralized, a rollout that takes a critical service down. P1: unpinned actions or images, missing limits or probes on a new workload, a config key missing in one environment where startup fails safely. P2: hardening and hygiene.
