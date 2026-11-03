import AppKit
import IOKit.hid
import IOKit.hidsystem
import PointerMath

/// Указатель мыши. Обычному процессу на macOS 27.2 из настроек ускорения доступно только свойство HID-службы
/// `HIDMouseAcceleration` (флаг линейного режима и свои кривые `HIDAccelCurves` система не принимает). У мышей, для которых
/// в системе выключено «Ускорение указателя» (`com.apple.mouse.linear = 1`), это просто множитель скорости:
/// - «Без ускорения» — постоянный множитель;
/// - «Как в Windows» — множитель меняется на лету по скорости мыши (кривая `WindowsCurve`). Скорость меряется по сырым отсчётам
///   мыши через IOHIDManager — для этого нужен «Мониторинг ввода». Курсор двигает сама система, мы только меняем множитель.
/// Тачпад не трогаем: у него тип ускорения HIDTrackpadAcceleration. Свойства сбрасываются при переподключении мыши,
/// поэтому, пока режим не системный, раз в 2 с сверяем значения и ставим заново.
@MainActor
final class MousePointer: ObservableObject {
    static let shared = MousePointer()

    /// Мыши, к которым применяется настройка.
    @Published private(set) var mice: [String] = []
    /// Для «Как в Windows»: есть ли «Мониторинг ввода» и открыт ли поток отсчётов мыши.
    @Published private(set) var motionPermission = EventTapPermission.inputMonitoring.isGranted
    @Published private(set) var motionRunning = false

    private var settings = PointerSettings()
    /// Службы мышей живут, пока жив клиент, который их вернул: освобождённый клиент роняет приложение при обращении к службе.
    /// Поэтому клиент хранится вместе со списком и заменяется новым при каждой проверке.
    private var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var services: [IOHIDServiceClient] = []
    private var timer: Timer?

    // «Как в Windows»
    private var manager: IOHIDManager?
    private var speed = MotionSpeed()
    /// Последний записанный множитель.
    private var multiplier: Double?
    /// Отсчёты X и Y одного отчёта мыши приходят отдельными значениями с одним временем — собираем их вместе.
    private var pending: (time: UInt64, dx: Double, dy: Double)?
    /// Когда пришло последнее значение (mach_absolute_time). Время самих значений HID в другой шкале — для пауз не годится.
    private var lastValueReceived: UInt64 = 0
    private var idleCheckScheduled = false
    /// Мыши среди устройств IOHIDManager (без тачпадов), по адресу устройства.
    private var isMouseDevice: [UnsafeMutableRawPointer: Bool] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private init() {
        reloadMice()
    }

    /// Вызывается при запуске и при смене настроек.
    /// Пока режим системный, мыши не меняем вовсе (в том числе при запуске).
    func apply(_ settings: PointerSettings) {
        let wasDefault = self.settings.isDefault
        self.settings = settings
        multiplier = nil
        if settings.mode == .windows { startMotion() } else { stopMotion() }
        if !(wasDefault && settings.isDefault) { sync() }
        timer?.invalidate()
        timer = nil
        guard !settings.isDefault else { return }
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MousePointer.shared.sync() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// При выходе из приложения — вернуть мышам системные значения.
    func restore() {
        guard !settings.isDefault else { return }
        stopMotion()
        settings = PointerSettings()
        multiplier = nil
        sync()
    }

    func reloadMice() {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        services = mouseServices(client)
        mice = services.map { string($0, kIOHIDProductKey) ?? "Мышь" }
        motionPermission = EventTapPermission.inputMonitoring.isGranted
    }

    /// Флаг линейного режима из системы: без него множитель работает как уровень кривой Apple, а не как скорость.
    var systemLinear: Bool { UserDefaults.standard.bool(forKey: "com.apple.mouse.linear") }

    // MARK: - Свойства мыши

    /// Клиент нужен свежий: у долгоживущего простого клиента список служб не обновляется,
    /// и переподключённая мышь в нём не появляется (проверено на macOS 27.2).
    private func mouseServices(_ client: IOHIDEventSystemClient) -> [IOHIDServiceClient] {
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0
                && string($0, "HIDPointerAccelerationType") == kIOHIDMouseAccelerationType
        }
    }

    /// Ставит каждой мыши целевое значение, если оно отличается от текущего.
    private func sync() {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        services = mouseServices(client)
        let system = fixed(IOHIDEventSystemClientCopyProperty(client, kIOHIDMouseAccelerationType as CFString)) ?? 0.5
        let target = multiplier ?? PointerMath.targets(settings, systemAcceleration: system, systemLinear: systemLinear).acceleration
        for service in services {
            let acceleration = fixed(IOHIDServiceClientCopyProperty(service, kIOHIDMouseAccelerationType as CFString))
            if acceleration.map(PointerMath.fixed) != PointerMath.fixed(target) {
                set(service, target)
            }
        }
        let names = services.map { string($0, kIOHIDProductKey) ?? "Мышь" }
        if names != mice { mice = names }
        motionPermission = EventTapPermission.inputMonitoring.isGranted
    }

    /// Каждая запись пересобирает ускоритель в WindowServer и пишет строку в системный лог, а при движении ступень
    /// меняется ~50 раз в секунду (проверено) — поэтому разгон пишем не чаще раза в 40 мс. Торможение — сразу,
    /// иначе курсор проскакивает цель.
    private static let minWriteInterval = 0.04
    private var lastWrite: UInt64 = 0

    private func setMultiplier(_ value: Double, force: Bool = false) {
        guard value != multiplier else { return }
        let now = mach_absolute_time()
        let slowingDown = multiplier.map { value < $0 } ?? true
        guard force || slowingDown || seconds(now - lastWrite) >= Self.minWriteInterval else { return }
        lastWrite = now
        multiplier = value
        for service in services { set(service, value) }
    }

    private func set(_ service: IOHIDServiceClient, _ value: Double) {
        _ = IOHIDServiceClientSetProperty(service, kIOHIDMouseAccelerationType as CFString, NSNumber(value: PointerMath.fixed(value)))
    }

    private func fixed(_ value: CFTypeRef?) -> Double? {
        (value as? NSNumber).map { PointerMath.double($0.int32Value) }
    }

    private func string(_ service: IOHIDServiceClient, _ key: String) -> String? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? String
    }

    // MARK: - «Как в Windows»: скорость мыши по сырым отсчётам

    private func startMotion() {
        guard manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
                                          kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(m, motionCallback, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        motionRunning = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        motionPermission = EventTapPermission.inputMonitoring.isGranted
        manager = m
        speed.reset()
    }

    private func stopMotion() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        motionRunning = false
        pending = nil
        isMouseDevice = [:]
    }

    fileprivate func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == kHIDPage_GenericDesktop else { return }
        let usage = Int(IOHIDElementGetUsage(element))
        guard usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y, isMouse(IOHIDElementGetDevice(element)) else { return }
        let time = IOHIDValueGetTimeStamp(value)
        if let p = pending, p.time != time { flush() }
        var p = pending ?? (time, 0, 0)
        let delta = Double(IOHIDValueGetIntegerValue(value))
        if usage == kHIDUsage_GD_X { p.dx += delta } else { p.dy += delta }
        pending = p
        lastValueReceived = mach_absolute_time()
        scheduleIdleCheck()
    }

    private func flush() {
        guard let p = pending, manager != nil else { return }
        pending = nil
        let cps = speed.add(dx: p.dx, dy: p.dy, time: seconds(p.time))
        setMultiplier(WindowsCurve.multiplier(countsPerSecond: cps, base: settings.windowsSpeed, strength: settings.windowsStrength))
    }

    /// Последний отчёт движения не ждёт следующего; после паузы множитель возвращается к «медленному».
    private func scheduleIdleCheck() {
        guard !idleCheckScheduled else { return }
        idleCheckScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            MainActor.assumeIsolated {
                let me = MousePointer.shared
                me.idleCheckScheduled = false
                guard me.manager != nil else { return }
                let age = me.seconds(mach_absolute_time() - me.lastValueReceived)
                if age > 0.012 { me.flush() }
                if age > MotionSpeed.idle {
                    me.speed.reset()
                    me.setMultiplier(WindowsCurve.multiplier(countsPerSecond: 0, base: me.settings.windowsSpeed), force: true)
                } else {
                    me.scheduleIdleCheck()
                }
            }
        }
    }

    private func isMouse(_ device: IOHIDDevice) -> Bool {
        let key = Unmanaged.passUnretained(device).toOpaque()
        if let known = isMouseDevice[key] { return known }
        let builtIn = (IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? Bool) ?? false
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let mouse = !builtIn && !product.localizedCaseInsensitiveContains("trackpad")
        isMouseDevice[key] = mouse
        return mouse
    }

    private func seconds(_ machTime: UInt64) -> Double {
        Double(machTime) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}

/// IOHIDManager запланирован в главном run loop, поэтому колбэк приходит на главном потоке.
private func motionCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    MainActor.assumeIsolated { MousePointer.shared.handle(value) }
}
