import Foundation

public struct Position: Equatable, Sendable {
    public var column: Extended
    public var line: Extended

    public static var zero: Position { Position(column: 0, line: 0) }

    public init(column: Extended, line: Extended) {
        self.column = column
        self.line = line
    }

    // MARK: - Point Compatibility
    public init(x: Int, y: Int) {
        self.column = Extended(x)
        self.line = Extended(y)
    }

    public var x: Int {
        get { column.intValue }
        set { column = Extended(newValue) }
    }

    public var y: Int {
        get { line.intValue }
        set { line = Extended(newValue) }
    }
}


extension Position: CustomStringConvertible {
    public var description: String { "(\(column), \(line))" }
}

extension Position: AdditiveArithmetic {
    public static func +(lhs: Self, rhs: Self) -> Self {
        Position(column: lhs.column + rhs.column, line: lhs.line + rhs.line)
    }

    public static func - (lhs: Position, rhs: Position) -> Position {
        Position(column: lhs.column - rhs.column, line: lhs.line - rhs.line)
    }
}
