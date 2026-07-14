# SwiftTUI Architecture

## Runtime model

```
View (SwiftUI-shaped DSL)
  → ViewGraph (Node + @State slots + Observation)
  → Element tree (layout / focus / hit-test / paint)
  → Layer dirty rects
    → VTRenderer (delta present)
```

## Entry (intentional, CLI-shaped)

```swift
try await Application(rootView: RootView()).start()
```

Not `App` / `WindowGroup` — TUI hosts one terminal surface and must compose with CLI entrypoints.

## Frame pipeline

`Application` owns a `Transaction`, a coalescing `FrameScheduler`, and a `HostClock`.

Two MainActor tasks:

1. **Input loop** — `for try await event in terminal.input` → `dispatchTerminalEvent`
2. **Frame loop** — consumes `FrameScheduler` wakes (Observation, residual dirty, hover paint)

### `dispatchTerminalEvent`

- Always `handleTerminalEvent`
- **Inline `settleHost`** for key / click / scroll / resize (`HostEventPolicy.requiresInlineSettle`)
- **Mouse-move only** marks dirty + `scheduleUpdate` (DECSET 1003 must not block the pump)

### `settleHost` → `commitFrame` → `update`

1. Flush staged editor Binding commits  
2. Rebuild dirty nodes  
3. Refresh popup panels  
4. Layout (bounded passes)  
5. Paint  
6. Present  

While a commit is open, `scheduleUpdate` coalesces into one post-commit wake (no unbounded wake backlog).

## Design choices (terminal-suited)

| Choice | Rationale |
|--------|-----------|
| Dual tree (ViewGraph + Element), not Attribute Graph | Enough for TUI; far less complexity |
| No PreferenceKey / Layout protocol | Low terminal payoff |
| Navigation page keep-alive (`hidden`) | Push/pop must not rebuild root `@State` |
| Slot-based `@State` | Structural identity without Mirror labels |
| Cached `EnvironmentValues` on Node | Avoid parent-chain walks every read |
| `HostClock` (Task) for delays/animation | No GCD / `Timer` in View/Host layer |
| VT FFI may use pointer `unsafe*` | Concurrency `@unchecked Sendable` abuse is not allowed in UI layer |

## Public API

View / modifier / property-wrapper **shapes** align with SwiftUI / SwiftUICore headers on the host SDK. Entry stays `Application.start()`.
