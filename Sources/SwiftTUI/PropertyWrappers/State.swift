import Foundation

@propertyWrapper
@MainActor public struct State<T>: AnyState {
    public let initialValue: T

    public init(initialValue: T) {
        self.initialValue = initialValue
    }

    public init(wrappedValue: T) {
        self.initialValue = wrappedValue
    }

    /// @State variables can have a nonmutating setter, because they are just
    /// a reference to state stored in a Node.
    var valueReference = StateReference()

    public var wrappedValue: T {
        get {
            guard let node = valueReference.node,
                  let label = valueReference.label
            else {
                assertionFailure("Attempting to access @State variable before view is instantiated")
                return initialValue
            }
            if let value = node.state[label] {
                return value as! T
            }
            // 首次读取时写入 node.state，否则父视图刷新会丢掉引用类型状态（如 NavigationContext）
            node.state[label] = initialValue
            return initialValue
        }
        nonmutating set {
            guard let node = valueReference.node,
                  let label = valueReference.label
            else {
                assertionFailure("Attempting to modify @State variable before view is instantiated")
                return
            }
            node.state[label] = newValue
            node.root.application?.invalidateNode(node)
        }
    }

    public var projectedValue: Binding<T> {
        // 通过 valueReference 捕获，避免 Binding 在 View 副本上失效；
        // node 已释放时安全 no-op，避免 syncToBinding 时 assertion 闪退。
        let reference = valueReference
        let fallback = initialValue
        return Binding<T>(
            get: {
                guard let node = reference.node, let label = reference.label else {
                    return fallback
                }
                if let value = node.state[label] as? T {
                    return value
                }
                node.state[label] = fallback
                return fallback
            },
            set: { newValue in
                guard let node = reference.node, let label = reference.label else {
                    return
                }
                node.state[label] = newValue
                node.root.application?.invalidateNode(node)
            }
        )
    }
}

@MainActor protocol AnyState {
    var valueReference: StateReference { get }
}

@MainActor class StateReference {
    weak var node: Node?
    var label: String?
}
