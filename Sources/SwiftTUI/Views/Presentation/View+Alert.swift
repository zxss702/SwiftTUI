import Foundation

// MARK: - alert（现行 API：actions / message，无旧 Alert 结构体）

public extension View {
    func alert<A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> A
    ) -> some View {
        alert(title, isPresented: isPresented, actions: actions, message: { EmptyView() })
    }

    func alert<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> A,
        @ViewBuilder message: @escaping () -> M
    ) -> some View {
        PresentationBindingModifier(
            kind: .alert,
            isPresented: isPresented,
            onDismiss: nil,
            presented: {
                AlertContent(title: title, message: message(), actions: actions())
            },
            content: self
        )
    }

    func alert<A: View, T>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> A
    ) -> some View {
        alert(title, isPresented: isPresented, presenting: data, actions: actions, message: { _ in EmptyView() })
    }

    func alert<A: View, M: View, T>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> A,
        @ViewBuilder message: @escaping (T) -> M
    ) -> some View {
        let presented = Binding<Bool>(
            get: { isPresented.wrappedValue && data != nil },
            set: { newValue in
                if !newValue { isPresented.wrappedValue = false }
            }
        )
        return PresentationBindingModifier(
            kind: .alert,
            isPresented: presented,
            onDismiss: nil,
            presented: {
                AlertPresentingContent(
                    title: title,
                    data: data,
                    actions: actions,
                    message: message
                )
            },
            content: self
        )
    }

    func alert<E: LocalizedError, A: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: @escaping () -> A
    ) -> some View {
        alert(
            error?.errorDescription ?? "Error",
            isPresented: isPresented,
            presenting: error,
            actions: { _ in actions() },
            message: { err in Text(err.recoverySuggestion ?? err.failureReason ?? "") }
        )
    }

    func alert<E: LocalizedError, A: View, M: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: @escaping (E) -> A,
        @ViewBuilder message: @escaping (E) -> M
    ) -> some View {
        alert(
            error?.errorDescription ?? "Error",
            isPresented: isPresented,
            presenting: error,
            actions: actions,
            message: message
        )
    }
}

// MARK: - Alert chrome

/// 宽度由标题/正文决定；按钮行均分该宽度（先声明的在左，如 OK | Cancel），不撑满窗口。
@MainActor
struct AlertContent<Message: View, Actions: View>: View, PrimitiveView, LayoutRootView {
    let title: String
    let message: Message
    let actions: Actions

    static var size: Int? { 1 }

    private func makeHeader() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).bold()
            message
        }
    }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: makeHeader().view))
        node.addNode(at: 1, Node(view: actions.bold().view))
        node.control = AlertContentControl()
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: makeHeader().view)
        node.children[1].update(using: actions.bold().view)
        let control = node.control as! AlertContentControl
        control.headerControl = node.children[0].control(at: 0)
    }

    func loadData(node: Node) {
        let control = node.control as! AlertContentControl
        control.headerControl = node.children[0].control(at: 0)
        control.addSubview(control.headerControl, at: 0)
        for i in 0 ..< node.children[1].size {
            control.addSubview(node.children[1].control(at: i), at: i + 1)
        }
    }

    func insertControl(at index: Int, node: Node) {
        let control = node.control as! AlertContentControl
        if index == 0 { return }
        control.addSubview(node.children[1].control(at: index - 1), at: index)
    }

    func removeControl(at index: Int, node: Node) {
        let control = node.control as! AlertContentControl
        if index == 0 { return }
        control.removeSubview(at: index)
    }
}

@MainActor
private final class AlertContentControl: Control {
    var headerControl: Control!
    private let actionSpacing: Extended = 1

    private var actionControls: [Control] {
        Array(children.dropFirst())
    }

    override func size(proposedSize: Size) -> Size {
        let headerSize = headerControl.size(
            proposedSize: Size(width: proposedSize.width, height: proposedSize.height)
        )

        let actions = actionControls
        var actionsWidth: Extended = 0
        var actionsHeight: Extended = 0
        for (i, action) in actions.enumerated() {
            let s = action.size(proposedSize: Size(width: .infinity, height: proposedSize.height))
            actionsWidth += s.width
            if i > 0 { actionsWidth += actionSpacing }
            actionsHeight = max(actionsHeight, s.height)
        }

        let width = max(headerSize.width, actionsWidth)
        var height = headerSize.height
        if !actions.isEmpty {
            height += actionsHeight
        }
        return Size(width: width, height: height)
    }

    override func layout(size: Size) {
        super.layout(size: size)

        let headerHeight = headerControl.size(
            proposedSize: Size(width: size.width, height: size.height)
        ).height
        headerControl.layout(size: Size(width: size.width, height: headerHeight))
        headerControl.layer.frame.position = .zero

        let actions = actionControls
        guard !actions.isEmpty else { return }

        let count = Extended(actions.count)
        let totalSpacing = actionSpacing * Extended(max(0, actions.count - 1))
        let eachWidth = max(Extended(1), (size.width - totalSpacing) / count)
        var column: Extended = 0
        let line = headerHeight

        for action in actions {
            let actionHeight = max(
                Extended(1),
                action.size(proposedSize: Size(width: eachWidth, height: size.height)).height
            )
            action.layout(size: Size(width: eachWidth, height: actionHeight))
            action.layer.frame.position = Position(column: column, line: line)
            column += eachWidth + actionSpacing
        }
    }
}

@MainActor
private struct AlertPresentingContent<T, A: View, M: View>: View {
    let title: String
    let data: T?
    let actions: (T) -> A
    let message: (T) -> M

    var body: some View {
        if let data {
            AlertContent(title: title, message: message(data), actions: actions(data))
        } else {
            EmptyView()
        }
    }
}
