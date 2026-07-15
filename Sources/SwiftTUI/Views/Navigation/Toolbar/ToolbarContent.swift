import Foundation

// MARK: - Resolved storage

/// 导航栏三槽内容（按 pageID 存入 NavigationContext）。
@MainActor
struct NavigationToolbarContent {
    var leading: AnyView?
    var principal: AnyView?
    var trailing: AnyView?
    /// `.toolbarTitleMenu` / `ToolbarTitleMenu`：把 `navigationTitle` 变成可下拉菜单。
    var titleMenu: AnyView?

    static let empty = NavigationToolbarContent()

    mutating func append(_ view: AnyView, placement: ToolbarItemPlacement) {
        switch placement.slot {
        case .leading:
            leading = Self.merge(leading, view)
        case .principal:
            // 多个 principal：后者覆盖（对齐「替换 title」语义）
            principal = view
        case .trailing:
            trailing = Self.merge(trailing, view)
        }
    }

    private static func merge(_ existing: AnyView?, _ next: AnyView) -> AnyView {
        if let existing {
            return AnyView(HStack(spacing: 1) {
                existing
                next
            })
        }
        return next
    }
}

// MARK: - Protocol

@MainActor public protocol ToolbarContent {}

@MainActor
protocol _ToolbarContentCollectable {
    func collect(into storage: inout NavigationToolbarContent)
}

// MARK: - Empty

@MainActor public struct EmptyToolbarContent: ToolbarContent, _ToolbarContentCollectable {
    public init() {}
    func collect(into storage: inout NavigationToolbarContent) {}
}

// MARK: - ToolbarItem

@MainActor public struct ToolbarItem<ID, Content: View>: ToolbarContent, _ToolbarContentCollectable {
    let placement: ToolbarItemPlacement
    let content: Content

    func collect(into storage: inout NavigationToolbarContent) {
        storage.append(AnyView(content), placement: placement)
    }
}

extension ToolbarItem where ID == () {
    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }
}

// MARK: - ToolbarTitleMenu

/// 导航标题下拉菜单内容；与 `.toolbarTitleMenu` 等价，可写在 `.toolbar { }` 里。
@MainActor public struct ToolbarTitleMenu<Content: View>: ToolbarContent, _ToolbarContentCollectable {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func collect(into storage: inout NavigationToolbarContent) {
        storage.titleMenu = AnyView(content)
    }
}

// MARK: - ToolbarItemGroup

/// 同一 placement 下的一组控件；TUI 内合成一个 `HStack`。
@MainActor public struct ToolbarItemGroup<Content: View>: ToolbarContent, _ToolbarContentCollectable {
    let placement: ToolbarItemPlacement
    let content: Content

    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }

    func collect(into storage: inout NavigationToolbarContent) {
        storage.append(
            AnyView(HStack(spacing: 1) { content }),
            placement: placement
        )
    }
}

// MARK: - Tuple / Conditional

@MainActor public struct TupleToolbarContent2<C0: ToolbarContent, C1: ToolbarContent>: ToolbarContent, _ToolbarContentCollectable {
    let c0: C0
    let c1: C1
    func collect(into storage: inout NavigationToolbarContent) {
        (c0 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c1 as? any _ToolbarContentCollectable)?.collect(into: &storage)
    }
}

@MainActor public struct TupleToolbarContent3<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>: ToolbarContent, _ToolbarContentCollectable {
    let c0: C0
    let c1: C1
    let c2: C2
    func collect(into storage: inout NavigationToolbarContent) {
        (c0 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c1 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c2 as? any _ToolbarContentCollectable)?.collect(into: &storage)
    }
}

@MainActor public struct TupleToolbarContent4<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>: ToolbarContent, _ToolbarContentCollectable {
    let c0: C0
    let c1: C1
    let c2: C2
    let c3: C3
    func collect(into storage: inout NavigationToolbarContent) {
        (c0 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c1 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c2 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c3 as? any _ToolbarContentCollectable)?.collect(into: &storage)
    }
}

@MainActor public struct TupleToolbarContent5<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent>: ToolbarContent, _ToolbarContentCollectable {
    let c0: C0
    let c1: C1
    let c2: C2
    let c3: C3
    let c4: C4
    func collect(into storage: inout NavigationToolbarContent) {
        (c0 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c1 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c2 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c3 as? any _ToolbarContentCollectable)?.collect(into: &storage)
        (c4 as? any _ToolbarContentCollectable)?.collect(into: &storage)
    }
}

@MainActor public struct ConditionalToolbarContent<TrueContent: ToolbarContent, FalseContent: ToolbarContent>: ToolbarContent, _ToolbarContentCollectable {
    enum Storage {
        case first(TrueContent)
        case second(FalseContent)
    }
    let storage: Storage

    func collect(into storage: inout NavigationToolbarContent) {
        switch self.storage {
        case .first(let c):
            (c as? any _ToolbarContentCollectable)?.collect(into: &storage)
        case .second(let c):
            (c as? any _ToolbarContentCollectable)?.collect(into: &storage)
        }
    }
}

// MARK: - Builder

@resultBuilder
@MainActor public struct ToolbarContentBuilder {
    public static func buildBlock() -> EmptyToolbarContent { EmptyToolbarContent() }

    public static func buildBlock<Content: ToolbarContent>(_ content: Content) -> Content { content }

    public static func buildOptional<Content: ToolbarContent>(_ content: Content?) -> ConditionalToolbarContent<Content, EmptyToolbarContent> {
        if let content {
            return ConditionalToolbarContent(storage: .first(content))
        }
        return ConditionalToolbarContent(storage: .second(EmptyToolbarContent()))
    }

    public static func buildIf<Content: ToolbarContent>(_ content: Content?) -> ConditionalToolbarContent<Content, EmptyToolbarContent> {
        buildOptional(content)
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        first: TrueContent
    ) -> ConditionalToolbarContent<TrueContent, FalseContent> {
        ConditionalToolbarContent(storage: .first(first))
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        second: FalseContent
    ) -> ConditionalToolbarContent<TrueContent, FalseContent> {
        ConditionalToolbarContent(storage: .second(second))
    }

    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent>(
        _ c0: C0, _ c1: C1
    ) -> TupleToolbarContent2<C0, C1> {
        TupleToolbarContent2(c0: c0, c1: c1)
    }

    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleToolbarContent3<C0, C1, C2> {
        TupleToolbarContent3(c0: c0, c1: c1, c2: c2)
    }

    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleToolbarContent4<C0, C1, C2, C3> {
        TupleToolbarContent4(c0: c0, c1: c1, c2: c2, c3: c3)
    }

    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleToolbarContent5<C0, C1, C2, C3, C4> {
        TupleToolbarContent5(c0: c0, c1: c1, c2: c2, c3: c3, c4: c4)
    }
}
