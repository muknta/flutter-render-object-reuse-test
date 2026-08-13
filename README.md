# render_key_test

Minimal Flutter repro testing whether widget rebuilds reuse the underlying `RenderObject`, and what actually controls that — keys, `const`, or content.

## Problem

Common assumption: "identical const widgets reuse their render object; anything with different keys or different text gets re-rendered." That's imprecise — `const`-ness and content have nothing to do with `RenderObject` reuse. Reuse is decided by `Element.canUpdate`, which only checks `runtimeType` and `key` match at the same child slot. This repro isolates that by testing 5 configurations of an otherwise-identical widget:

- **A** — `const` widget, `const ValueKey`, same every rebuild (golden case)
- **B** — same `ValueKey`, but text content changes every rebuild (not `const`)
- **C** — no key, non-`const`, identical position every rebuild
- **D** — no key, `const`, identical every rebuild
- **E** — key itself changes every rebuild (the real "different keys" case)
- **F** — `GlobalKey`, moved between two different parents on the same page (see Part 2)

## How it's tested

Widget hash/`hashCode` on the `Widget` object is useless here — a new `Widget` instance (except when `const`-canonicalized) is created on every `build()` regardless of what happens underneath. The thing that actually persists or gets torn down is the `RenderObject`.

`ProbeBox` (`lib/main.dart`) is a `LeafRenderObjectWidget` that overrides:
- `createRenderObject` — logs `CREATE` with `identityHashCode(renderObject)`
- `updateRenderObject` — logs `REUSE` with the same id
- `didUnmountRenderObject` — logs `DISPOSE`

A button triggers `setState` to force a rebuild; the id printed each time is the ground truth for whether the same `RenderObject` instance survived.

## Result

Across 9 forced rebuilds:

| Case | Behavior | RenderObject id |
|---|---|---|
| A — const + same key | No log line on rebuild at all — Flutter never re-enters `update`, because the const widget instance is `identical()` to the previous one and the `Element` short-circuits | fixed, never changes |
| B — same key, changing text | `REUSE` every rebuild | fixed, never changes |
| C — no key, non-const, same slot | `REUSE` every rebuild | fixed, never changes |
| D — const, no key | Same as A — silent, short-circuited | fixed, never changes |
| E — key changes every rebuild | `CREATE` new + `DISPOSE` old, every single rebuild | changes every time |

## Conclusion

- **Keys/type only matter for matching**, not content. B and C prove `RenderObject` identity survives content changes as long as `runtimeType` + `key` (or slot position, when no key) match.
- **`const` doesn't change the reuse rule** — it just lets Flutter skip calling `build`/`update` entirely, because the exact same canonicalized widget instance is passed in. A and D show identical outcomes to a non-const case with a stable key; const is a bonus optimization on top, not a different reuse mechanism.
- **Changing the key is the only thing that forces teardown** in this test. E is the sole case that pays the full dispose+create cost every rebuild.

## Part 2 — does reuse survive a parent change?

The first 5 cases all rebuild the child at the *same slot under the same parent Element*. Real apps also move widgets to a genuinely different parent — most commonly, navigating to a new route. Does matching key/type still preserve the `RenderObject` there?

**Theory:** No, by default. `canUpdate` matching is not a global lookup — it only compares siblings during a single parent `Element`'s own child-reconciliation pass. A new route builds a brand-new `Element` tree top-down; the new parent never had a previous child to compare against, so every child is an *insert*, regardless of whether its type/key happens to match something on the page you navigated from. Keys don't transcend parent/route boundaries.

The one mechanism that does transcend a parent change is `GlobalKey`. If a widget with a matching `GlobalKey` appears elsewhere in the tree in the same frame its old location is vacated, Flutter calls `Element.moveTo` — the existing `Element` (and its `RenderObject`) is literally relocated, not disposed and recreated.

Two probes test this:

- **F — GlobalKey, swapped between two different parent `Container`s on the same page**, via a toggle button. Both parents are built in the *same* `build()` call, so there's no ambiguity about ordering.
- **A2 / B2 — `SecondPage`**, reached via `Navigator.push`, redeclares `ProbeBox`es with the *same* `ValueKey` string (`'golden'`) and the same no-key shape as page 1's `A`/`C`, to check whether a matching key from a totally different route causes reuse.

### Result

- **F (GlobalKey swap, same page):** `REUSE` every time, same `RenderObject` id, across every swap and every rebuild — confirmed with zero `CREATE`/`DISPOSE` after the first. `Element.moveTo` reparenting works cleanly within a single build pass.
- **A2 / B2 (route push/pop):** `CREATE` on every single visit to `SecondPage`, `DISPOSE` on every pop — despite `A2` using the exact same `ValueKey('golden')` string as page 1's golden case. Confirms key matching does not transcend a route/parent boundary.

### A real constraint discovered along the way: GlobalKey does NOT survive a Navigator route push

The first version of this repro tried to also prove `GlobalKey` reparenting *across* a route push — same `GlobalKey` instance used by a probe on page 1 and again on `SecondPage`. This reliably threw:

```
Another exception was thrown: Duplicate GlobalKey detected in widget tree.
```

This is not a bug in the repro — it's a structural property of `Navigator`. A route push needs to animate the old route out, so `Navigator` keeps **both** the old and new route's `Element` trees mounted simultaneously for the duration of the transition. Two things were tried to eliminate that overlap and both failed to help:

- `maintainState: false` — only controls whether a *covered, non-topmost* route stays mounted after the transition finishes. It has no effect during the transition itself, which is exactly when the collision happens.
- `PageRouteBuilder` with `transitionDuration: Duration.zero` — doesn't eliminate the overlap either, because removing the old route's `OverlayEntry` is driven by an `AnimationController` status listener, and that listener fires on the *next frame*, not synchronously within the same frame the animation reaches its end value. So even a "zero duration" push still leaves one frame where old and new route are both mounted.

Net effect: as long as a `GlobalKey`'d widget is present on both sides of a `Navigator.push`, there will always be at least one frame with two live `Element`s claiming the same `GlobalKey`, and Flutter's uniqueness assertion fires. `GlobalKey` reparenting is real, but it only works within a single synchronous build pass (e.g. moving a widget between parents in the same page, as probe F does) — not across a route transition.

## Running it

```
flutter run -d macos   # or any connected device
```

- "Rebuild (setState)" — drives cases A–E.
- "Swap GlobalKey probe to other parent" — drives case F.
- "Navigate to new page (push route)" / "Pop back to page 1" — drives cases A2/B2.

Watch the console for `CREATE` / `REUSE` / `DISPOSE` lines per probe.
