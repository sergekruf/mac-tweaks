import AppKit
import IOKit.hid
import IOKit.hidsystem
import PointerMath

/// Ускорение и скорость указателя мыши (как в LinearMouse). Меняет свойства HID-службы каждой мыши через
/// IOHIDServiceClient — разрешение не нужно. Тачпад не трогаем: у него тип ускорения HIDTrackpadAcceleration.
/// Свойства не сохраняются: сбрасываются при переподключении мыши, а ползунок «Скорость перемещения» в Системных настройках
/// перезаписывает ускорение. Поэтому, пока настройка включена, раз в 2 с сверяем значения и ставим заново.
@MainActor
final class MousePointer: ObservableObject {
    static let shared = MousePointer()

    /// Мыши, к которым применяется настройка.
    @Published private(set) var mice: [String] = []

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var settings = PointerSettings()
    /// Разрешение мыши до наших изменений (по RegistryID службы); nil внутри — у мыши свойство не было задано.
    private var initialResolution: [UInt64: Double?] = [:]
    /// Что мы сами записали в разрешение: у мышей на DriverKit (macOS 27.2) HIDPointerResolution не читается обратно.
    private var writtenResolution: [UInt64: Double] = [:]
    private var timer: Timer?

    private init() {
        reloadMice()
    }

    /// Вызывается при запуске и при смене настроек.
    /// Пока настройки не трогали, мыши не меняем вовсе (в том числе при запуске).
    func apply(_ settings: PointerSettings) {
        let wasDefault = self.settings.isDefault
        self.settings = settings
        if !(wasDefault && settings.isDefault) { sync() }
        timer?.invalidate()
        timer = nil
        guard !settings.isDefault else {
            // Вернули как было — мыши уже получили исходные значения, дальше не следим
            initialResolution = [:]
            writtenResolution = [:]
            return
        }
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MousePointer.shared.sync() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// При выходе из приложения — вернуть мышам системные значения.
    func restore() {
        guard !settings.isDefault else { return }
        settings = PointerSettings()
        sync()
    }

    func reloadMice() {
        mice = mouseServices().map { (string($0, kIOHIDProductKey) ?? "Мышь") }
    }

    // MARK: - HID

    private func mouseServices() -> [IOHIDServiceClient] {
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0
                && string($0, "HIDPointerAccelerationType") == kIOHIDMouseAccelerationType
        }
    }

    /// Ставит каждой мыши целевые значения, если они отличаются от текущих.
    private func sync() {
        let services = mouseServices()
        let system = fixed(IOHIDEventSystemClientCopyProperty(client, kIOHIDMouseAccelerationType as CFString)) ?? 0.5
        for service in services {
            let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            if initialResolution[id] == nil {
                initialResolution[id] = .some(fixed(IOHIDServiceClientCopyProperty(service, kIOHIDPointerResolutionKey as CFString)))
            }
            let target = PointerMath.targets(settings, systemAcceleration: system, initialResolution: initialResolution[id] ?? nil)
            let resolution = fixed(IOHIDServiceClientCopyProperty(service, kIOHIDPointerResolutionKey as CFString))
                ?? writtenResolution[id] ?? initialResolution[id].flatMap { $0 } ?? PointerMath.defaultResolution
            let acceleration = fixed(IOHIDServiceClientCopyProperty(service, kIOHIDMouseAccelerationType as CFString))
            if PointerMath.fixed(resolution) != PointerMath.fixed(target.resolution) {
                set(service, kIOHIDPointerResolutionKey, target.resolution)
                writtenResolution[id] = target.resolution
                // Новое разрешение вступает в силу только после повторной записи ускорения
                set(service, kIOHIDMouseAccelerationType, target.acceleration)
            } else if acceleration.map(PointerMath.fixed) != PointerMath.fixed(target.acceleration) {
                set(service, kIOHIDMouseAccelerationType, target.acceleration)
            }
        }
        let names = services.map { string($0, kIOHIDProductKey) ?? "Мышь" }
        if names != mice { mice = names }
    }

    private func set(_ service: IOHIDServiceClient, _ key: String, _ value: Double) {
        _ = IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: PointerMath.fixed(value)))
    }

    private func fixed(_ value: CFTypeRef?) -> Double? {
        (value as? NSNumber).map { PointerMath.double($0.int32Value) }
    }

    private func string(_ service: IOHIDServiceClient, _ key: String) -> String? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? String
    }
}
