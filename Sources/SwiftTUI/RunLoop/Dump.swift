import Foundation

extension Application {
    func dumpTree() {
        var result = ""
        func dumpLayer(_ layer: Layer, indent: String) {
            let typeName = String(describing: type(of: layer))
            result += "\(indent)\(typeName): frame=\(layer.frame)\n"
            for child in layer.children {
                dumpLayer(child, indent: indent + "  ")
            }
        }
        dumpLayer(window.layer, indent: "")
        try? result.write(to: URL(fileURLWithPath: "/Users/zhiyang/SwiftTUI/Examples/JsonDataExample/tree.txt"), atomically: true, encoding: .utf8)
    }
}
