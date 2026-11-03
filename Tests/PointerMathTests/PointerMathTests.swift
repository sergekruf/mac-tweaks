import XCTest
@testable import PointerMath

final class PointerMathTests: XCTestCase {
    func testDefaultKeepsSystemAcceleration() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(), systemAcceleration: 0.5, systemLinear: false),
                       PointerTargets(linear: false, acceleration: 0.5))
        XCTAssertTrue(PointerSettings().isDefault)
        // Скорость без линейного режима ни на что не влияет
        XCTAssertEqual(PointerMath.targets(PointerSettings(speed: 4), systemAcceleration: 0.6875, systemLinear: false).acceleration, 0.6875)
    }

    func testResetReturnsSystemLinearFlag() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(), systemAcceleration: 0.5, systemLinear: true),
                       PointerTargets(linear: true, acceleration: 0.5))
    }

    func testLinearUsesSpeedAsAcceleration() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(linear: true, speed: 3), systemAcceleration: 0.5, systemLinear: false),
                       PointerTargets(linear: true, acceleration: 3))
        XCTAssertFalse(PointerSettings(linear: true).isDefault)
    }

    func testSpeedIsClamped() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(linear: true, speed: 50), systemAcceleration: 0, systemLinear: false).acceleration, 5)
        XCTAssertEqual(PointerMath.targets(PointerSettings(linear: true, speed: 0), systemAcceleration: 0, systemLinear: false).acceleration, 0.2)
    }

    func testFixedPoint() {
        XCTAssertEqual(PointerMath.fixed(3), 196_608)
        XCTAssertEqual(PointerMath.fixed(0.5), 32_768)
        XCTAssertEqual(PointerMath.double(45_056), 0.6875)
    }
}
