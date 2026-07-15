import Foundation

/// Equality helper for `ForEach` skip-update.
///
/// Value types that are `Equatable` may skip. Reference types always update:
/// `@Model` / class rows typically equate by identity/ID while properties change
/// (streaming `content`), so skipping would leave the UI stale.
///
/// If `content` closes over parent state (visibility, selection, …), encode that
/// state into the element so equality fails when the closure’s output must change
/// (see `NavigationPage.KeepAlivePage.isTop`).
enum StateEquality {
    static func areEqual<T>(_ lhs: T, _ rhs: T) -> Bool {
        if type(of: lhs) is AnyClass {
            return false
        }
        if let left = lhs as? any Equatable {
            return left.isEqual(rhs)
        }
        return false
    }
}

private extension Equatable {
    func isEqual(_ other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}
