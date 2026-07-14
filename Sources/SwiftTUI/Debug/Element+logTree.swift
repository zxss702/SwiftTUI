import Foundation

extension Element {
    /// Log the tree underneath the current control.
    /// ```
    /// → VStackElement
    ///   → TextElement
    ///   → TextElement
    /// ```
    func logTree() {
        log(treeDescription)
    }

    var treeDescription: String {
        treeDescription(level: 0)
    }

    private func treeDescription(level: Int) -> String {
        var str = ""
        let indent = Array(repeating: " ", count: level * 2).joined()
        str += "\(indent)→ \(type(of: self))"
        for child in children {
            str += "\n" + child.treeDescription(level: level + 1)
        }
        return str
    }
}
