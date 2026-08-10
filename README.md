# SwiftTUI

**[English](README.md)** | [中文](README.zh-CN.md)

Bring SwiftUI into the terminal. Works on macOS, Linux and Windows, powered by high-performance VT rendering.

SwiftTUI brings SwiftUI's declarative API to terminal application development. Describe your interface the way you would in SwiftUI, and you get a TUI program driven primarily by the mouse—click buttons, hover for highlights, scroll through pages with the wheel.

## Core features

- Mouse-driven: most major components support mouse click, hover, scrolling, and more.
- SwiftUI-DSL-like: no need to over-explain—it basically feels like SwiftUI.
- JsonData compatible: supports usages similar to `@Query` in SwiftUI. (JsonData is essentially the public-API equivalent of SwiftData. See https://github.com/zxss702/JsonData for details; it's open-sourced under the MPL-2.0 license.)
- High-performance rendering: built on the VirtualTerminal subsystem with a push-based model.

## Currently supported SwiftUI capabilities

✓ `Button` (click/hover), `Text`, `TextField`, `TextEdit`
✓ `ScrollView`, `GeometryReader`, `Spacer`, `Divider`
✓ `VStack`, `HStack`, `ZStack`, `LazyVStack`, `LazyVGrid`
✓ `Color` with ANSI / xterm / TrueColor support
✓ `.frame()`, `.padding()`, `.border()`, `.foregroundColor()`, `.background()`
✓ `.bold()`, `.italic()`, `.underline()`, `.strikethrough()`, `.onAppear()`, `.onHover()`, `.environment(_:_:)`
✓ `@State`, `@Binding`, `@Environment`, `@Query`
✓ `ForEach`, `Group`, `@ViewBuilder`

## Quick start

Add SwiftTUI as a dependency and write views just like you would in SwiftUI. Launch it with `Application`, passing in your root view:

```swift
import SwiftTUI

struct MyTerminalView: View {
    var body: some View {
        Button("Click me") {
            print("Clicked!")
        }
    }
}

try await Application(rootView: MyTerminalView()).start()
```

Working with JsonData (SwiftData)

```swift
import SwiftTUI
import JsonData

struct MyTerminalView: View { ... } // Basically the same as using SwiftData in SwiftUI.

let schema = Schema([TaskItem.self])
let modelConfiguration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: "todo.db"))

let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])

try await Application(rootView: MyTerminalView())
    .modelContainer(modelContainer) // Injects the environment to resolve refresh issues. Currently one data container per window.
    .start()
```

Switch to your package directory in the terminal and run:

```
swift run
```

## Examples

The repository includes a few simple examples for reference.

## Architecture

Host: an input pump plus frame tasks that coalesce wakes; interaction events settle in the current frame, while mouse-move is only scheduled (to avoid the key/mouse starvation caused by 1003). The frame stages are fixed as Update → Layout → Paint → Present. See [Docs/Architecture.md](Docs/Architecture.md) for details.

```
View (SwiftUI-style DSL)
       │
   ViewGraph (Node / @State slots / Observation)
       │
   Element tree (layout / focus / hit-test / paint)
       │
VirtualTerminal (diff present)
```

The entry point is intentionally CLI-shaped: `Application(rootView:).start()` (not `App` / `WindowGroup`).

## Contributing

We warmly welcome code contributions and suggestions for SwiftTUI! Before submitting code, please read our [contributing guide (CONTRIBUTING.md)](CONTRIBUTING.md).

## License

This project is open-sourced under the **MPL-2.0 (Mozilla Public License 2.0)**.

What this means:
- **You are free** to use this framework in your commercial, closed-source projects (without open-sourcing your app).
- **But if you directly modify the source of this framework**, you must open-source those modifications back to the community under the MPL-2.0 license. We encourage everyone to help make SwiftTUI even better!

## Star history

<a href="https://star-history.com/#zxss702/SwiftTUI">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=zxss702/SwiftTUI&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=zxss702/SwiftTUI&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=zxss702/SwiftTUI&type=Date" />
  </picture>
</a>
