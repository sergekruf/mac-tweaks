import AppKit
import ScrollWheel

/// Своё направление и прокрутка по строкам для колеса мыши (как LinearMouse).
/// Активный CGEventTap на scrollWheel (нужен «Универсальный доступ»): событие колеса меняется на месте,
/// тачпад и Magic Mouse проходят как есть — решение в `ScrollTransform`.
@MainActor
final class MouseScroller: ObservableObject {
    static let shared = MouseScroller()
    static let linearMouseBundleID = "com.lujjjh.LinearMouse"

    @Published private(set) var hasPermission = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var settings = ScrollSettings()
    private let tap = EventTap(types: [.scrollWheel], options: .defaultTap, permission: .accessibility) { type, event in
        guard type == .scrollWheel else { return }
        MouseScroller.shared.handle(event)
    }

    private init() {
        tap.onChange = { [weak self] in self?.syncTapState() }
        syncTapState()
    }

    /// Вызывается при запуске и при смене настроек. Пока обе функции выключены, перехвата нет.
    func apply(_ settings: ScrollSettings) {
        self.settings = settings
        if settings.changesAnything { tap.start() } else { tap.stop() }
    }

    func requestPermission() { tap.requestPermission() }
    func openPrivacySettings() { tap.permission.openSettings() }
    func refreshPermission() { tap.refreshPermission() }

    private func syncTapState() {
        hasPermission = tap.hasPermission
        isRunning = tap.isRunning
        lastError = tap.lastError
    }

    private func handle(_ event: CGEvent) {
        let input = ScrollEvent(
            vertical: ScrollAxis(lines: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                                 fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                                 points: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)),
            horizontal: ScrollAxis(lines: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                                   fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                                   points: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        guard let out = ScrollTransform.apply(input, settings) else { return }
        // Порядок важен: запись DeltaAxis пересчитывает FixedPt и Point по своей таблице, поэтому они — после
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: out.vertical.lines)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: out.vertical.fixed)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: out.vertical.points)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: out.horizontal.lines)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: out.horizontal.fixed)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: out.horizontal.points)
    }
}
