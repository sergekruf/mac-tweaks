import AppKit
import Carbon
import KeyChord

/// Сочетание, по которому меняется язык ввода. Новые варианты (правый Cmd и т.п.) — новый кейс с аккордом.
/// Caps Lock сюда не ляжет как есть: он не держится, а переключает состояние — для него нужен
/// отдельный разбор flagsChanged (или переназначение через hidutil), детектор останется тем же.
enum LayoutHotkey: String, CaseIterable, Identifiable {
    case off
    case commandShift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Выключено"
        case .commandShift: "Command+Shift"
        }
    }

    var chord: ModifierChord? {
        switch self {
        case .off: nil
        case .commandShift: .commandShift
        }
    }
}

/// Раскладка из списка включённых в системе.
struct InputSourceInfo: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Перехват Cmd+Shift и переключение раскладки по кругу.
/// Перехват — listen-only CGEventTap (нужен «Мониторинг ввода»), событий не меняет и не глотает.
/// Переключение — TISSelectInputSource по списку включённых раскладок.
@MainActor
final class LayoutSwitcher: ObservableObject {
    static let shared = LayoutSwitcher()
    static let commandShiftBundleID = "vasybaran.loveFromUkraine.CommandShift"

    @Published private(set) var hasPermission = false
    @Published private(set) var isRunning = false
    @Published private(set) var sources: [InputSourceInfo] = []
    @Published private(set) var currentSourceID: String?
    @Published private(set) var lastError: String?

    private var detector: ModifierTapDetector?
    private let tap = EventTap(types: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
                               options: .listenOnly, permission: .inputMonitoring) { type, event in
        LayoutSwitcher.shared.handle(type, event)
    }

    private init() {
        reloadSources()
        let dnc = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged] {
            dnc.addObserver(forName: Notification.Name(name! as String), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LayoutSwitcher.shared.reloadSources() }
            }
        }
        tap.onChange = { [weak self] in self?.syncTapState() }
        syncTapState()
    }

    /// Включить или выключить перехват под выбранное сочетание (вызывается при запуске и при смене настройки).
    func apply(_ hotkey: LayoutHotkey) {
        tap.stop()
        guard let chord = hotkey.chord else { return }
        detector = ModifierTapDetector(chord: chord)
        tap.start()
    }

    func requestPermission() { tap.requestPermission() }
    func openPrivacySettings() { tap.permission.openSettings() }
    func refreshPermission() { tap.refreshPermission() }

    // MARK: - Перехват

    private func syncTapState() {
        hasPermission = tap.hasPermission
        if isRunning != tap.isRunning {
            isRunning = tap.isRunning
            detector?.reset()
        }
        lastError = tap.lastError
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Tap включён обратно — начинаем с чистого состояния
            detector?.reset()
        case .flagsChanged:
            if detector?.handle(.modifiers(Self.modifierKeys(event.flags))) == true {
                DispatchQueue.main.async { LayoutSwitcher.shared.selectNextSource() }
            }
        default:
            _ = detector?.handle(.otherKey)
        }
    }

    /// Зажатые модификаторы по битам левой/правой клавиши. Caps Lock — это состояние, а не зажатая клавиша, его не берём.
    nonisolated static func modifierKeys(_ flags: CGEventFlags) -> Set<ModifierKey> {
        let raw = flags.rawValue
        var keys: Set<ModifierKey> = []
        func side(_ mask: CGEventFlags, left: UInt64, right: UInt64, _ l: ModifierKey, _ r: ModifierKey) {
            guard flags.contains(mask) else { return }
            if raw & left != 0 { keys.insert(l) }
            if raw & right != 0 { keys.insert(r) }
            // Синтетические события бывают без битов стороны — считаем левой
            if raw & (left | right) == 0 { keys.insert(l) }
        }
        // Биты NX_DEVICE*KEYMASK из IOKit/hidsystem/IOLLEvent.h
        side(.maskCommand, left: 0x08, right: 0x10, .leftCommand, .rightCommand)
        side(.maskShift, left: 0x02, right: 0x04, .leftShift, .rightShift)
        side(.maskAlternate, left: 0x20, right: 0x40, .leftOption, .rightOption)
        side(.maskControl, left: 0x01, right: 0x2000, .leftControl, .rightControl)
        if flags.contains(.maskSecondaryFn) { keys.insert(.function) }
        return keys
    }

    // MARK: - Раскладки

    private func enabledSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceCategory! as String: kTISCategoryKeyboardInputSource! as String,
                      kTISPropertyInputSourceIsSelectCapable! as String: true] as CFDictionary
        let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        // У методов ввода с режимами (китайский, японский) выбираются сами режимы, а не родитель
        return list.filter { Self.string($0, kTISPropertyInputSourceType) != kTISTypeKeyboardInputMethodModeEnabled! as String }
    }

    func reloadSources() {
        sources = enabledSources().map {
            InputSourceInfo(id: Self.string($0, kTISPropertyInputSourceID) ?? "?",
                            name: Self.string($0, kTISPropertyLocalizedName) ?? "?")
        }
        currentSourceID = TISCopyCurrentKeyboardInputSource().map { Self.string($0.takeRetainedValue(), kTISPropertyInputSourceID) } ?? nil
    }

    func selectNextSource() {
        let list = enabledSources()
        guard list.count > 1 else { return }
        let current = TISCopyCurrentKeyboardInputSource().map { Self.string($0.takeRetainedValue(), kTISPropertyInputSourceID) } ?? nil
        let index = list.firstIndex { Self.string($0, kTISPropertyInputSourceID) == current } ?? -1
        let next = list[(index + 1) % list.count]
        let status = TISSelectInputSource(next)
        lastError = status == noErr ? nil : "Не удалось переключить раскладку (код \(status))."
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
