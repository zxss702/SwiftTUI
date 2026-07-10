import Foundation

// MARK: - Placement

/// 对齐 SwiftUI.ToolbarItemPlacement（仅 macOS 现行、非弃用项）。
@MainActor public struct ToolbarItemPlacement: Hashable, Sendable {
    let id: String

    public static let automatic = ToolbarItemPlacement(id: "automatic")
    public static let principal = ToolbarItemPlacement(id: "principal")
    public static let navigation = ToolbarItemPlacement(id: "navigation")
    public static let primaryAction = ToolbarItemPlacement(id: "primaryAction")
    public static let secondaryAction = ToolbarItemPlacement(id: "secondaryAction")
    public static let status = ToolbarItemPlacement(id: "status")
    public static let confirmationAction = ToolbarItemPlacement(id: "confirmationAction")
    public static let cancellationAction = ToolbarItemPlacement(id: "cancellationAction")
    public static let destructiveAction = ToolbarItemPlacement(id: "destructiveAction")
}

// MARK: - Slot（内部）

enum ToolbarSlot: Hashable {
    case leading
    case principal
    case trailing
}

extension ToolbarItemPlacement {
    var slot: ToolbarSlot {
        switch id {
        case Self.navigation.id, Self.cancellationAction.id:
            return .leading
        case Self.principal.id:
            return .principal
        default:
            // automatic / primary / secondary / status / confirmation / destructive → trailing
            return .trailing
        }
    }
}
