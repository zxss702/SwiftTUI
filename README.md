# SwiftTUI

把 SwiftUI 带进终端。支持 macOS、Linux、Win。使用 VT 高性能渲染。

SwiftTUI 将 SwiftUI 的声明式 API 引入终端应用开发。你只需像写 SwiftUI 一样描述界面，就能得到一个以鼠标驱动为主的 TUI 程序——点击按钮、悬停高亮、滚轮翻页。

## 核心特性

- 鼠标驱动：绝大部分主要组件均支持鼠标点击、悬浮、滚动等。
- SwiftUI-DSL Like：不过多赘述了，基本上和 SwiftUI 差不多。
- JsonData 兼容：支持类似 SwiftUI 中 `@Query` 等用法。（JsonData 是 SwiftData 的 public api 基本等效物。详情请参阅 https://github.com/zxss702/JsonData，采用 MPL 2 协议开源。）
- 高性能渲染：底层采用 VirtualTerminal 子系统。采用 Push 模式。

## 目前支持的 SwiftUI 能力：

✓ `Button`（点击/悬浮）、`Text`、`TextField`、`TextEdit`
✓ `ScrollView`、`GeometryReader`、`Spacer`、`Divider`
✓ `VStack`、`HStack`、`ZStack`、`LazyVStack`、`LazyVGrid`
✓ `Color` 支持 ANSI / xterm / TrueColor
✓ `.frame()`、`.padding()`、`.border()`、`.foregroundColor()`、`.background()`
✓ `.bold()`、`.italic()`、`.underline()`、`.strikethrough()`、`.onAppear()`、`.onHover()`、`.environment(_:_:)`
✓ `@State`、`@Binding`、`@Environment`、`@Query`
✓ `ForEach`、`Group`、`@ViewBuilder`

## 快速开始

添加 SwiftTUI 依赖，然后像写 SwiftUI 一样写视图。启动时用 `Application` 并传入根视图：

```swift
import SwiftTUI

struct MyTerminalView: View {
    var body: some View {
        Button("点击我") {
            print("被点击了！")
        }
    }
}

try await Application(rootView: MyTerminalView()).start()
```

与 JsonData（SwiftData）配合

```swift
import SwiftTUI
import JsonData

struct MyTerminalView: View { ... } // 与在 SwiftUI 中使用 SwiftData 基本一致。

let schema = Schema([TaskItem.self])
let modelConfiguration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: "todo.db"))

let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])

try await Application(rootView: MyTerminalView())
    .modelContainer(modelContainer) // 通过此注入环境以解决刷新问题。当前只支持一个窗口使用一个 data 容器。
    .start()
```

在终端中切换到你的包目录后运行：

```
swift run
```

## 示例

仓库内提供了几个简单示例，可供参考。

## 架构

SwiftTUI 采用分层架构，核心位于 `Sources/SwiftTUI/VirtualTerminal/`：

```
View 层（声明式 SwiftUI 风格）
       │
   Control 树（hitTest / 焦点 / 事件分发）
       │
VirtualTerminal 子系统
  ├── VTEventStream — AsyncSequence，统一接收键盘/鼠标/窗口变化事件
  ├── VTInputParser  — 解析 ANSI 转义序列和终端输入
  ├── Platform（POSIX / Windows）— 平台适配
  ├── VTRenderer      — 差分渲染，SGR 优化，光标运动压缩
  └── Buffer           — 终端网格缓冲区，逐 cell 管理
       │
   stdout（直接写入终端）
```

## 参与贡献
我们非常欢迎你为 SwiftTUI 提交代码或提出宝贵建议！在提交代码前，请务必阅读我们的 [贡献指南 (CONTRIBUTING.md)](CONTRIBUTING.md)。

## 开源协议
本项目采用 **MPL-2.0 (Mozilla Public License 2.0)** 协议开源。

这意味着：
- **您可以自由地**将本框架用于您的商业闭源项目中（无需将您的 App 开源）。
- **但如果您直接修改了本框架的源码**，您必须将这些针对本框架的修改以 MPL-2.0 协议开源回馈给社区。我们鼓励大家共同将 SwiftTUI 维护得更好！

## 获赞历史

<a href="https://star-history.com/#zxss702/SwiftTUI">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=zxss702/SwiftTUI&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=zxss702/SwiftTUI&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=zxss702/SwiftTUI&type=Date" />
  </picture>
</a>
