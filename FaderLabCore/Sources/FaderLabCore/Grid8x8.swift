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

    /// Rotates the whole grid by a multiple of 90 degrees. Applied to a pattern's finished
    /// output, not to its inputs — a "gravity" pattern like Ember Fire or VU Columns has no
    /// idea it's been rotated, it just renders exactly as always, and rotating the result
    /// afterward carries its authored "bottom" along to whichever physical edge the user has
    /// designated as down. See `PatternEngine.padRotation`.
    public func rotated(_ rotation: GridRotation) -> Grid8x8<Element> {
        let n = Grid8x8.size
        switch rotation {
        case .degrees0:
            return self
        case .degrees90:
            return Grid8x8(flatStorage: (0..<(n * n)).map { i in
                let x = i % n, y = i / n
                return self[y, n - 1 - x]
            })
        case .degrees180:
            return Grid8x8(flatStorage: (0..<(n * n)).map { i in
                let x = i % n, y = i / n
                return self[n - 1 - x, n - 1 - y]
            })
        case .degrees270:
            return Grid8x8(flatStorage: (0..<(n * n)).map { i in
                let x = i % n, y = i / n
                return self[n - 1 - y, x]
            })
        }
    }
}

/// A rotation applied to a full `Grid8x8` frame before it reaches the hardware or the
/// on-screen preview, so any physical edge of the Launchpad can be designated as "down"
/// without any individual pattern needing to know about orientation. `.degrees90` and
/// `.degrees270` are opposite rotation directions — since the same rotated grid also drives
/// the live on-screen preview, the right one for a given physical orientation is whichever
/// visually matches the hardware, not something to reason out from the case name alone.
public enum GridRotation: CaseIterable, Equatable, Hashable, Sendable {
    case degrees0
    case degrees90
    case degrees180
    case degrees270
}

/// The canonical pixel-art frame type: an 8x8 grid of colors ready to send to the Launchpad.
public typealias PixelGrid = Grid8x8<RGBColor>

public extension PixelGrid {
    static var allBlack: PixelGrid { PixelGrid(repeating: .black) }
}
