import SwiftTUI
import Foundation

// MARK: - 共享数据

struct MenuItem: Hashable {
    let id: Int
    let title: String
    let description: String
}

let menuItems: [MenuItem] = [
    MenuItem(id: 1, title: "Swift 语法", description: "Swift 的基础语法指南"),
    MenuItem(id: 2, title: "SwiftUI 视图", description: "如何构建漂亮的 SwiftUI 视图"),
    MenuItem(id: 3, title: "TUI 开发", description: "用 SwiftTUI 写终端应用"),
]

// MARK: - 通用详情页

@MainActor
struct DetailView: View {
    let item: MenuItem

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.description)
                .foregroundColor(.cyan)
            Text("id: \(item.id)")
                .foregroundColor(.yellow)
            NavigationLink("继续深入 >", value: "sub-\(item.id)")
        }
        .padding()
        .navigationTitle(item.title)
    }
}

@MainActor
struct SubDetailView: View {
    let id: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("深入页面: \(id)")
            Text("可用返回按钮或 dismiss 回到上一页。")
                .foregroundColor(.cyan)
        }
        .padding()
        .navigationTitle("深入")
    }
}

@MainActor
struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("通过 NavigationLink(destination:) 打开，")
            Text("无需 .navigationDestination。")
                .foregroundColor(.cyan)
        }
        .padding()
        .navigationTitle("关于")
    }
}

// MARK: - Demo 1: 无 path（内部自动管理）

@MainActor
struct BasicNavigationDemo: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("NavigationStack { } 无外部 path")
                    .foregroundColor(.yellow)

                ForEach(menuItems, id: \.id) { item in
                    NavigationLink(item.title, value: item)
                }

                NavigationLink("关于页面") {
                    AboutView()
                }
            }
            .padding()
            .navigationDestination(for: MenuItem.self) { item in
                DetailView(item: item)
            }
            .navigationDestination(for: String.self) { id in
                SubDetailView(id: id)
            }
            .navigationTitle("Basic")
        }
    }
}

// MARK: - Demo 2: NavigationPath binding（异构栈）

/// SwiftUI: `NavigationStack(path: $path)` where `path: NavigationPath`
/// 可 append 任意 Hashable（MenuItem、String…）。
@MainActor
struct NavigationPathDemo: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading) {
                Text("NavigationPath 绑定")
                    .foregroundColor(.yellow)
                Text("path.count = \(path.count)")
                    .foregroundColor(.cyan)

                ForEach(menuItems, id: \.id) { item in
                    NavigationLink(item.title, value: item)
                }

                Button("path.append(MenuItem)") {
                    path.append(menuItems[0])
                }
                Button("path.append(String)") {
                    path.append("from-path")
                }
                Button("连续 push 两层") {
                    path.append(menuItems[1])
                    path.append("sub-\(menuItems[1].id)")
                }
                if !path.isEmpty {
                    Button("path.removeLast()") {
                        path.removeLast()
                    }
                    Button("回到根 path.removeLast(count)") {
                        path.removeLast(path.count)
                    }
                }
            }
            .padding()
            .navigationDestination(for: MenuItem.self) { item in
                DetailView(item: item)
            }
            .navigationDestination(for: String.self) { id in
                SubDetailView(id: id)
            }
            .navigationTitle("Path")
        }
    }
}

// MARK: - Demo 3: Typed path `[MenuItem]`

/// SwiftUI: `NavigationStack(path: $path)` where `path: [Element]` 且 `Element: Hashable`
/// 同质栈，只能 push 同一种类型（不是 `[AnyHashable]`，而是具体类型的数组）。
@MainActor
struct TypedPathDemo: View {
    @State private var path: [MenuItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading) {
                Text("Typed path: [MenuItem]")
                    .foregroundColor(.yellow)
                Text("path.count = \(path.count)")
                    .foregroundColor(.cyan)

                ForEach(menuItems, id: \.id) { item in
                    NavigationLink(item.title, value: item)
                }

                Button("path.append(...)") {
                    path.append(menuItems[2])
                }
                if !path.isEmpty {
                    Button("path.removeLast()") {
                        path.removeLast()
                    }
                    Button("path.removeAll() 回根") {
                        path.removeAll()
                    }
                }
            }
            .padding()
            .navigationDestination(for: MenuItem.self) { item in
                VStack(alignment: .leading) {
                    Text(item.description)
                        .foregroundColor(.cyan)
                    Text("typed path 深度: \(path.count)")
                        .foregroundColor(.yellow)
                    Button("再 push 一项") {
                        if let next = menuItems.first(where: { !path.contains($0) }) {
                            path.append(next)
                        }
                    }
                }
                .padding()
                .navigationTitle(item.title)
            }
            .navigationTitle("Typed")
        }
    }
}

// MARK: - 入口：选择演示

@MainActor
struct RootView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("SwiftTUI NavigationStack")
                    .bold()
                Text("选择一种 path 用法：")
                    .foregroundColor(.yellow)

                NavigationLink("1. 无 path（内部管理）") {
                    BasicNavigationDemo()
                }
                NavigationLink("2. NavigationPath 绑定") {
                    NavigationPathDemo()
                }
                NavigationLink("3. Typed path [MenuItem]") {
                    TypedPathDemo()
                }
            }
            .padding()
            .navigationTitle("Demos")
        }
    }
}

// MARK: - main
let app = Application(rootView: RootView())

try? await app.start()
