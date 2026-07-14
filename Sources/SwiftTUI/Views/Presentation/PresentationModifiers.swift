import Foundation

// MARK: - Shared presentation sync (sheet / alert modal)

enum PresentationKind {
    case sheet
    case alert
}

/// `isPresented` 绑定的 sheet / alert。
@MainActor
struct PresentationBindingModifier<Content: View, Presented: View>: View, PrimitiveView {
    let kind: PresentationKind
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let presented: () -> Presented
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        sync(node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        sync(node)
    }

    private func sync(_ node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let presenter = env[PopupPresenter.self] else { return }

        let sessionKey = "presentation.sessionID"
        if isPresented.wrappedValue {
            let sessionID = node.storage[sessionKey] as? UUID
            let stillOurs = sessionID.map { presenter.contains($0) } ?? false
            if stillOurs, let sessionID {
                // 宿主状态变了但 session 仍在：刷新 makePanel，让嵌套 sheet 等读到最新 Binding。
                let presented = self.presented
                let kind = self.kind
                presenter.updateMakePanel(id: sessionID) { [weak presenter] in
                    Self.makePanel(
                        kind: kind,
                        id: sessionID,
                        presenter: presenter,
                        presented: presented
                    )
                }
            } else if !stillOurs {
                let binding = isPresented
                let onDismiss = self.onDismiss
                let finish = {
                    if binding.wrappedValue { binding.wrappedValue = false }
                    onDismiss?()
                }
                let id: UUID
                switch kind {
                case .sheet:
                    id = presenter.presentSheet(environmentSource: node, onDismiss: {
                        node.storage[sessionKey] = nil
                        finish()
                    }, content: presented)
                case .alert:
                    id = presenter.presentAlert(environmentSource: node, onDismiss: {
                        node.storage[sessionKey] = nil
                        finish()
                    }, content: presented)
                }
                node.storage[sessionKey] = id
            }
        } else if let id = node.storage[sessionKey] as? UUID {
            // isPresented → false：先清 session，再 dismiss，避免 onDismiss/finish 重入时误判 stillOurs。
            node.storage[sessionKey] = nil
            if presenter.contains(id) {
                presenter.dismiss(id: id)
            }
        }
    }

    private static func makePanel(
        kind: PresentationKind,
        id: UUID,
        presenter: PopupPresenter?,
        presented: @escaping () -> Presented
    ) -> AnyView {
        switch kind {
        case .sheet:
            return AnyView(SheetPanel(content: presented().environment(\.dismiss, DismissAction {
                presenter?.dismiss(id: id)
            })))
        case .alert:
            return AnyView(
                AlertPanel(content: presented())
                    .environment(\.dismiss, DismissAction { presenter?.dismiss(id: id) })
                    .environment(\.buttonDismissesPresentation, true)
            )
        }
    }
}

/// `item:` 绑定的 sheet。
@MainActor
struct PresentationItemModifier<Content: View, Item: Identifiable, Presented: View>: View, PrimitiveView {
    let kind: PresentationKind
    let item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let presented: (Item) -> Presented
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        sync(node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        sync(node)
    }

    private func sync(_ node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let presenter = env[PopupPresenter.self] else { return }

        let sessionKey = "presentation.sessionID"
        let presentedIDKey = "presentation.presentedID"

        if let value = item.wrappedValue {
            let sessionID = node.storage[sessionKey] as? UUID
            let presentedID = node.storage[presentedIDKey] as? AnyHashable
            let stillOurs = (sessionID.map { presenter.contains($0) } ?? false)
                && presentedID == AnyHashable(value.id)
            if stillOurs, let sessionID {
                let presented = self.presented
                let kind = self.kind
                let current = value
                presenter.updateMakePanel(id: sessionID) { [weak presenter] in
                    Self.makePanel(
                        kind: kind,
                        id: sessionID,
                        presenter: presenter,
                        presented: { presented(current) }
                    )
                }
            } else if !stillOurs {
                if let old = sessionID, presenter.contains(old) {
                    presenter.dismiss(id: old)
                }
                node.storage[presentedIDKey] = AnyHashable(value.id)
                let binding = item
                let onDismiss = self.onDismiss
                let finish = {
                    node.storage[presentedIDKey] = nil
                    if binding.wrappedValue != nil { binding.wrappedValue = nil }
                    onDismiss?()
                }
                let id: UUID
                switch kind {
                case .sheet:
                    id = presenter.presentSheet(environmentSource: node, onDismiss: {
                        node.storage[sessionKey] = nil
                        finish()
                    }) {
                        presented(value)
                    }
                case .alert:
                    id = presenter.presentAlert(environmentSource: node, onDismiss: {
                        node.storage[sessionKey] = nil
                        finish()
                    }) {
                        presented(value)
                    }
                }
                node.storage[sessionKey] = id
            }
        } else if let id = node.storage[sessionKey] as? UUID {
            node.storage[sessionKey] = nil
            node.storage[presentedIDKey] = nil
            if presenter.contains(id) {
                presenter.dismiss(id: id)
            }
        }
    }

    private static func makePanel(
        kind: PresentationKind,
        id: UUID,
        presenter: PopupPresenter?,
        presented: @escaping () -> Presented
    ) -> AnyView {
        switch kind {
        case .sheet:
            return AnyView(SheetPanel(content: presented().environment(\.dismiss, DismissAction {
                presenter?.dismiss(id: id)
            })))
        case .alert:
            return AnyView(
                AlertPanel(content: presented())
                    .environment(\.dismiss, DismissAction { presenter?.dismiss(id: id) })
                    .environment(\.buttonDismissesPresentation, true)
            )
        }
    }
}

// MARK: - Popover（锚点为修饰视图的 absoluteFrame）

@MainActor
struct PopoverBindingModifier<Content: View, Presented: View>: View, PrimitiveView {
    let isPresented: Binding<Bool>
    let presented: () -> Presented
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        let control = PopoverHostElement()
        control.contentElement = node.children[0].element(at: 0)
        control.addSubview(control.contentElement, at: 0)
        node.element = control
        sync(node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! PopoverHostElement
        let newContent = node.children[0].element(at: 0)
        control.contentElement = newContent
        control.syncChild(newContent)
        sync(node)
    }

    private func sync(_ node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let presenter = env[PopupPresenter.self] else { return }
        let control = node.element as! PopoverHostElement
        let binding = isPresented

        if binding.wrappedValue {
            let stillOurs = control.token.map { presenter.contains($0) } ?? false
            if stillOurs, let id = control.token {
                let body = presented
                let anchor = control.absoluteFrame
                if let record = presenter.record(id: id) {
                    record.anchor = anchor
                }
                presenter.updateMakePanel(id: id) { [weak presenter] in
                    AnyView(PopoverPanel(content: body().environment(\.dismiss, DismissAction {
                        presenter?.dismiss(id: id)
                    })))
                }
            } else if !stillOurs {
                let body = presented
                let id = presenter.presentPopover(
                    anchor: control.absoluteFrame,
                    environmentSource: node,
                    onDismiss: {
                        control.token = nil
                        if binding.wrappedValue { binding.wrappedValue = false }
                    }
                ) {
                    body()
                }
                control.token = id
            }
        } else if let id = control.token {
            control.token = nil
            if presenter.contains(id) {
                presenter.dismiss(id: id)
            }
        }
    }
}

@MainActor
struct PopoverItemModifier<Content: View, Item: Identifiable, Presented: View>: View, PrimitiveView {
    let item: Binding<Item?>
    let presented: (Item) -> Presented
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        let control = PopoverHostElement()
        control.contentElement = node.children[0].element(at: 0)
        control.addSubview(control.contentElement, at: 0)
        node.element = control
        sync(node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! PopoverHostElement
        let newContent = node.children[0].element(at: 0)
        control.contentElement = newContent
        control.syncChild(newContent)
        sync(node)
    }

    private func sync(_ node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let presenter = env[PopupPresenter.self] else { return }
        let control = node.element as! PopoverHostElement
        let binding = item

        if let value = binding.wrappedValue {
            let stillOurs = (control.token.map { presenter.contains($0) } ?? false)
                && control.presentedID == AnyHashable(value.id)
            if stillOurs, let id = control.token {
                let presented = self.presented
                let current = value
                let anchor = control.absoluteFrame
                if let record = presenter.record(id: id) {
                    record.anchor = anchor
                }
                presenter.updateMakePanel(id: id) { [weak presenter] in
                    AnyView(PopoverPanel(content: presented(current).environment(\.dismiss, DismissAction {
                        presenter?.dismiss(id: id)
                    })))
                }
            } else if !stillOurs {
                if let old = control.token, presenter.contains(old) {
                    presenter.dismiss(id: old)
                }
                control.presentedID = AnyHashable(value.id)
                let id = presenter.presentPopover(
                    anchor: control.absoluteFrame,
                    environmentSource: node,
                    onDismiss: {
                        control.token = nil
                        control.presentedID = nil
                        if binding.wrappedValue != nil { binding.wrappedValue = nil }
                    }
                ) {
                    presented(value)
                }
                control.token = id
            }
        } else if let id = control.token {
            control.token = nil
            control.presentedID = nil
            if presenter.contains(id) {
                presenter.dismiss(id: id)
            }
        }
    }
}

@MainActor
private final class PopoverHostElement: Element {
    var contentElement: Element!
    var token: UUID?
    var presentedID: AnyHashable?

    override func size(proposedSize: Size) -> Size {
        contentElement.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        contentElement.layout(size: size)
    }
}
