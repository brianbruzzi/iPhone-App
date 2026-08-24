import XCTest
@testable import FaderLabCore

private struct Point: Equatable {
    let x: Int
    let y: Int
}

final class Grid8x8Tests: XCTestCase {

    /// A grid with exactly one marked cell, rest `0`, for tracking where a single point
    /// lands after a rotation.
    private func markedGrid(x: Int, y: Int) -> Grid8x8<Int> {
        var grid = Grid8x8<Int>(repeating: 0)
        grid[x, y] = 1
        return grid
    }

    private func onlyMarkedCell(_ grid: Grid8x8<Int>) -> Point? {
        var found: Point?
        grid.forEach { x, y, value in
            if value == 1 { found = Point(x: x, y: y) }
        }
        return found
    }

    func testDegrees0IsIdentity() {
        let grid = markedGrid(x: 2, y: 5)
        XCTAssertEqual(grid.rotated(.degrees0), grid)
    }

    /// The defining case this feature exists for: rotating the whole grid carries whatever
    /// a pattern considers its "bottom" (the y=7 row) to a full physical edge, so a
    /// gravity-style pattern's floor ends up wherever the user has designated as down —
    /// without the pattern itself doing anything different.
    func testDegrees90CarriesTheBottomRowToTheLeftColumn() {
        var grid = Grid8x8<Int>(repeating: 0)
        for x in 0..<8 { grid[x, 7] = 1 } // the bottom row, lit
        let rotated = grid.rotated(.degrees90)

        for y in 0..<8 {
            XCTAssertEqual(rotated[0, y], 1, "left column should be entirely lit after a 90 degree rotation")
        }
        for x in 1..<8 {
            for y in 0..<8 {
                XCTAssertEqual(rotated[x, y], 0, "only the left column should be lit")
            }
        }
    }

    func testDegrees90MovesTopLeftCornerToTopRight() {
        let grid = markedGrid(x: 0, y: 0)
        XCTAssertEqual(onlyMarkedCell(grid.rotated(.degrees90)), Point(x: 7, y: 0))
    }

    func testDegrees180MovesTopLeftCornerToBottomRight() {
        let grid = markedGrid(x: 0, y: 0)
        XCTAssertEqual(onlyMarkedCell(grid.rotated(.degrees180)), Point(x: 7, y: 7))
    }

    func testDegrees270MovesTopLeftCornerToBottomLeft() {
        let grid = markedGrid(x: 0, y: 0)
        XCTAssertEqual(onlyMarkedCell(grid.rotated(.degrees270)), Point(x: 0, y: 7))
    }

    func testFourNinetyDegreeRotationsReturnToTheOriginal() {
        let grid = markedGrid(x: 3, y: 1)
        let fourTimes = grid.rotated(.degrees90).rotated(.degrees90).rotated(.degrees90).rotated(.degrees90)
        XCTAssertEqual(fourTimes, grid)
    }

    func testTwoNinetyDegreeRotationsEqualOneHundredEighty() {
        let grid = markedGrid(x: 6, y: 2)
        XCTAssertEqual(grid.rotated(.degrees90).rotated(.degrees90), grid.rotated(.degrees180))
    }

    func testRotationPreservesEveryElementExactlyOnce() {
        // Every cell distinct, so a rotation that duplicated or dropped a value would show
        // up as a changed multiset of contents.
        var grid = Grid8x8<Int>(repeating: 0)
        for y in 0..<8 {
            for x in 0..<8 {
                grid[x, y] = y * 8 + x
            }
        }
        let originalValues = Set(grid.rows.flatMap { $0 })
        for rotation: GridRotation in [.degrees90, .degrees180, .degrees270] {
            let rotatedValues = Set(grid.rotated(rotation).rows.flatMap { $0 })
            XCTAssertEqual(rotatedValues, originalValues, "\(rotation) must be a permutation, not lossy")
        }
    }
}
