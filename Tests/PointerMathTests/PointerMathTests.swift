import XCTest
@testable import PointerMath

final class PointerMathTests: XCTestCase {
    func testSystemModeKeepsSystemValues() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(), systemAcceleration: 0.5, systemLinear: false),
                       PointerTargets(linear: false, acceleration: 0.5))
        XCTAssertEqual(PointerMath.targets(PointerSettings(), systemAcceleration: 0.5, systemLinear: true),
                       PointerTargets(linear: true, acceleration: 0.5))
        XCTAssertTrue(PointerSettings().isDefault)
    }

    func testLinearUsesSpeedAsAcceleration() {
        XCTAssertEqual(PointerMath.targets(PointerSettings(mode: .linear, speed: 3), systemAcceleration: 0.5, systemLinear: false),
                       PointerTargets(linear: true, acceleration: 3))
        XCTAssertEqual(PointerMath.targets(PointerSettings(mode: .linear, speed: 50), systemAcceleration: 0, systemLinear: true).acceleration, 5)
    }

    func testWindowsModeStartsWithSlowMultiplier() {
        let t = PointerMath.targets(PointerSettings(mode: .windows, windowsSpeed: 0.6), systemAcceleration: 0.5, systemLinear: true)
        XCTAssertEqual(t, PointerTargets(linear: true, acceleration: 0.6))
        XCTAssertFalse(PointerSettings(mode: .windows).isDefault)
    }

    func testFixedPoint() {
        XCTAssertEqual(PointerMath.fixed(3), 196_608)
        XCTAssertEqual(PointerMath.fixed(0.5), 32_768)
        XCTAssertEqual(PointerMath.double(45_056), 0.6875)
    }
}

final class WindowsCurveTests: XCTestCase {
    func testSlowMovementKeepsBaseGain() {
        XCTAssertEqual(WindowsCurve.relativeGain(windowsSpeed: 0), 1)
        XCTAssertEqual(WindowsCurve.relativeGain(windowsSpeed: 0.43), 1, accuracy: 0.0001)
        // 0,43 по Windows — около 90 отсчётов в секунду, у мыши 1000 dpi это ~2 мм/с
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: 80, base: 0.6), 0.6, accuracy: 0.0001)
    }

    func testGainGrowsWithSpeedLikeWindows() {
        // Средний коэффициент y(x)/x в точках кривой Windows относительно медленного
        XCTAssertEqual(WindowsCurve.relativeGain(windowsSpeed: 1.25), (5.30 / 1.25) / (1.37 / 0.43), accuracy: 0.0001)
        XCTAssertEqual(WindowsCurve.relativeGain(windowsSpeed: 3.86), (24.30 / 3.86) / (1.37 / 0.43), accuracy: 0.0001)
        XCTAssertEqual(WindowsCurve.relativeGain(windowsSpeed: 40), (568 / 40) / (1.37 / 0.43), accuracy: 0.0001)
        // Дальше — не растёт
        XCTAssertEqual(WindowsCurve.relativeGain(windowsSpeed: 400), WindowsCurve.relativeGain(windowsSpeed: 40), accuracy: 0.0001)
        var previous = 0.0
        for x in stride(from: 0.0, through: 40, by: 0.5) {
            let g = WindowsCurve.relativeGain(windowsSpeed: x)
            XCTAssertGreaterThanOrEqual(g, previous - 0.0001, "x = \(x)")
            previous = g
        }
    }

    func testStrengthScalesAcceleration() {
        let fast = 100_000.0
        let full = WindowsCurve.relativeGain(windowsSpeed: 40)
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: fast, base: 1, strength: 0), 1)
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: fast, base: 1, strength: 0.5), 1 + 0.5 * (full - 1), accuracy: 0.0001)
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: fast, base: 1, strength: 1), full, accuracy: 0.0001)
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: 1_000_000, base: 5), WindowsCurve.maxMultiplier)
    }

    func testHysteresisIgnoresSmallChanges() {
        XCTAssertTrue(WindowsCurve.shouldUpdate(current: nil, to: 1))
        XCTAssertFalse(WindowsCurve.shouldUpdate(current: 1, to: 1.05))
        XCTAssertFalse(WindowsCurve.shouldUpdate(current: 1, to: 0.95))
        XCTAssertTrue(WindowsCurve.shouldUpdate(current: 1, to: 1.1))
        XCTAssertTrue(WindowsCurve.shouldUpdate(current: 1, to: 0.9))
    }
}

final class MotionSpeedTests: XCTestCase {
    func testUnevenReportsGiveSteadySpeed() {
        // По Bluetooth отчёты бывают склеенными: 8 отсчётов за 16 мс, потом 0 — средняя скорость та же 500/с
        var s = MotionSpeed()
        var values: [Double] = []
        for i in 0..<60 {
            let v = s.add(dx: i % 2 == 0 ? 8 : 0.001, dy: 0, time: Double(i) * 0.008)
            if i > 30 { values.append(v) }
        }
        XCTAssertLessThan(values.max()! / values.min()!, 1.6)
    }

    func testSteadyMotionConvergesToRealSpeed() {
        var s = MotionSpeed()
        // 4 отсчёта каждые 8 мс = 500 отсчётов/с
        for i in 0..<40 { s.add(dx: 4, dy: 0, time: Double(i) * 0.008) }
        XCTAssertEqual(s.countsPerSecond, 500, accuracy: 5)
    }

    func testDiagonalUsesDistance() {
        var s = MotionSpeed()
        for i in 0..<40 { s.add(dx: 3, dy: 4, time: Double(i) * 0.008) }
        XCTAssertEqual(s.countsPerSecond, 625, accuracy: 6)
    }

    func testSlowsDownFasterThanSpeedsUp() {
        var s = MotionSpeed()
        for i in 0..<40 { s.add(dx: 40, dy: 0, time: Double(i) * 0.008) }
        let fast = s.countsPerSecond
        // Резкое торможение у цели: через четыре отчёта (32 мс) скорость уже почти медленная
        for i in 40..<44 { s.add(dx: 1, dy: 0, time: Double(i) * 0.008) }
        XCTAssertLessThan(s.countsPerSecond, fast * 0.1)
        // А разгон с нуля за два отчёта — меньше половины
        var up = MotionSpeed()
        up.add(dx: 40, dy: 0, time: 0)
        up.add(dx: 40, dy: 0, time: 0.008)
        XCTAssertLessThan(up.countsPerSecond, fast * 0.5)
    }

    func testStartsSlowAndRestartsAfterPause() {
        var s = MotionSpeed()
        // Первый отсчёт резкого движения не даёт сразу полную скорость — множитель растёт плавно
        let first = s.add(dx: 20, dy: 0, time: 0)
        XCTAssertLessThan(first, 2500 / 2)
        for i in 1..<40 { s.add(dx: 20, dy: 0, time: Double(i) * 0.008) }
        XCTAssertGreaterThan(s.countsPerSecond, 2000)
        // После паузы — новое движение с нуля
        let afterPause = s.add(dx: 1, dy: 0, time: 1.0)
        XCTAssertLessThan(afterPause, 100)
    }
}
