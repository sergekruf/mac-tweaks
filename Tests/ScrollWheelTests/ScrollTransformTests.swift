import XCTest
@testable import ScrollWheel

final class ScrollTransformTests: XCTestCase {
    private let reverse = ScrollSettings(reverseWheel: true)
    private let threeLines = ScrollSettings(linesPerNotch: 3)

    func testWheelDownReversed() {
        // При «естественной» прокрутке колесо вниз приходит с положительной дельтой — после обращения она отрицательная
        let out = ScrollTransform.apply(.wheel(lines: 2), reverse)
        XCTAssertEqual(out?.vertical, ScrollAxis(lines: -2, fixed: -2, points: -20))
        XCTAssertEqual(out?.horizontal, .zero)
    }

    func testReverseKeepsAcceleratedValues() {
        // Без «по строкам» обращаем то, что прислала система, включая её ускорение и дробную часть
        let event = ScrollEvent(vertical: ScrollAxis(lines: -7, fixed: -6.5, points: -83))
        XCTAssertEqual(ScrollTransform.apply(event, reverse)?.vertical, ScrollAxis(lines: 7, fixed: 6.5, points: 83))
    }

    func testTrackpadAndMagicMouseUntouched() {
        let touch = ScrollEvent(vertical: ScrollAxis(lines: 1, fixed: 1.2, points: 12), isContinuous: true)
        let all = ScrollSettings(reverseWheel: true, linesPerNotch: 3)
        XCTAssertNil(ScrollTransform.apply(touch, all))
        // Фазы жеста и инерция — тоже не трогаем, даже если continuous не выставлен
        XCTAssertNil(ScrollTransform.apply(ScrollEvent(vertical: ScrollAxis(lines: 1, fixed: 1, points: 10), scrollPhase: 2), all))
        XCTAssertNil(ScrollTransform.apply(ScrollEvent(vertical: ScrollAxis(lines: 1, fixed: 1, points: 10), momentumPhase: 1), all))
    }

    func testNothingEnabledPassesThrough() {
        XCTAssertNil(ScrollTransform.apply(.wheel(lines: 5), ScrollSettings()))
    }

    func testFixedLinesRegardlessOfInputDelta() {
        // Медленный щелчок, быстрый с ускорением, дробный без целых строк — всегда 3 строки
        let inputs = [ScrollAxis(lines: 1, fixed: 1, points: 10),
                      ScrollAxis(lines: 9, fixed: 8.7, points: 112),
                      ScrollAxis(lines: 0, fixed: 0.1, points: 1)]
        for input in inputs {
            XCTAssertEqual(ScrollTransform.apply(ScrollEvent(vertical: input), threeLines)?.vertical,
                           ScrollAxis(lines: 3, fixed: 3, points: 30), "\(input)")
        }
        XCTAssertEqual(ScrollTransform.apply(ScrollEvent(vertical: ScrollAxis(lines: -12, fixed: -11.4, points: -150)), threeLines)?.vertical,
                       ScrollAxis(lines: -3, fixed: -3, points: -30))
    }

    func testLinesCountIsConfigurable() {
        for n in [1, 5, 10] {
            let out = ScrollTransform.apply(.wheel(lines: 4), ScrollSettings(linesPerNotch: n))
            XCTAssertEqual(out?.vertical, ScrollAxis(lines: Int64(n), fixed: Double(n), points: Double(n) * 10))
        }
    }

    func testFixedLinesAndReverseTogether() {
        let out = ScrollTransform.apply(.wheel(lines: 6), ScrollSettings(reverseWheel: true, linesPerNotch: 3))
        XCTAssertEqual(out?.vertical, ScrollAxis(lines: -3, fixed: -3, points: -30))
    }

    func testHorizontalTilt() {
        // Наклон колеса — Axis2, обрабатывается так же; вертикаль при этом нулевая и остаётся нулевой
        let all = ScrollSettings(reverseWheel: true, linesPerNotch: 2)
        let out = ScrollTransform.apply(.wheel(lines: 0, horizontal: -4), all)
        XCTAssertEqual(out?.horizontal, ScrollAxis(lines: 2, fixed: 2, points: 20))
        XCTAssertEqual(out?.vertical, .zero)
        XCTAssertEqual(ScrollTransform.apply(.wheel(lines: 0, horizontal: 1), reverse)?.horizontal,
                       ScrollAxis(lines: -1, fixed: -1, points: -10))
    }

    func testShiftWheelStaysOnVerticalAxis() {
        // Shift + колесо приходит как вертикаль с флагом Shift — горизонталью его делает приложение,
        // поэтому достаточно того же преобразования Axis1
        let out = ScrollTransform.apply(.wheel(lines: -1), ScrollSettings(linesPerNotch: 4))
        XCTAssertEqual(out?.vertical, ScrollAxis(lines: -4, fixed: -4, points: -40))
        XCTAssertEqual(out?.horizontal, .zero)
    }
}
