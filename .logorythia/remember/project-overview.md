# SwiftTUI 项目概览

## 技术栈
- Swift 6.0
- 平台：macOS 15+、Linux、Windows（Package.swift 仅声明 macOS .v15，但 VirtualTerminal 有 POSIX/Windows 平台适配）
- 构建：`swift run`，无额外工具链
- 文档：Swift-DocC 插件（`swift-docc-plugin`）

## 目录职责
- `Sources/SwiftTUI/VirtualTerminal/` — 核心终端抽象层（输入解析、平台适配、差分渲染、缓冲区）
- `Sources/SwiftTUI/Views/` — SwiftUI 风格声明式视图（Button、Text、TextField、ScrollView、Stacks 等）
- `Sources/SwiftTUI/Controls/` — Control 基类和 Window
- `Sources/SwiftTUI/RunLoop/` — Application 主循环
- `Sources/SwiftTUI/PropertyWrappers/` — @State、@Binding、@Environment、@ObservedObject
- `Sources/SwiftTUI/Drawing/` — Layer 渲染
- `Examples/` — Numbers、ToDoList、Flags、Colors

## 核心接口
- `Application(rootView:).start()` — async，非阻塞启动
- `VTEvent` — 统一事件枚举（key / mouse / resize）
- `VTEventStream` — AsyncSequence 事件流
- `VTRenderer` — 差分渲染器，替代旧的 Renderer
- `Button` — 支持 `.init(action:hover:label:)` 和 `.init(_:hover:action:)`，handleMouseEvent 处理左键释放，handleEvent 处理回车/空格

## 工程约束
- API 尽可能贴近 SwiftUI
- README 为中文
- 交互以鼠标驱动为核心，键盘作为辅助
