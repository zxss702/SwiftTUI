import Foundation

@MainActor public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

@MainActor public struct EnvironmentValues {
    var values: [ObjectIdentifier: Any] = [:]
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }

    public subscript<T>(type: T.Type) -> T? {
        get { values[ObjectIdentifier(type)] as? T }
        set { values[ObjectIdentifier(type)] = newValue }
    }
}

@propertyWrapper
@MainActor public struct Environment<T>: AnyEnvironment {
    let keyPath: KeyPath<EnvironmentValues, T>?

    public init(_ keyPath: KeyPath<EnvironmentValues, T>) {
        self.keyPath = keyPath
    }

    public init(_ type: T.Type) {
        self.keyPath = nil
    }

    var valueReference = EnvironmentReference()

    public var wrappedValue: T {
        get {
            guard let node = valueReference.node else {
                assertionFailure("Attempting to access @Environment variable before view is instantiated")
                if let kp = keyPath {
                    return EnvironmentValues()[keyPath: kp]
                }
                fatalError("Missing environment object of type \(T.self)")
            }
            let environmentValues = makeEnvironment(node: node, transform: { _ in })
            if let kp = keyPath {
                return environmentValues[keyPath: kp]
            } else {
                guard let object = environmentValues[T.self] else {
                    fatalError("No environment object of type \(T.self) found in view hierarchy")
                }
                return object
            }
        }
        set {}
    }

    private func makeEnvironment(node: Node, transform: (inout EnvironmentValues) -> Void) -> EnvironmentValues {
        if let parent = node.parent {
            return makeEnvironment(node: parent) {
                node.environment?(&$0)
                transform(&$0)
            }
        }
        var environmentValues = EnvironmentValues()
        node.environment?(&environmentValues)
        transform(&environmentValues)
        return environmentValues
    }
}

@MainActor protocol AnyEnvironment {
    var valueReference: EnvironmentReference { get }
}

@MainActor class EnvironmentReference {
    weak var node: Node?
}
