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
            let sessionID = node.state[sessionKey] as? UUID
            let stillOurs = sessionID.map { presenter.contains($0) } ?? false
            if !stillOurs {
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
                        node.state[sessionKey] = nil
                        finish()
                    }, content: presented)
                case .alert:
                    id = presenter.presentAlert(environmentSource: node, onDismiss: {
                        node.state[sessionKey] = nil
                        finish()
                    }, content: presented)
                }
                node.state[sessionKey] = id
            }
        } else if let id = node.state[sessionKey] as? UUID {
            node.state[sessionKey] = nil
            if presenter.contains(id) {
                presenter.dismiss(id: id)
            }
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
            let sessionID = node.state[sessionKey] as? UUID
            let presentedID = node.state[presentedIDKey] as? AnyHashable
            let stillOurs = (sessionID.map { presenter.contains($0) } ?? false)
                && presentedID == AnyHashable(value.id)
            if !stillOurs {
                if let old = sessionID, presenter.contains(old) {
                    presenter.dismiss(id: old)
                }
                node.state[presentedIDKey] = AnyHashable(value.id)
                let binding = item
                let onDismiss = self.onDismiss
                let finish = {
                    node.state[presentedIDKey] = nil
                    if binding.wrappedValue != nil { binding.wrappedValue = nil }
                    onDismiss?()
                }
                let id: UUID
                switch kind {
                case .sheet:
                    id = presenter.presentSheet(environmentSource: node, onDismiss: {
                        node.state[sessionKey] = nil
                        finish()
                    }) {
                        presented(value)
                    }
                case .alert:
                    id = presenter.presentAlert(environmentSource: node, onDismiss: {
                        node.state[sessionKey] = nil
                        finish()
                    }) {
                        presented(value)
                    }
                }
                node.state[sessionKey] = id
            }
        } else if let id = node.state[sessionKey] as? UUID {
            node.state[sessionKey] = nil
            node.state[presentedIDKey] = nil
            if presenter.contains(id) {
                presenter.dismiss(id: id)
            }
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
        let control = PopoverHostControl()
        control.contentControl = node.children[0].control(at: 0)
        control.addSubview(control.contentControl, at: 0)
        node.control = control
        sync(node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.control as! PopoverHostControl
        control.contentControl = node.children[0].control(at: 0)
        sync(node)
    }

    private func sync(_ node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let presenter = env[PopupPresenter.self] else { return }
        let control = node.control as! PopoverHostControl
        let binding = isPresented

        if binding.wrappedValue {
            let stillOurs = control.token.map { presenter.contains($0) } ?? false
            if !stillOurs {
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
        let control = PopoverHostControl()
        control.contentControl = node.children[0].control(at: 0)
        control.addSubview(control.contentControl, at: 0)
        node.control = control
        sync(node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.control as! PopoverHostControl
        control.contentControl = node.children[0].control(at: 0)
        sync(node)
    }

    private func sync(_ node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let presenter = env[PopupPresenter.self] else { return }
        let control = node.control as! PopoverHostControl
        let binding = item

        if let value = binding.wrappedValue {
            let stillOurs = (control.token.map { presenter.contains($0) } ?? false)
                && control.presentedID == AnyHashable(value.id)
            if !stillOurs {
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
private final class PopoverHostControl: Control {
    var contentControl: Control!
    var token: UUID?
    var presentedID: AnyHashable?

    override func size(proposedSize: Size) -> Size {
        contentControl.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        contentControl.layout(size: size)
    }
}
