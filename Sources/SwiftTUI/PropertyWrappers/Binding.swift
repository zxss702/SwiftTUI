import Foundation

@propertyWrapper
@dynamicMemberLookup
@MainActor public struct Binding<T> {
    let get: () -> T
    let set: (T) -> Void

    public init(get: @escaping () -> T, set: @escaping (T) -> Void) {
        self.get = get
        self.set = set
    }

    public var wrappedValue: T {
        get { get() }
        nonmutating set { set(newValue) }
    }

    public var projectedValue: Binding<T> { self }

    /// 投影可写成员，并通过根绑定写回最新值。
    public subscript<Member>(dynamicMember keyPath: WritableKeyPath<T, Member>) -> Binding<Member> {
        Binding<Member>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var root = self.wrappedValue
                root[keyPath: keyPath] = newValue
                self.wrappedValue = root
            }
        )
    }

    /// Read-only binding that always returns `value` and ignores writes (SwiftUI-shaped).
    public static func constant(_ value: T) -> Binding<T> {
        Binding(get: { value }, set: { _ in })
    }
}
