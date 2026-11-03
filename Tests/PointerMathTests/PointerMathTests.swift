import XCTest
@testable import PointerMath

final class PointerMathTests: XCTestCase {
    func testDefaultKeepsSystemValues() {
        let t = PointerMath.targets(PointerSettings(), systemAcceleration: 0.5, initialResolution: nil)
        XCTAssertEqual(t, PointerTargets(acceleration: 0.5, resolution: 400))
        XCTAssertTrue(PointerSettings().isDefault)
    }

    func testDisableAcceleration() {
        let t = PointerMath.targets(PointerSettings(disableAcceleration: true), systemAcceleration: 0.5, initialResolution: 800)
        XCTAssertEqual(t, PointerTargets(acceleration: -1, resolution: 800))
    }

    func testSpeedScalesFromInitialResolution() {
        // В 2 раза быстрее — разрешение в 2 раза меньше; ускорение остаётся системным
        XCTAssertEqual(PointerMath.targets(PointerSettings(speed: 2), systemAcceleration: 0.6875, initialResolution: nil),
                       PointerTargets(acceleration: 0.6875, resolution: 200))
        XCTAssertEqual(PointerMath.targets(PointerSettings(speed: 0.5), systemAcceleration: 0.5, initialResolution: 1000).resolution, 1995)
    }

    func testSpeedIsClamped() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(speed: 10), systemAcceleration: 0, initialResolution: 400).resolution,
                       400 / 3, accuracy: 0.0001)
    }

    func testFixedPoint() {
        XCTAssertEqual(PointerMath.fixed(-1), -65_536)
        XCTAssertEqual(PointerMath.fixed(0.5), 32_768)
        XCTAssertEqual(PointerMath.double(45_056), 0.6875)
    }
}
