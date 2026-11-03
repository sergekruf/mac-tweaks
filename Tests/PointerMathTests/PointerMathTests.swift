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
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: fast, base: 1, strength: 0), 1)
        let full = WindowsCurve.relativeGain(windowsSpeed: 40)
        // Половина силы — половина прибавки, с точностью до ступени
        let half = WindowsCurve.multiplier(countsPerSecond: fast, base: 1, strength: 0.5)
        XCTAssertLessThan(abs(log(half / (1 + 0.5 * (full - 1)))), log(WindowsCurve.stepRatio) / 2 + 0.0001)
        XCTAssertLessThan(half, WindowsCurve.multiplier(countsPerSecond: fast, base: 1, strength: 1))
    }

    func testMultiplierIsSteppedAndClamped() {
        let m = WindowsCurve.multiplier(countsPerSecond: 1000, base: 0.6)
        let steps = log(m / 0.6) / log(WindowsCurve.stepRatio)
        XCTAssertEqual(steps, steps.rounded(), accuracy: 0.0001)
        // Ступенька не дальше половины шага от точного значения
        let exact = 0.6 * WindowsCurve.relativeGain(windowsSpeed: WindowsCurve.windowsSpeed(countsPerSecond: 1000))
        XCTAssertLessThan(abs(log(m / exact)), log(WindowsCurve.stepRatio) / 2 + 0.0001)
        XCTAssertEqual(WindowsCurve.multiplier(countsPerSecond: 1_000_000, base: 5), WindowsCurve.maxMultiplier)
    }
}

final class MotionSpeedTests: XCTestCase {
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
        // Резкое торможение у цели: через два отчёта скорость уже почти медленная
        s.add(dx: 1, dy: 0, time: 40 * 0.008)
        s.add(dx: 1, dy: 0, time: 41 * 0.008)
        XCTAssertLessThan(s.countsPerSecond, fast * 0.1)
        // А разгон с нуля за те же два отчёта — меньше половины
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
