import AppKit
import IOKit.hid
import IOKit.hidsystem
import PointerMath

/// Указатель мыши без ускорения и его скорость. Меняет свойства HID-службы каждой мыши через IOHIDServiceClient —
/// разрешение не нужно: линейный режим (HIDUseLinearScalingMouseAcceleration = 1), в котором HIDMouseAcceleration —
/// просто множитель скорости. Тачпад не трогаем: у него тип ускорения HIDTrackpadAcceleration.
/// Свойства не сохраняются: сбрасываются при переподключении мыши, а ползунок «Скорость перемещения» в Системных настройках
/// перезаписывает ускорение. Поэтому, пока настройка включена, раз в 2 с сверяем значения и ставим заново.
@MainActor
final class MousePointer: ObservableObject {
    static let shared = MousePointer()

    /// Мыши, к которым применяется настройка.
    @Published private(set) var mice: [String] = []

    private var settings = PointerSettings()
    /// Какой режим мы записали мыши (по RegistryID службы): HIDUseLinearScalingMouseAcceleration со службы не читается.
    private var writtenLinear: [UInt64: Bool] = [:]
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
            writtenLinear = [:]
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
        mice = mouseServices(IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)).map { (string($0, kIOHIDProductKey) ?? "Мышь") }
    }

    // MARK: - HID

    /// Клиент создаётся заново при каждом вызове: у долгоживущего простого клиента список служб не обновляется,
    /// и переподключённая мышь в нём не появляется (проверено на macOS 27.2).
    private func mouseServices(_ client: IOHIDEventSystemClient) -> [IOHIDServiceClient] {
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0
                && string($0, "HIDPointerAccelerationType") == kIOHIDMouseAccelerationType
        }
    }

    /// Ставит каждой мыши целевые значения, если они отличаются от текущих.
    private func sync() {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = mouseServices(client)
        let system = fixed(IOHIDEventSystemClientCopyProperty(client, kIOHIDMouseAccelerationType as CFString)) ?? 0.5
        // Через HID-клиент системный флаг не читается — берём из настройки, которую пишут Системные настройки
        let systemLinear = UserDefaults.standard.bool(forKey: "com.apple.mouse.linear")
        for service in services {
            let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            let target = PointerMath.targets(settings, systemAcceleration: system, systemLinear: systemLinear)
            let acceleration = fixed(IOHIDServiceClientCopyProperty(service, kIOHIDMouseAccelerationType as CFString))
            // Флаг со службы не читается — сравниваем с тем, что записали сами; при сбросе пишем системный
            if writtenLinear[id] != target.linear {
                _ = IOHIDServiceClientSetProperty(service, kIOHIDUseLinearScalingMouseAccelerationKey as CFString,
                                                  NSNumber(value: target.linear ? 1 : 0))
                writtenLinear[id] = target.linear
                // Режим вступает в силу после записи ускорения
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
