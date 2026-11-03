import Foundation
import IOKit.pwr_mgt

/// Режим «не засыпать» через IOPMAssertion. Пока assertion держится, Mac не уходит в сон по бездействию.
/// Assertion снимается по таймеру, кнопкой «Выключить» и при выходе (система снимает её и при падении процесса).
/// Закрытую крышку без внешнего монитора так не удержать — это другой механизм (clamshell sleep).
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    /// Варианты в минутах, nil — «Пока не выключу».
    static let durations: [Int?] = [15, 30, 60, 120, 240, 480, nil]
    static let assertionName = "Mac Tweaks: keep awake" // pmset показывает только ASCII

    @Published private(set) var isActive = false
    /// Выбранная длительность, nil — без срока.
    @Published private(set) var minutes: Int?
    @Published private(set) var endDate: Date?
    /// Не гасить экран: PreventUserIdleDisplaySleep вместо PreventUserIdleSystemSleep.
    @Published var keepDisplayOn: Bool {
        didSet { if isActive && keepDisplayOn != oldValue { createAssertion(); onChange?() } }
    }
    @Published private(set) var lastError: String?

    var onChange: (() -> Void)?

    private var assertionID: IOPMAssertionID?
    private var endTimer: Timer?
    private var tickTimer: Timer?

    private init() {
        keepDisplayOn = AppSettings.shared.keepDisplayOnByDefault
    }

    func start(minutes: Int?) {
        self.minutes = minutes
        endDate = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        createAssertion()
        isActive = assertionID != nil
        endTimer?.invalidate(); endTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        if isActive {
            if let endDate {
                let t = Timer(fire: endDate, interval: 0, repeats: false) { _ in
                    Task { @MainActor in KeepAwake.shared.stop() }
                }
                RunLoop.main.add(t, forMode: .common)
                endTimer = t
            }
            // Обновляет подсказку у значка; заодно ловит истёкший срок после сна с закрытой крышкой
            let tick = Timer(timeInterval: 30, repeats: true) { _ in
                Task { @MainActor in KeepAwake.shared.tick() }
            }
            RunLoop.main.add(tick, forMode: .common)
            tickTimer = tick
        }
        onChange?()
    }

    func stop() {
        endTimer?.invalidate(); endTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        releaseAssertion()
        isActive = false
        minutes = nil
        endDate = nil
        onChange?()
    }

    private func tick() {
        if let endDate, endDate <= Date() { stop() } else { onChange?() }
    }

    private func createAssertion() {
        releaseAssertion()
        let type = keepDisplayOn ? kIOPMAssertPreventUserIdleDisplaySleep : kIOPMAssertPreventUserIdleSystemSleep
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 Self.assertionName as CFString, &id)
        if result == kIOReturnSuccess {
            assertionID = id
            lastError = nil
        } else {
            lastError = "Не удалось включить: IOPMAssertionCreateWithName вернул \(result)"
        }
    }

    private func releaseAssertion() {
        if let id = assertionID { IOPMAssertionRelease(id) }
        assertionID = nil
    }

    // MARK: - Тексты

    /// «Не спит ещё 1 ч 23 мин» или nil, если выключено.
    var remainingText: String? {
        guard isActive else { return nil }
        guard let endDate else { return "Не спит, пока не выключите" }
        let left = Int((endDate.timeIntervalSinceNow / 60).rounded(.up))
        return "Не спит ещё " + Self.format(minutes: max(left, 1))
    }

    static func title(for minutes: Int?) -> String {
        minutes.map(format(minutes:)) ?? "Пока не выключу"
    }

    static func format(minutes m: Int) -> String {
        let h = m / 60, mm = m % 60
        if h == 0 { return "\(mm) мин" }
        return mm == 0 ? "\(h) ч" : "\(h) ч \(mm) мин"
    }
}
