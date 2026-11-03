import XCTest
@testable import KeyChord

final class ModifierTapTests: XCTestCase {
    /// Прогоняет события и возвращает, сколько раз сработало.
    private func fires(_ events: [TapInput], chord: ModifierChord = .commandShift) -> Int {
        var d = ModifierTapDetector(chord: chord)
        return events.filter { d.handle($0) }.count
    }

    private func m(_ keys: ModifierKey...) -> TapInput { .modifiers(Set(keys)) }

    func testCommandThenShift() {
        // Cmd↓ Shift↓ Shift↑ Cmd↑
        XCTAssertEqual(fires([m(.leftCommand), m(.leftCommand, .leftShift), m(.leftCommand), m()]), 1)
    }

    func testShiftThenCommandReleasedInAnyOrder() {
        // Shift↓ Cmd↓ Cmd↑ Shift↑
        XCTAssertEqual(fires([m(.leftShift), m(.leftShift, .leftCommand), m(.leftShift), m()]), 1)
        // Shift↓ Cmd↓ Shift↑ Cmd↑
        XCTAssertEqual(fires([m(.leftShift), m(.leftShift, .leftCommand), m(.leftCommand), m()]), 1)
    }

    func testRightKeysAndMixedSides() {
        XCTAssertEqual(fires([m(.rightCommand), m(.rightCommand, .rightShift), m(.rightCommand), m()]), 1)
        XCTAssertEqual(fires([m(.rightShift), m(.rightShift, .leftCommand), m(.leftCommand), m()]), 1)
    }

    func testOtherKeyInsideChordCancels() {
        // Cmd↓ Shift↓ 4↓ 4↑ Shift↑ Cmd↑ — скриншот, язык не трогаем
        XCTAssertEqual(fires([m(.leftCommand), m(.leftCommand, .leftShift), .otherKey, m(.leftCommand), m()]), 0)
        // Клавиша после отпускания Shift, но пока Cmd зажат (Cmd+Shift, затем Cmd+Tab)
        XCTAssertEqual(fires([m(.leftCommand), m(.leftCommand, .leftShift), m(.leftCommand), .otherKey, m()]), 0)
        // Клавиша до того, как сочетание набрано: Cmd↓ Z↓ Shift↓ …
        XCTAssertEqual(fires([m(.leftCommand), .otherKey, m(.leftCommand, .leftShift), m(.leftCommand), m()]), 0)
    }

    /// Cmd↓ Shift↓ Cmd↑ — язык меняется сразу, пока Shift ещё зажат; Shift+2 после этого уже не мешает.
    func testFiresWhenOnlyShiftRemains() {
        var d = ModifierTapDetector(chord: .commandShift)
        XCTAssertFalse(d.handle(m(.leftCommand)))
        XCTAssertFalse(d.handle(m(.leftCommand, .leftShift)))
        XCTAssertTrue(d.handle(m(.leftShift)))
        XCTAssertFalse(d.handle(.otherKey))
        XCTAssertFalse(d.handle(m()))
        // Следующее нажатие снова работает
        XCTAssertEqual(fires([m(.leftShift), m(.leftShift, .rightCommand), m(.leftShift), .otherKey, m()]), 1)
    }

    /// Если зажатым остался Cmd — ждём полного отпускания (иначе сломается Cmd+Shift, затем Cmd+Tab).
    func testWaitsWhileCommandHeld() {
        var d = ModifierTapDetector(chord: .commandShift)
        XCTAssertFalse(d.handle(m(.leftCommand)))
        XCTAssertFalse(d.handle(m(.leftCommand, .leftShift)))
        XCTAssertFalse(d.handle(m(.leftCommand)))
        XCTAssertTrue(d.handle(m()))
    }

    func testSingleModifierDoesNothing() {
        XCTAssertEqual(fires([m(.leftShift), m()]), 0)
        XCTAssertEqual(fires([m(.rightCommand), m()]), 0)
    }

    func testExtraModifierCancels() {
        // Cmd+Shift+Option — уже другое сочетание
        XCTAssertEqual(fires([m(.leftCommand), m(.leftCommand, .leftShift), m(.leftCommand, .leftShift, .leftOption),
                              m(.leftCommand, .leftShift), m()]), 0)
        XCTAssertEqual(fires([m(.leftControl), m(.leftControl, .leftCommand, .leftShift), m()]), 0)
    }

    func testTypingBeforeChordDoesNotBlockIt() {
        XCTAssertEqual(fires([.otherKey, .otherKey, m(.leftCommand), m(.leftCommand, .leftShift), m()]), 1)
    }

    func testStateResetsBetweenPresses() {
        let spoiled: [TapInput] = [m(.leftCommand), m(.leftCommand, .leftShift), .otherKey, m()]
        let clean: [TapInput] = [m(.leftShift), m(.leftShift, .rightCommand), m()]
        XCTAssertEqual(fires(spoiled + clean + clean), 2)
    }

    func testRightCommandChord() {
        XCTAssertEqual(fires([m(.rightCommand), m()], chord: .rightCommand), 1)
        XCTAssertEqual(fires([m(.leftCommand), m()], chord: .rightCommand), 0)
        XCTAssertEqual(fires([m(.rightCommand), m(.rightCommand, .leftShift), m(.rightCommand), m()], chord: .rightCommand), 0)
    }
}
