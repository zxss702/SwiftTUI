import Foundation

/// Modifies controls as they are passed to a container.
@MainActor protocol ModifierView {
    func passElement(_ control: Element, node: Node) -> Element
}
