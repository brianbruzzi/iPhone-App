import Foundation

/// A fixed 8x8 grid, matching the Launchpad X's pad layout. Row-major storage with an
/// (x, y) subscript where x/y are both 0...7, x increasing left->right and y increasing
/// top->bottom (standard pixel-art/image convention — NOT the Launchpad's own bottom-up
/// note numbering, which `LaunchpadXProtocol.note(x:y:)` converts to/from).
public struct Grid8x8<Element: Equatable>: Equatable {
    public static var size: Int { 8 }

    private var storage: [Element]

    public init(repeating element: Element) {
        storage = Array(repeating: element, count: Grid8x8.size * Grid8x8.size)
    }

    /// Builds a grid from row-major nested arrays (rows[y][x]). Returns nil unless the
    /// input is exactly 8x8.
    public init?(rows: [[Element]]) {
        guard rows.count == Grid8x8.size, rows.allSatisfy({ $0.count == Grid8x8.size }) else {
            return nil
        }
        storage = rows.flatMap { $0 }
    }

    init(flatStorage: [Element]) {
        precondition(flatStorage.count == Grid8x8.size * Grid8x8.size)
        storage = flatStorage
    }

    public subscript(x: Int, y: Int) -> Element {
        get {
            precondition((0..<Grid8x8.size).contains(x) && (0..<Grid8x8.size).contains(y))
            return storage[y * Grid8x8.size + x]
        }
        set {
            precondition((0..<Grid8x8.size).contains(x) && (0..<Grid8x8.size).contains(y))
            storage[y * Grid8x8.size + x] = newValue
        }
    }

    /// Row-major nested-array view (rows[y][x]).
    public var rows: [[Element]] {
        (0..<Grid8x8.size).map { y in
            (0..<Grid8x8.size).map { x in self[x, y] }
        }
    }

    public func map<T: Equatable>(_ transform: (Element) -> T) -> Grid8x8<T> {
        Grid8x8<T>(flatStorage: storage.map(transform))
    }

    public func forEach(_ body: (_ x: Int, _ y: Int, _ element: Element) -> Void) {
        for y in 0..<Grid8x8.size {
            for x in 0..<Grid8x8.size {
                body(x, y, self[x, y])
            }
        }
    }
}

/// The canonical pixel-art frame type: an 8x8 grid of colors ready to send to the Launchpad.
public typealias PixelGrid = Grid8x8<RGBColor>

public extension PixelGrid {
    static var allBlack: PixelGrid { PixelGrid(repeating: .black) }
}
