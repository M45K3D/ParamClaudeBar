import XCTest
@testable import ParamClaudeBar

final class ClaudeLogoTests: XCTestCase {
    func testPathParsesToNonEmptyArtwork() {
        let box = ClaudeLogo.cgPath.boundingBox
        XCTAssertFalse(box.isEmpty)
        // Artwork should fill most of its 248×248 viewBox.
        XCTAssertGreaterThan(box.width, 200)
        XCTAssertGreaterThan(box.height, 200)
        XCTAssertLessThanOrEqual(box.maxX, ClaudeLogo.viewBoxSize + 1)
        XCTAssertLessThanOrEqual(box.maxY, ClaudeLogo.viewBoxSize + 1)
    }

    func testFittedPathStaysInsideAndCentresOnTargetRect() {
        let target = CGRect(x: 10, y: 30, width: 40, height: 40)
        let box = ClaudeLogo.fittedPath(in: target).boundingBox

        // Never spills outside the requested rect.
        XCTAssertGreaterThanOrEqual(box.minX, target.minX - 0.5)
        XCTAssertGreaterThanOrEqual(box.minY, target.minY - 0.5)
        XCTAssertLessThanOrEqual(box.maxX, target.maxX + 0.5)
        XCTAssertLessThanOrEqual(box.maxY, target.maxY + 0.5)

        // Centre of the artwork lands near the centre of the rect (the glyph is
        // not perfectly symmetric, so allow a few points of slack).
        XCTAssertEqual(box.midX, target.midX, accuracy: 4)
        XCTAssertEqual(box.midY, target.midY, accuracy: 4)
    }

    func testFittedPathScalesWithRect() {
        let small = ClaudeLogo.fittedPath(in: CGRect(x: 0, y: 0, width: 20, height: 20)).boundingBox
        let large = ClaudeLogo.fittedPath(in: CGRect(x: 0, y: 0, width: 40, height: 40)).boundingBox
        XCTAssertEqual(large.width / small.width, 2, accuracy: 0.05)
    }

    func testFlippedPathMirrorsVerticallyWithinBox() {
        let rect = CGRect(x: 0, y: 0, width: 22, height: 22)
        let upright = ClaudeLogo.fittedPath(in: rect).boundingBox
        let flipped = ClaudeLogo.fittedPathFlipped(in: rect, boxHeight: 22).boundingBox

        // Horizontal extent is untouched; vertical extent mirrors about the box.
        XCTAssertEqual(flipped.minX, upright.minX, accuracy: 0.01)
        XCTAssertEqual(flipped.width, upright.width, accuracy: 0.01)
        XCTAssertEqual(flipped.minY, 22 - upright.maxY, accuracy: 0.01)
        XCTAssertEqual(flipped.maxY, 22 - upright.minY, accuracy: 0.01)
    }
}
