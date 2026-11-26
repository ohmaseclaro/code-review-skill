# Frontend and accessibility

Use when: the change touches UI components, styles, client state, forms, routing or client-side data fetching.

## The questions

- What does the user see while loading, with no data, on error, with partial data and offline?
- Can the feature be used with a keyboard alone, and with a screen reader?
- What happens on a slow network, a double click, the back button, a stale tab?
- Does the server render the same thing the client does?

## States and interaction

- Loading, empty and error states exist and are distinguishable.
- Double submission: the action is disabled or deduplicated while pending.
- Out-of-order responses: an older request finishing last must not overwrite newer state. Requests are aborted on unmount or navigation.
- Optimistic updates roll back on failure.
- Deep links, back and forward restore the right state.
- Long text, zero items, one item, thousands of items, and very long words.
- Form input survives a failed submit. Validation messages say what to fix.
- Dates, numbers and currency are formatted for the user's locale. Strings are externalized. Layout survives right-to-left text.

## Component and state pitfalls

React examples, with the same ideas in other frameworks:

- Effect dependencies missing or too broad. Effects used to derive state that could be computed during render.
- Stale closures in callbacks and timers. Missing cleanup for subscriptions, timers and listeners.
- Index used as key in a list that reorders or filters. Hooks called conditionally.
- State or props mutated in place. State copied from props and never resynchronized.
- A context value recreated on every render, re-rendering every consumer.
- Inputs switching between controlled and uncontrolled.
- Reactivity lost by destructuring or reassigning reactive objects, and watchers or subscriptions never torn down.

## Data fetching and rendering

- Cache keys include every parameter that changes the result. Mutations invalidate what they affect.
- Request waterfalls and one request per row.
- Module-level state on the server shared across users' requests.
- Hydration mismatches from time, randomness or locale during render. Browser-only globals used during server render.
- Server-only modules or secrets pulled into a client bundle.

## Accessibility

- Semantic elements: a real `button`, `a` or `input`, not a clickable `div`.
- Every control has an accessible name. Images carry meaningful alternative text, or an empty one when decorative.
- Everything works from the keyboard: reachable, visible focus, sensible order, Escape closes, no traps.
- Focus management for dialogs, menus and route changes: move focus in, keep it there, restore it afterwards.
- ARIA only where native semantics fall short, with roles and states that match the behavior. No `aria-hidden` on focusable content.
- Form errors are associated with their fields and announced.
- Async updates are announced where they matter (live regions).
- Information is not carried by color alone. Contrast meets the project's standard.
- Motion respects the reduced-motion preference. Auto-dismissing messages leave enough time.
- Touch targets are large enough. Headings and landmarks give structure.

## Security in the UI

- Raw HTML sinks fed with content that is not fully trusted.
- `href` or `src` built from user input without restricting the scheme.
- Tokens in web storage. Secrets or private configuration exposed through public build-time variables.
- Message handlers that do not check the sender's origin.
- Authorization enforced only in the client. The server must enforce it.

## Performance

- A heavy dependency added for a small need, or a whole library imported for one function.
- Images without dimensions (layout shift), oversized assets, fonts that block rendering.
- Long lists without virtualization. Expensive work during render. Animations that force layout.

## Styling and layout

- Breakpoints, overflow and truncation. Stacking contexts and z-index escalation.
- Design tokens and existing design-system components used instead of hard-coded values and re-created widgets.
- Global styles leaking across components.

## Verify by

- Running the UI when you can: one pass with the keyboard only, one with a narrow viewport.
- A browser or screenshot tool if the host provides one. Otherwise ask for a screenshot or recording of a visual change.
- Accessibility lint output and component tests that query by role and label.
- Bundle size reports from CI when available.

Tracking events consumed by dashboards are contracts: see `api-contracts.md`.

## Do not flag

- Visual taste. Memoization as a reflex.
- Accessibility debt in markup the change did not touch, beyond one line in the handoff.
- Hypothetical render performance with no measurement or obvious cause.

## Priority guidance

P0: a primary action that cannot be reached or operated by keyboard or assistive technology in a new flow, script injection, a state bug that loses user input or shows another user's data, a hydration crash, a secret in the bundle. P1: a missing loading, empty or error state on a common path, a secondary accessibility barrier, a race with a visible but recoverable glitch. P2: polish.
