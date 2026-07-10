import Foundation

public extension View {
    /// 视图出现时启动异步任务；消失或 `id` 变化时取消。
    func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        task(id: 0 as UInt8, priority: priority, action)
    }

    func task<T: Equatable>(
        id value: T,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        TaskModifier(content: self, id: AnyEquatable(value), priority: priority, action: action)
    }
}

private struct AnyEquatable: Equatable {
    private let value: Any
    private let equals: (Any) -> Bool

    init<T: Equatable>(_ value: T) {
        self.value = value
        self.equals = { other in
            (other as? T) == value
        }
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        lhs.equals(rhs.value)
    }
}

@MainActor
private struct TaskModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let id: AnyEquatable
    let priority: TaskPriority
    let action: @Sendable () async -> Void

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.controls = WeakSet<Control>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.controls?.values ?? [] {
            let control = control as! TaskControl
            control.update(id: id, priority: priority, action: action)
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let existing = control.parent as? TaskControl {
            existing.update(id: id, priority: priority, action: action)
            return existing
        }
        let wrapper = TaskControl(id: id, priority: priority, action: action)
        wrapper.addSubview(control, at: 0)
        node.controls?.add(wrapper)
        return wrapper
    }
}

@MainActor
private final class TaskControl: Control {
    private var currentID: AnyEquatable
    private var priority: TaskPriority
    private var action: @Sendable () async -> Void
    private var running: Task<Void, Never>?
    private var started = false

    init(id: AnyEquatable, priority: TaskPriority, action: @escaping @Sendable () async -> Void) {
        self.currentID = id
        self.priority = priority
        self.action = action
    }

    func update(id: AnyEquatable, priority: TaskPriority, action: @escaping @Sendable () async -> Void) {
        let idChanged = id != currentID
        self.currentID = id
        self.priority = priority
        self.action = action
        if idChanged, started {
            restart()
        }
    }

    override func size(proposedSize: Size) -> Size {
        children[0].size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children[0].layout(size: size)
        if !started {
            started = true
            restart()
        }
    }

    override func willRemoveFromParent() {
        running?.cancel()
        running = nil
        super.willRemoveFromParent()
    }

    private func restart() {
        running?.cancel()
        let action = self.action
        let priority = self.priority
        running = Task(priority: priority) {
            await action()
        }
    }
}
