# Security

Use when: the change touches authentication, sessions, permissions, tenancy, cryptography, secrets, input parsing, file handling, outbound requests, redirects, deserialization or security-relevant configuration, or when a security-focused review is requested.

## The questions

- Who can reach this code path, and what stops everyone else?
- What does the credential or token actually prove, and who can obtain one?
- Whose data is this, and is that ownership enforced in the query itself?
- Where does each untrusted value come from, and where does it end up?

## Method

1. **Learn the house pattern.** Find how the repository already validates input, checks authorization, builds queries and escapes output.
2. **Compare.** New code that deviates from the established secure pattern is the signal. A sibling field or route that gets a check this one lacks is a concrete inconsistency.
3. **Trace.** Follow each new untrusted source to every sink. Write the exploit scenario in one sentence. If you cannot, you do not have a finding yet.

## Checklist (ordered as the OWASP Top 10:2025)

**A01 Broken access control**
- Authorization per object, not just per route: every read and write by id checks ownership or tenant.
- The tenant or user key comes from the authenticated context, never from the body, a query parameter or a client header.
- List and search endpoints filter by tenant in the query, not after fetching.
- A new route outside the middleware or guard that protects its siblings. Auth applied per route where a router-level default would not let a new route slip through.
- Mass assignment: request bodies bound straight onto models (`role`, `isAdmin`, `ownerId`, `price`).
- Background jobs and event handlers that trust an embedded id instead of re-deriving scope from a verified origin.
- Server-side requests to user-supplied URLs: allow-list hosts, block private ranges and metadata addresses, handle redirects and DNS rebinding.

**A02 Security misconfiguration**
- Debug modes, verbose errors or stack traces reaching clients. Permissive CORS, especially with credentials.
- Cookies without `Secure`, `HttpOnly` and a `SameSite` choice. Security headers removed.
- TLS verification disabled. Default credentials. Publicly readable storage. Admin or diagnostic endpoints exposed.

**A03 Software supply chain failures**
- New or changed dependencies, build scripts that fetch and execute remote code, unpinned CI actions: see `dependencies-supply-chain.md` and `infra-iac-ci.md`.

**A04 Cryptographic failures**
- Passwords hashed with a fast hash instead of a password hashing function. Homemade crypto. ECB mode, static or reused IVs and nonces.
- Tokens from a non-cryptographic random source, or too short.
- Secrets and MACs compared with a timing-unsafe equality.
- JWT handling: decoding without verifying, accepting `none`, missing expiry, audience or issuer checks, key confusion.

**A05 Injection**
- SQL and NoSQL built by concatenation or interpolation. Operator injection from JSON bodies into document queries.
- OS commands through a shell with interpolated input. `eval` and dynamic code.
- Path traversal: `../`, absolute paths, archive extraction, symlinks.
- Cross-site scripting through raw HTML sinks, unescaped template helpers, `javascript:` URLs, rendered Markdown.
- Unsafe deserialization of untrusted data. XML external entities. Server-side template injection.
- Header and redirect injection, open redirects, user input compiled into a regex.

**A06 Insecure design**
- Trusting client-supplied price, role, discount or step in a multi-step flow.
- No rate limit or lockout on authentication, reset and other expensive or abusable endpoints.
- Check-then-act on balances, quotas or uniqueness.
- Account enumeration through differing responses or timing.

**A07 Authentication failures**
- Auth that is present but vacuous: auto-approved client registration, tokens issued to anyone who asks, identity never verified against a trusted provider.
- OAuth and OIDC: redirect URI validation, `state` and PKCE.
- Sessions: fixation, no invalidation on logout or password change.
- Reset and magic-link tokens: expiry, single use, bound to the user.
- Webhook signatures that are logged on failure instead of rejected, computed over a parsed body instead of the raw one, or lack replay protection.

**A08 Software or data integrity failures**
- Unsigned artifacts or updates. CI steps that pipe a download into a shell. Config or code loaded from a location the requester controls.

**A09 Logging and alerting failures**
- Secrets, tokens or personal data in logs, error messages, URLs, analytics or crash reports.
- A redaction step that only covers one encoding or one error shape, so a different upstream error leaks the payload. Logging the status alone is the safe default.
- Sensitive actions with no audit trail where the repository requires one.

**A10 Mishandling of exceptional conditions**
- Fail-open: a catch block in an auth or validation path that lets the request through.
- A permissive default when configuration is missing.
- Unchecked return codes. Inconsistent state after an exception. Internals revealed by an error path.

## Secrets and privacy

- Credentials, keys or tokens in code, tests, fixtures, docs, CI files, client bundles, container layers or infrastructure state. A committed secret is leaked even if a later commit removes it: recommend rotation. Never quote the value.
- New personal data collected, stored, logged or sent to a third party: purpose, minimization, retention, deletion. Real personal data in test fixtures.

## Multi-tenant check

For every new query, cache key, storage path and queue message: is the tenant key part of it? Shared cache keys across tenants leak data, and can leak existence through timing.

## Precedents: usually not a finding

- Output a framework escapes by default, unless the code uses an explicit bypass.
- Queries built through a parameterizing API.
- Environment variables and CLI flags, which the operator controls.
- Client-side checks that are missing: the finding, if any, is the missing server-side check.
- Test-only code, documentation, theoretical resource exhaustion, generic "missing hardening".
- Memory-safety classes in memory-safe languages.

A precedent is a prior, not a verdict. If you can state a concrete exploit path, flag it regardless. Exclusion lists have dismissed real vulnerabilities.

## Reporting

- Every security finding states: source, sink, the attacker capability required (anonymous, any user, a tenant admin), the exploit in one sentence, the impact and the smallest fix.
- Security findings are exempt from the one-paragraph limit. Clarity beats brevity here.
- For a real vulnerability in code that is already released in a public repository, do not post exploit details publicly. Follow the repository's security policy and tell the user.

## Priority guidance

P0: an exploitable path for a realistic attacker, missing authorization, fail-open behavior, a committed credential, personal data exposed. For a committed credential, open the body with the action needed now (revoke and rotate): deleting it from the diff does not remove it from history. P1: a weakness that needs a second failure to become exploitable. P2: defense in depth with no demonstrated path.
