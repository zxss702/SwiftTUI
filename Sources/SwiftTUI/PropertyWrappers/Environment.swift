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
                // Detached / torn-down views can still be observed briefly; never trap the process.
                if let kp = keyPath {
                    return EnvironmentValues()[keyPath: kp]
                }
                fatalError("Attempting to access @Environment(\(T.self)) before view is instantiated")
            }
            let environmentValues = node.resolvedEnvironment()
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
}

@MainActor protocol AnyEnvironment {
    var valueReference: EnvironmentReference { get }
}

@MainActor class EnvironmentReference {
    weak var node: Node?
}
