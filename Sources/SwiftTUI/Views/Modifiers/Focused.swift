import Foundation

// MARK: - Public API

public extension View {
    /// Aligns with SwiftUI `View.focused(_:)` (macOS 12+).
    func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        FocusedBoolModifier(content: self, binding: condition)
    }

    /// Aligns with SwiftUI `View.focused(_:equals:)` (macOS 12+).
    func focused<Value: Hashable>(
        _ binding: FocusState<Value>.Binding,
        equals value: Value
    ) -> some View {
        FocusedEqualsModifier(content: self, binding: binding, equals: value)
    }

    /// Aligns with SwiftUI `View.defaultFocus(_:_:priority:)` (macOS 13+).
    func defaultFocus<V: Hashable>(
        _ binding: FocusState<V>.Binding,
        _ value: V,
        priority: DefaultFocusEvaluationPriority = .automatic
    ) -> some View {
        DefaultFocusModifier(content: self, binding: binding, value: value, priority: priority)
    }

    /// Aligns with SwiftUI `View.focusable(_:)` (macOS 12+; without deprecated onFocusChange).
    func focusable(_ isFocusable: Bool = true) -> some View {
        FocusableModifier(content: self, isFocusable: isFocusable)
    }
}

public struct DefaultFocusEvaluationPriority: Sendable, Equatable {
    public static let automatic = DefaultFocusEvaluationPriority(id: 0)
    public static let userInitiated = DefaultFocusEvaluationPriority(id: 1)
    private let id: Int
}

// MARK: - Bool focused

@MainActor
private struct FocusedBoolModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let binding: FocusState<Bool>.Binding

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as? FocusHostElement)?.installBool(binding)
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let host = control.parent as? FocusHostElement {
            host.installBool(binding)
            return host
        }
        let host = FocusHostElement()
        host.addSubview(control, at: 0)
        host.installBool(binding)
        node.elements?.add(host)
        return host
    }
}

// MARK: - Equals focused

@MainActor
private struct FocusedEqualsModifier<Content: View, Value: Hashable>: View, PrimitiveView, ModifierView {
    let content: Content
    let binding: FocusState<Value>.Binding
    let equals: Value

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as? FocusHostElement)?.installEquals(binding, equals: equals)
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let host = control.parent as? FocusHostElement {
            host.installEquals(binding, equals: equals)
            return host
        }
        let host = FocusHostElement()
        host.addSubview(control, at: 0)
        host.installEquals(binding, equals: equals)
        node.elements?.add(host)
        return host
    }
}

// MARK: - Focus host

@MainActor
private final class FocusHostElement: Element {
    private var registration: FocusRegistration?

    func installBool(_ binding: FocusState<Bool>.Binding) {
        install(
            reference: binding.reference,
            match: { ($0 as? Bool) == true },
            writeFocused: { binding.wrappedValue = true },
            writeUnfocused: { binding.wrappedValue = false }
        )
    }

    func installEquals<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals: Value) {
        let reset = binding.resetValue
        install(
            reference: binding.reference,
            match: { ($0 as? Value) == equals },
            writeFocused: { binding.wrappedValue = equals },
            writeUnfocused: { binding.wrappedValue = reset }
        )
    }

    private func install(
        reference: FocusStateReference,
        match: @escaping (Any) -> Bool,
        writeFocused: @escaping () -> Void,
        writeUnfocused: @escaping () -> Void
    ) {
        if let registration {
            FocusSystem.unregister(registration)
            if registration.element?.focusRegistration === registration {
                registration.element?.focusRegistration = nil
            }
        }
        guard let target else { return }
        let registration = FocusRegistration(
            reference: reference,
            control: target,
            match: match,
            writeFocused: writeFocused,
            writeUnfocused: writeUnfocused
        )
        self.registration = registration
        target.focusRegistration = registration
        FocusSystem.register(registration)
    }

    private var target: Element? {
        children.first?.firstSelectableElement ?? children.first
    }

    override func size(proposedSize: Size) -> Size {
        children.first?.size(proposedSize: proposedSize) ?? proposedSize
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children.first?.layout(size: size)
    }

    override var selectable: Bool { false }

    override var firstSelectableElement: Element? {
        children.first?.firstSelectableElement
    }

    override func willRemoveFromParent() {
        if let registration {
            FocusSystem.unregister(registration)
            if registration.element?.focusRegistration === registration {
                registration.element?.focusRegistration = nil
            }
            self.registration = nil
        }
        super.willRemoveFromParent()
    }
}

// MARK: - defaultFocus

@MainActor
private struct DefaultFocusModifier<Content: View, Value: Hashable>: View, PrimitiveView, ModifierView {
    let content: Content
    let binding: FocusState<Value>.Binding
    let value: Value
    let priority: DefaultFocusEvaluationPriority

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as? DefaultFocusElement<Value>)?.configure(binding: binding, value: value)
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let host = control.parent as? DefaultFocusElement<Value> {
            host.configure(binding: binding, value: value)
            return host
        }
        let host = DefaultFocusElement(binding: binding, value: value)
        host.addSubview(control, at: 0)
        node.elements?.add(host)
        return host
    }
}

@MainActor
private final class DefaultFocusElement<Value: Hashable>: Element {
    private var binding: FocusState<Value>.Binding
    private var value: Value
    private var didApply = false

    init(binding: FocusState<Value>.Binding, value: Value) {
        self.binding = binding
        self.value = value
    }

    func configure(binding: FocusState<Value>.Binding, value: Value) {
        self.binding = binding
        self.value = value
    }

    override func size(proposedSize: Size) -> Size {
        children.first?.size(proposedSize: proposedSize) ?? proposedSize
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children.first?.layout(size: size)
        guard !didApply else { return }
        didApply = true
        let binding = self.binding
        let value = self.value
        // Next host turn so the tree finishes this layout before stealing focus.
        if let clock = layer.rootRenderer?.application?.clock {
            clock.scheduleNextTurn { [weak self] in
                guard let self else { return }
                let window = self.root.window
                if window?.firstResponder == nil || window?.firstResponder?.canReceiveFocus != true {
                    binding.wrappedValue = value
                }
            }
        } else {
            let window = root.window
            if window?.firstResponder == nil || window?.firstResponder?.canReceiveFocus != true {
                binding.wrappedValue = value
            }
        }
    }

    override var firstSelectableElement: Element? {
        children.first?.firstSelectableElement
    }
}

// MARK: - focusable

@MainActor
private struct FocusableModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let isFocusable: Bool

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as? FocusableElement)?.isFocusable = isFocusable
            (control as? FocusableElement)?.applyFlag()
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let host = control.parent as? FocusableElement {
            host.isFocusable = isFocusable
            host.applyFlag()
            return host
        }
        let host = FocusableElement(isFocusable: isFocusable)
        host.addSubview(control, at: 0)
        host.applyFlag()
        node.elements?.add(host)
        return host
    }
}

@MainActor
private final class FocusableElement: Element {
    var isFocusable: Bool

    init(isFocusable: Bool) {
        self.isFocusable = isFocusable
    }

    func applyFlag() {
        let target = children.first?.firstSelectableElement ?? children.first
        target?.focusableFlag = isFocusable
        if !isFocusable, target?.isFirstResponder == true {
            target?.window?.setFirstResponder(target?.root.firstSelectableElement)
        }
    }

    override func size(proposedSize: Size) -> Size {
        children.first?.size(proposedSize: proposedSize) ?? proposedSize
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children.first?.layout(size: size)
    }

    override var firstSelectableElement: Element? {
        guard isFocusable else { return nil }
        return children.first?.firstSelectableElement
    }
}
