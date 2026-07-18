import Foundation

/// 只读取「可用宽度」的轻量布局容器，用于需要按宽度自定义排版的内容（如 Markdown
/// 的代码块 / 表格 / 分割线）。
///
/// 相比 `GeometryReader`：
/// - 只关心宽度，不因高度探测而重建；
/// - 布局用的有限宽度真正变化时才重建子树；`.infinity` / `0` 这类测量探测
///   （来自 stack 排序的 flexibility）不触发重建，直接用上次的宽度测量。
///
/// 这样在滚动新挂载行、以及排序测量时，避免了 `GeometryReader` 反复以「垃圾宽度」
/// 重建整棵子树的开销。纯 `Node`/`Element`，跨平台安全。
@MainActor public struct WidthReader<Content: View>: View, PrimitiveView {
    let content: (Int) -> Content

    public init(@ViewBuilder content: @escaping (Int) -> Content) {
        self.content = content
    }

    /// 最近一次构建子树所用的有限宽度。
    @State private var width: Int = 1

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupStateProperties(node: node)
        node.addNode(at: 0, Node(view: VStack(content: content(max(width, 1)))))
        let element = WidthReaderElement(width: _width)
        element.node = node
        element.rebuild = { [content] w in VStack(content: content(w)).view }
        node.element = element
        element.addSubview(node.children[0].element(at: 0), at: 0)
    }

    func updateNode(_ node: Node) {
        setupStateProperties(node: node)
        node.view = self
        let element = node.element as! WidthReaderElement
        element.node = node
        element.rebuild = { [content] w in VStack(content: content(w)).view }
        node.children[0].update(using: VStack(content: content(max(width, 1))))
        element.syncChildElement()
    }

    private final class WidthReaderElement: Element {
        let width: State<Int>
        weak var node: Node?
        var rebuild: ((Int) -> GenericView)?
        /// 已构建子树的宽度；-1 表示尚未按真实宽度构建。
        private var builtWidth: Int = -1

        init(width: State<Int>) {
            self.width = width
        }

        override func size(proposedSize: Size) -> Size {
            // ∞ 宽度探测（水平 flexibility 的 max）：用当前已构建宽度测量，不重建。
            if proposedSize.width == .infinity {
                let childSize = measureChild(atWidth: max(builtWidth, 1), height: proposedSize.height)
                return Size(width: childSize.width, height: childSize.height)
            }
            // 0 宽度探测（水平 flexibility 的 min）：内容完全弹性，直接报 0 宽不重建。
            if proposedSize.width <= 0 {
                let childSize = measureChild(atWidth: max(builtWidth, 1), height: proposedSize.height)
                return Size(width: 0, height: childSize.height)
            }
            let w = max(proposedSize.width.intValue, 1)
            ensureBuilt(width: w)
            let childSize = measureChild(atWidth: w, height: proposedSize.height)
            // 贴合内容：按换行后的实际宽度报告，不撑满建议宽度（对齐 SwiftUI Text/Markdown）。
            return Size(width: childSize.width, height: childSize.height)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            // 换行宽度沿用 size() 时记录的可用宽度；不要用 layout 分到的内容宽去 rebuild，
            // 否则短气泡会对长文错误地按窄宽重新换行。
            guard !children.isEmpty else { return }
            let wrapWidth = max(builtWidth, 1)
            let proposedHeight: Extended = size.height == .infinity ? .infinity : size.height
            let childSize = children[0].size(
                proposedSize: Size(width: Extended(wrapWidth), height: proposedHeight)
            )
            children[0].layout(size: childSize)
        }

        private func measureChild(atWidth w: Int, height: Extended) -> Size {
            guard !children.isEmpty else { return .zero }
            let childHeight: Extended = height == .infinity ? .infinity : height
            return children[0].size(proposedSize: Size(width: Extended(w), height: childHeight))
        }

        /// 仅当有限宽度真正变化时才重建子树。
        private func ensureBuilt(width w: Int) {
            guard w != builtWidth else { return }
            builtWidth = w
            width.setValue(w, invalidate: false)
            guard let node, let rebuild, !node.children.isEmpty else { return }
            node.children[0].update(using: rebuild(w))
            syncChildElement()
        }

        func syncChildElement() {
            guard let node, !node.children.isEmpty else { return }
            syncChild(node.children[0].element(at: 0))
        }
    }
}
