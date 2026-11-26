# Design and maintainability

Use when: the change adds modules or abstractions, crosses layers, refactors, introduces or reshapes types, or lays groundwork others will build on.

Ground rule: a design finding names its cost. That is the maintenance task made harder, the class of bug made likely, or the commitment made hard to reverse. "Violates single responsibility" is not a finding. Principles are diagnostic aids, never justifications. If you cannot name the cost, do not comment.

## The questions

- For the most likely next change, where would someone have to edit, and in how many places?
- Does each decision (a rule, a mapping, a permission) live in exactly one place?
- If a second or third consumer needed a variant, would that be a config change or a code change?
- Can this function be understood without reading three other modules?
- Is this the smallest design that meets today's requirement without closing a door the roadmap already needs?

## Red flags

**Right change, right place**
- Domain decisions made in controllers, views, serializers or SQL strings. Infrastructure details leaking through domain or public interfaces.
- A reach into another module's internals. A new dependency cycle. New global state.
- A contextual value threaded through many signatures when the codebase has a context mechanism for it.

**Single source of truth**
- Duplicated policy that can drift: validation rules, permission checks, status-to-label mappings, constants.
- A re-implemented helper. Name the existing one and confirm the semantics match before flagging.
- Two ways of doing the same thing introduced in one change.
- The reverse mistake: merging things that merely look alike but change for different reasons.

**Abstractions**
- Speculative generality: an interface with one implementation, a factory for one product, options nobody sets, a plugin system with one plugin.
- Boolean or mode parameters that switch behavior. Option objects that grow without limit.
- Inheritance used only to share code.
- The reverse: the third copy of the same logic with no shared home.

**Solution heavier than the problem**
- Leases, locks, caches, state machines or tolerance layers where a constraint, a validation at the boundary or deleting a condition would do.
- When the explanation is longer than the change, look for the simpler fix.
- Useful tags for a simplification suggestion: delete it, the standard library has it, the platform has it, not needed yet, same logic in fewer lines.

**Types and data shapes**
- Can an invalid state be constructed? Two booleans that encode three legal states. Fields that are only valid together but are independently optional.
- A boolean that will need a third value: make it an enumeration now instead of migrating later.
- Bare strings and numbers for identifiers, units and money.
- Invariants enforced by comments or by callers instead of the constructor. Mutable internals handed out.
- Untyped maps and `any` crossing module boundaries.

**Local reasoning**
- Names that mislead: an `isValid` that mutates, a `get` that writes, a field name that promises a format it does not hold.
- A function doing unrelated things. Deep nesting that an early return would flatten.
- Hidden ordering requirements ("call A before B"). Side effects in accessors. Action at a distance.

**Vocabulary**
- One concept with two names, or one name for two concepts. A new word where the codebase already has one.
- Names describing who asked instead of what it is. Names outlive requesters.

**Generic core, specific edge**
- Customer, client or tenant names in conditionals inside shared code.
- Behavior that should vary by data or config implemented as a code fork.
- A shared primitive narrowed for one use case. Specialize at the edge.

**Scope and hygiene**
- The diff does materially more than the description says. Unrelated rewrites bundled in. Ask for a split.
- Dead code, unused parameters and exports, commented-out code, debug leftovers.
- A temporary workaround with no removal condition and no owner.
- A capability removed as a side effect. That is a product decision, not a cleanup.

## Credit the inverse

A change that deletes dead code, removes an abstraction nobody needed or solves the problem with less is worth one specific line in the handoff.

## Verify by

- Searching for an existing helper or pattern before calling something duplicated or new.
- Sketching the next likely change and counting the edit points.
- Checking the import direction between the modules involved.
- Listing the call sites of a new abstraction. One call site is a signal.

## Do not flag

- A preference for a different pattern with no stated cost.
- File or function length by itself.
- "Could be more generic." Legacy code that the change only passes through.
- Naming taste.

## Priority guidance

P0 only when the design creates a costly or hard-to-reverse commitment now: a public contract shape, a persisted format, a security policy duplicated where it can diverge, coupling across services. Or when it makes required behavior impossible to verify. P1 when the next likely change gets measurably harder: name the task and the edit points. P2 for the rest, with the concrete cost and a proportionate alternative.
