import Foundation

public struct Rect: Equatable, Sendable {
    public var position: Position
    public var size: Size

    public init(position: Position, size: Size) {
        self.position = position
        self.size = size
    }

    public init(origin: Position, size: Size) {
        self.position = origin
        self.size = size
    }

    public var origin: Position {
        get { position }
        set { position = newValue }
    }

    public init(minColumn: Extended, minLine: Extended, maxColumn: Extended, maxLine: Extended) {
        self.position = Position(column: minColumn, line: minLine)
        self.size = Size(width: maxColumn - minColumn + 1, height: maxLine - minLine + 1)
    }

    init(column: Extended, line: Extended, width: Extended, height: Extended) {
        self.position = Position(column: column, line: line)
        self.size = Size(width: width, height: height)
    }

    public static let zero = Rect(position: .zero, size: .zero)

    public var minLine: Extended { position.line }
    public var minColumn: Extended { position.column }
    public var maxLine: Extended {
        guard size.height != .infinity else { return .infinity }
        guard size.height != 0 else { return minLine }
        return position.line + size.height - 1
    }
    public var maxColumn: Extended {
        guard size.width != .infinity else { return .infinity }
        guard size.width != 0 else { return minColumn }
        return position.column + size.width - 1
    }
    public var width: Extended { size.width }
    public var height: Extended { size.height }

    /// The smallest rectangle that contains the two source rectangles.
    public func union(_ r2: Rect) -> Rect {
        Rect(minColumn: min(minColumn, r2.minColumn),
             minLine: min(minLine, r2.minLine),
             maxColumn: max(maxColumn, r2.maxColumn),
             maxLine: max(maxLine, r2.maxLine))
    }

    public func contains(_ position: Position) -> Bool {
        position.column >= minColumn &&
        position.line >= minLine &&
        position.column <= maxColumn &&
        position.line <= maxLine
    }
}

extension Rect: CustomStringConvertible {
    public var description: String { "\(position) \(size)" }
}

extension Rect {
    public var isEmpty: Bool {
        size.isEmpty
    }

    public func contains(_ rect: Rect) -> Bool {
        rect.minColumn >= minColumn &&
        rect.maxColumn <= maxColumn &&
        rect.minLine >= minLine &&
        rect.maxLine <= maxLine
    }

    public func intersects(_ rect: Rect) -> Bool {
        maxColumn >= rect.minColumn &&
        minColumn <= rect.maxColumn &&
        maxLine >= rect.minLine &&
        minLine <= rect.maxLine
    }

    public func intersection(with rect: Rect) -> Rect? {
        let col = (min: max(minColumn, rect.minColumn),
                   max: min(maxColumn, rect.maxColumn))
        let line = (min: max(minLine, rect.minLine),
                    max: min(maxLine, rect.maxLine))

        guard col.min <= col.max, line.min <= line.max else { return nil }
        return Rect(minColumn: col.min, minLine: line.min, maxColumn: col.max, maxLine: line.max)
    }

    public func offset(by position: Position) -> Rect {
        return Rect(position: self.position + position, size: self.size)
    }
}
