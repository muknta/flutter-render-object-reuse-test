# render_key_test

Minimal Flutter repro testing whether widget rebuilds reuse the underlying `RenderObject`, and what actually controls that — keys, `const`, or content.

## Problem

Common assumption: "identical const widgets reuse their render object; anything with different keys or different text gets re-rendered." That's imprecise — `const`-ness and content have nothing to do with `RenderObject` reuse. Reuse is decided by `Element.canUpdate`, which only checks `runtimeType` and `key` match at the same child slot. This repro isolates that by testing 5 configurations of an otherwise-identical widget:

- **A** — `const` widget, `const ValueKey`, same every rebuild (golden case)
- **B** — same `ValueKey`, but text content changes every rebuild (not `const`)
- **C** — no key, non-`const`, identical position every rebuild
- **D** — no key, `const`, identical every rebuild
- **E** — key itself changes every rebuild (the real "different keys" case)

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

Run it yourself:

```
flutter run -d macos   # or any connected device
```

Click "Rebuild (setState)" and watch the console for `CREATE` / `REUSE` / `DISPOSE` lines per probe.
