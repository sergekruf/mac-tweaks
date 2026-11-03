/// Как Mac Tweaks ведёт указатель мыши.
public enum PointerMode: String, CaseIterable, Identifiable {
    /// Не трогаем — как настроено в системе.
    case system
    /// Без ускорения: постоянный множитель скорости.
    case linear
    /// Как «Повышенная точность указателя» в Windows: множитель меняется на лету по скорости мыши.
    case windows

    public var id: String { rawValue }
}

/// Значения пишутся в свойство HID-службы мыши `HIDMouseAcceleration`. У мышей, для которых в системе выключено
/// «Ускорение указателя» (`com.apple.mouse.linear = 1`, линейный режим), это просто множитель скорости.
/// Флаг линейного режима обычный процесс поменять не может (проверено на macOS 27.2) — он только читается из настроек.
public struct PointerSettings: Equatable {
    public var mode: PointerMode
    /// Множитель в режиме «Без ускорения».
    public var speed: Double
    /// Множитель на медленных движениях в режиме «Как в Windows»; на быстрых он растёт по кривой Windows.
    public var windowsSpeed: Double

    public static let speedRange = 0.2...5.0
    public static let defaultSpeed = 1.5
    public static let windowsSpeedRange = 0.2...2.0
    public static let defaultWindowsSpeed = 0.6

    public init(mode: PointerMode = .system, speed: Double = defaultSpeed, windowsSpeed: Double = defaultWindowsSpeed) {
        self.mode = mode
        self.speed = speed
        self.windowsSpeed = windowsSpeed
    }

    /// Ничего не меняем — у мыши системные значения.
    public var isDefault: Bool { mode == .system }
}

/// Значения, которые должны стоять у одной мыши.
public struct PointerTargets: Equatable {
    public var linear: Bool
    public var acceleration: Double

    public init(linear: Bool, acceleration: Double) {
        self.linear = linear
        self.acceleration = acceleration
    }
}

public enum PointerMath {
    /// Значения мыши в покое. В режиме «Как в Windows» — множитель для медленных движений, с него начинается каждое движение.
    /// - Parameters:
    ///   - systemAcceleration: ускорение из Системных настроек (ползунок «Скорость перемещения»).
    ///   - systemLinear: системный флаг линейного режима (`com.apple.mouse.linear`) — его и возвращаем при сбросе.
    public static func targets(_ settings: PointerSettings, systemAcceleration: Double, systemLinear: Bool) -> PointerTargets {
        switch settings.mode {
        case .system:
            return PointerTargets(linear: systemLinear, acceleration: systemAcceleration)
        case .linear:
            return PointerTargets(linear: true, acceleration: clamp(settings.speed, PointerSettings.speedRange))
        case .windows:
            return PointerTargets(linear: true, acceleration: WindowsCurve.multiplier(countsPerSecond: 0, base: settings.windowsSpeed))
        }
    }

    /// IOFixed (16.16) ↔ Double — так HIDMouseAcceleration хранится в HID.
    public static func fixed(_ value: Double) -> Int32 { Int32((value * 65_536).rounded()) }
    public static func double(_ fixed: Int32) -> Double { Double(fixed) / 65_536 }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
