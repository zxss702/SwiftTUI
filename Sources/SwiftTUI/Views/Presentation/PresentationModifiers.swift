import Foundation

// MARK: - Shared presentation sync (sheet / alert modal)

enum PresentationKind {
    case sheet
    case alert
}

/// `isPresented` 绑定的 sheet / alert。
@MainActor
struct PresentationBindingModifier<Content: View, Presented: View>: View {
    let kind: PresentationKind
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let presented: () -> Presented
    let content: Content

    @Environment(PopupPresenter.self) private var presenter
    @State private var sessionID: UUID?

    var body: some View {
        let _ = sync()
        content
    }

    private func sync() {
        if isPresented {
            let stillOurs = sessionID != nil && presenter.presentationID == sessionID
            if !stillOurs {
                let id = UUID()
                sessionID = id
                let binding = $isPresented
                let onDismiss = self.onDismiss
                let finish = {
                    if binding.wrappedValue { binding.wrappedValue = false }
                    onDismiss?()
                }
                switch kind {
                case .sheet:
                    presenter.presentSheet(onDismiss: {
                        sessionID = nil
                        finish()
                    }, content: presented)
                case .alert:
                    presenter.presentAlert(onDismiss: {
                        sessionID = nil
                        finish()
                    }, content: presented)
                }
                // present 会换新 presentationID；记下本次
                sessionID = presenter.presentationID
            }
        } else if sessionID != nil {
            sessionID = nil
            if presenter.isPresented {
                presenter.dismiss()
            }
        }
    }
}

/// `item:` 绑定的 sheet。
@MainActor
struct PresentationItemModifier<Content: View, Item: Identifiable, Presented: View>: View {
    let kind: PresentationKind
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let presented: (Item) -> Presented
    let content: Content

    @Environment(PopupPresenter.self) private var presenter
    @State private var sessionID: UUID?
    @State private var presentedID: Item.ID?

    var body: some View {
        let _ = sync()
        content
    }

    private func sync() {
        if let value = item {
            let stillOurs = sessionID != nil
                && presenter.presentationID == sessionID
                && presentedID == value.id
            if !stillOurs {
                if sessionID != nil {
                    presenter.dismiss()
                }
                presentedID = value.id
                let binding = $item
                let onDismiss = self.onDismiss
                let finish = {
                    presentedID = nil
                    if binding.wrappedValue != nil { binding.wrappedValue = nil }
                    onDismiss?()
                }
                switch kind {
                case .sheet:
                    presenter.presentSheet(onDismiss: {
                        sessionID = nil
                        finish()
                    }) {
                        presented(value)
                    }
                case .alert:
                    presenter.presentAlert(onDismiss: {
                        sessionID = nil
                        finish()
                    }) {
                        presented(value)
                    }
                }
                sessionID = presenter.presentationID
            }
        } else if sessionID != nil {
            sessionID = nil
            presentedID = nil
            if presenter.isPresented {
                presenter.dismiss()
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
            if control.token == nil {
                let token = UUID()
                control.token = token
                let body = presented
                presenter.presentPopover(anchor: control.absoluteFrame, onDismiss: {
                    control.token = nil
                    if binding.wrappedValue { binding.wrappedValue = false }
                }) {
                    body()
                }
            }
        } else if control.token != nil {
            control.token = nil
            if presenter.isPresented {
                presenter.dismiss()
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
            if control.token == nil {
                control.token = UUID()
                presenter.presentPopover(anchor: control.absoluteFrame, onDismiss: {
                    control.token = nil
                    if binding.wrappedValue != nil { binding.wrappedValue = nil }
                }) {
                    presented(value)
                }
            }
        } else if control.token != nil {
            control.token = nil
            if presenter.isPresented {
                presenter.dismiss()
            }
        }
    }
}

@MainActor
private final class PopoverHostControl: Control {
    var contentControl: Control!
    var token: UUID?

    override func size(proposedSize: Size) -> Size {
        contentControl.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        contentControl.layout(size: size)
    }
}
