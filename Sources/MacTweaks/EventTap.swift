import AppKit
import ApplicationServices

/// Разрешение, без которого CGEventTap не создаётся.
enum EventTapPermission {
    /// listen-only tap — только слушает события.
    case inputMonitoring
    /// Активный tap, который меняет события.
    case accessibility

    var title: String {
        switch self {
        case .inputMonitoring: "Мониторинг ввода"
        case .accessibility: "Универсальный доступ"
        }
    }

    var isGranted: Bool {
        switch self {
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Системный запрос; заодно добавляет Mac Tweaks в список в Системных настройках.
    func request() {
        switch self {
        case .inputMonitoring: CGRequestListenEventAccess()
        case .accessibility: _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    func openSettings() {
        let pane = switch self {
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

/// CGEventTap в главном run loop: работает, пока приложение запущено, и с закрытым окном.
/// После start() сам следит за разрешением: выдали — создаёт tap без перезапуска приложения, отозвали — снимает.
/// Если система отключает tap (tapDisabledByTimeout/UserInput), включает его обратно и передаёт это событие в handler,
/// чтобы владелец мог сбросить своё состояние.
/// Handler вызывается на главном потоке и может менять событие на месте (для активного tap) — он должен быть быстрым.
@MainActor
final class EventTap {
    let permission: EventTapPermission
    private(set) var hasPermission: Bool
    private(set) var isRunning = false
    private(set) var lastError: String?
    /// Вызывается при смене hasPermission, isRunning или lastError.
    var onChange: (() -> Void)?

    private let mask: CGEventMask
    private let options: CGEventTapOptions
    private let handler: (CGEventType, CGEvent) -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchTimer: Timer?

    init(types: [CGEventType], options: CGEventTapOptions, permission: EventTapPermission,
         handler: @escaping (CGEventType, CGEvent) -> Void) {
        self.mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        self.options = options
        self.permission = permission
        self.handler = handler
        self.hasPermission = permission.isGranted
    }

    func start() {
        guard watchTimer == nil else { return }
        createTap()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchPermission() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
    }

    func stop() {
        watchTimer?.invalidate()
        watchTimer = nil
        removeTap()
        lastError = nil
        onChange?()
    }

    func requestPermission() {
        permission.request()
        refreshPermission()
    }

    func refreshPermission() {
        let granted = permission.isGranted
        guard granted != hasPermission else { return }
        hasPermission = granted
        onChange?()
    }

    private func watchPermission() {
        refreshPermission()
        if hasPermission && port == nil {
            createTap()
        } else if !hasPermission && port != nil {
            removeTap()
            onChange?()
        }
    }

    private func createTap() {
        refreshPermission()
        guard hasPermission, port == nil else { return }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: options, eventsOfInterest: mask,
                                           callback: eventTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lastError = "Разрешение есть, но перехват не запустился. Перезапустите Mac Tweaks."
            onChange?()
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        lastError = nil
        isRunning = true
        onChange?()
    }

    private func removeTap() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        isRunning = false
    }

    fileprivate func dispatch(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        handler(type, event)
    }
}

/// Tap добавлен в главный run loop, поэтому колбэк приходит на главном потоке.
/// Событие всегда пропускается дальше (изменённым на месте, если handler его поменял).
private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        MainActor.assumeIsolated { tap.dispatch(type, event) }
    }
    return Unmanaged.passUnretained(event)
}

/// Какие приложения запущены — для предупреждений о конфликтующих утилитах (CommandShift, LinearMouse).
@MainActor
final class RunningApps: ObservableObject {
    static let shared = RunningApps()

    @Published private(set) var identifiers: Set<String> = []

    private init() {
        reload()
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { RunningApps.shared.reload() }
            }
        }
    }

    /// Запущено ли приложение с таким bundle id или именем.
    func contains(bundleID: String, name: String) -> Bool {
        identifiers.contains(bundleID) || identifiers.contains(name)
    }

    private func reload() {
        var ids: Set<String> = []
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { ids.insert(id) }
            if let name = app.localizedName { ids.insert(name) }
        }
        identifiers = ids
    }
}
