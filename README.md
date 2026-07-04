# SwiftTUI

![swift 6.0](https://img.shields.io/badge/swift-6.0-orange.svg)
![platform macOS](https://img.shields.io/badge/platform-macOS%2015+-lightgrey.svg)
![platform Linux](https://img.shields.io/badge/platform-Linux-lightgrey.svg)
![platform Windows](https://img.shields.io/badge/platform-Windows-lightgrey.svg)

把 GUI 的交互直觉带进终端。

SwiftTUI 将 SwiftUI 的声明式 API 引入终端应用开发。你只需像写 SwiftUI 一样描述界面，就能得到一个以鼠标驱动为主的 TUI 程序——点击按钮、悬停高亮、滚轮翻页。

### 核心特性

**以鼠标驱动为核心交互：** 鼠标悬浮、点击、滚轮滚动。按钮在鼠标划过时自动高亮，点击触发——键盘输入仍有保留支持，但鼠标已成为主力交互方式。

**SwiftUI 声明式写法：** 用 `@State`、`@Binding`、`@Environment`、`@ObservedObject` 管理状态，用 `VStack` / `HStack` / `ZStack` 布局，用 `@ViewBuilder` 和 `ForEach` 组合视图。

**高性能差分渲染：** 底层 VirtualTerminal 子系统直接将变更写入终端缓冲区，配合 SGR 优化、光标运动压缩和增量差分，只刷新真正变化的区域。

目前支持的 SwiftUI 能力：

✓ `Button`（支持点击与悬浮）、`TextField`、`Text`（粗体/斜体/下划线/删除线）  
✓ `ScrollView`、`GeometryReader`、`Spacer`、`Divider`  
✓ `.frame()`、`.padding()`、`.border()`、`.foregroundColor()`、`.backgroundColor`  
✓ `.onAppear()`、`.onHover()`  
✓ `Color` 支持 ANSI / xterm / TrueColor  
✓ `@State`、`@Binding`、`@Environment`、`@ObservedObject`  
✓ `ForEach`、`Group`、`@ViewBuilder`、结构标识

### 快速开始

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

在终端中切换到你的包目录后运行：

```
swift run
```

### 示例

仓库内提供了四个示例项目：

#### Numbers（[Examples/Numbers](Examples/Numbers)）

最简单的交互示例——点击按钮增减列表条目数量，支持滚轮翻阅。展示 Button、ForEach 和 ScrollView 的基本用法。

#### ToDoList（[Examples/ToDoList](Examples/ToDoList)）

经典的待办事项应用。鼠标点击某个条目前面的复选框即可标记完成，已完成的条目会在半秒后自动消失。底部文本框可直接输入新事项并回车添加。

#### Flags（[Examples/Flags](Examples/Flags)）

国旗编辑器。点击旗帜上的颜色条即可切换颜色，右侧面板可调整颜色数量和排列方向（横向/纵向）。

#### Colors（[Examples/Colors](Examples/Colors)）

颜色浏览器。展示 SwiftTUI 对 ANSI 256 色和 TrueColor 的完整支持。

### 架构

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

### 参与贡献

这是一个开源项目，欢迎贡献！SwiftTUI 的核心理念是：在 API 设计和内部机制上尽可能贴近 SwiftUI，除非某些设计对终端应用没有意义。对于 SwiftUI 不具备但对终端应用有用的特性，建议放在独立项目中迭代。
