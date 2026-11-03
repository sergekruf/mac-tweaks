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

    @Published private(set) var hasPermission = CGPreflightListenEventAccess()
    @Published private(set) var isRunning = false
    @Published private(set) var sources: [InputSourceInfo] = []
    @Published private(set) var currentSourceID: String?
    @Published private(set) var commandShiftRunning = false
    @Published private(set) var lastError: String?

    private var hotkey: LayoutHotkey = .off
    private var detector: ModifierTapDetector?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var watchTimer: Timer?

    private init() {
        reloadSources()
        let dnc = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged] {
            dnc.addObserver(forName: Notification.Name(name! as String), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LayoutSwitcher.shared.reloadSources() }
            }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LayoutSwitcher.shared.checkCommandShift() }
            }
        }
        checkCommandShift()
    }

    /// Включить или выключить перехват под выбранное сочетание (вызывается при запуске и при смене настройки).
    func apply(_ hotkey: LayoutHotkey) {
        self.hotkey = hotkey
        stopTap()
        watchTimer?.invalidate(); watchTimer = nil
        guard let chord = hotkey.chord else { return }
        detector = ModifierTapDetector(chord: chord)
        startTapIfPossible()
        // Разрешение могут выдать или отозвать, пока приложение работает
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { LayoutSwitcher.shared.watchPermission() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
    }

    /// Показывает системный запрос и добавляет Mac Tweaks в список «Мониторинга ввода».
    func requestPermission() {
        CGRequestListenEventAccess()
        refreshPermission()
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    func refreshPermission() {
        hasPermission = CGPreflightListenEventAccess()
    }

    // MARK: - Перехват

    private func watchPermission() {
        refreshPermission()
        if hasPermission && tap == nil {
            startTapIfPossible()
        } else if !hasPermission && tap != nil {
            stopTap()
        }
    }

    private func startTapIfPossible() {
        refreshPermission()
        guard hasPermission, tap == nil else { return }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .listenOnly, eventsOfInterest: mask,
                                           callback: tapCallback, userInfo: nil) else {
            lastError = "Разрешение есть, но перехват не запустился. Перезапустите Mac Tweaks."
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        detector?.reset()
        lastError = nil
        isRunning = true
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        isRunning = false
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Система отключает медленный tap — включаем обратно и начинаем с чистого состояния
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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

    // MARK: - CommandShift

    private func checkCommandShift() {
        commandShiftRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.commandShiftBundleID || $0.localizedName == "CommandShift"
        }
    }
}

/// Tap добавлен в главный run loop, поэтому колбэк приходит на главном потоке.
private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolated { LayoutSwitcher.shared.handle(type, event) }
    return Unmanaged.passUnretained(event)
}
