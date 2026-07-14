import Foundation

@MainActor public struct Spacer: View, PrimitiveView {
    @Environment(\.stackOrientation) var stackOrientation
    
    public init() {}
    
    static var size: Int? { 1 }
    
    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.element = SpacerElement(orientation: stackOrientation)
    }
    
    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.element as! SpacerElement
        control.orientation = stackOrientation
    }
    
    private class SpacerElement: Element {
        var orientation: StackOrientation
        
        init(orientation: StackOrientation) {
            self.orientation = orientation
        }
        
        override func size(proposedSize: Size) -> Size {
            switch orientation {
            case .horizontal:
                // 无界提案时不抢无限宽，避免父栈 infinity-infinity
                if proposedSize.width == .infinity {
                    return Size(width: 0, height: 0)
                }
                return Size(width: proposedSize.width, height: 0)
            case .vertical:
                if proposedSize.height == .infinity {
                    return Size(width: 0, height: 0)
                }
                return Size(width: 0, height: proposedSize.height)
            }
        }

        /// size(.infinity) 故意返回 0，但弹性必须视为最大，否则 HStack 不会把剩余宽度分给 Spacer。
        override func horizontalFlexibility(height: Extended) -> Extended {
            orientation == .horizontal ? .infinity : 0
        }

        override func verticalFlexibility(width: Extended) -> Extended {
            orientation == .vertical ? .infinity : 0
        }
    }
}
