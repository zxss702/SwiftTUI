import Foundation
import JsonDataCore

public struct ModelContextKey: EnvironmentKey {
    public static var defaultValue: ModelContext? = nil
}

public extension EnvironmentValues {
    var modelContext: ModelContext? {
        get { self[ModelContextKey.self] }
        set { self[ModelContextKey.self] = newValue }
    }
}
