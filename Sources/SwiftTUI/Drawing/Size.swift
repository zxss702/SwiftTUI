import Foundation

public struct Size: Equatable, CustomStringConvertible, Sendable {
    public var width: Extended
    public var height: Extended

    public static var zero: Size { Size(width: 0, height: 0) }

    public init(width: Extended, height: Extended) {
        self.width = width
        self.height = height
    }

    public init(width: Int, height: Int) {
        self.width = Extended(width)
        self.height = Extended(height)
    }

    public var widthInt: Int { width.intValue }
    public var heightInt: Int { height.intValue }

    public var description: String { "\(width)x\(height)" }
}


extension Size: AdditiveArithmetic {
    public static func + (lhs: Size, rhs: Size) -> Size {
        Size(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    public static func - (lhs: Size, rhs: Size) -> Size {
        Size(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
}

extension Size {
    public static func * (size: Size, scalar: Int) -> Size {
        Size(width: size.width * Extended(scalar), height: size.height * Extended(scalar))
    }

    public static func / (size: Size, scalar: Int) -> Size {
        Size(width: size.width / Extended(scalar), height: size.height / Extended(scalar))
    }
}

extension Size {
    public var area: Extended {
        width * height
    }
    
    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }
}

