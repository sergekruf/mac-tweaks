/// Что Mac Tweaks делает с указателем мыши. Значения пишутся в свойства HID-службы мыши:
/// `HIDUseLinearScalingMouseAcceleration` (1 — линейный режим, без разгона) и `HIDMouseAcceleration`
/// (в линейном режиме — просто множитель скорости, в обычном — кривая ускорения от ползунка «Скорость перемещения»).
public struct PointerSettings: Equatable {
    /// Курсор движется строго пропорционально мыши, как в Windows без «Повышенной точности».
    public var linear: Bool
    /// Скорость в линейном режиме (значение HIDMouseAcceleration).
    public var speed: Double

    public static let speedRange = 0.2...5.0
    public static let defaultSpeed = 1.5

    public init(linear: Bool = false, speed: Double = defaultSpeed) {
        self.linear = linear
        self.speed = speed
    }

    /// Ничего не меняем — у мыши системные значения.
    public var isDefault: Bool { !linear }
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
    /// - Parameters:
    ///   - systemAcceleration: ускорение из Системных настроек (ползунок «Скорость перемещения»).
    ///   - systemLinear: системный флаг линейного режима (`com.apple.mouse.linear`) — его и возвращаем при сбросе.
    public static func targets(_ settings: PointerSettings, systemAcceleration: Double, systemLinear: Bool) -> PointerTargets {
        guard settings.linear else { return PointerTargets(linear: systemLinear, acceleration: systemAcceleration) }
        let speed = min(max(settings.speed, PointerSettings.speedRange.lowerBound), PointerSettings.speedRange.upperBound)
        return PointerTargets(linear: true, acceleration: speed)
    }

    /// IOFixed (16.16) ↔ Double — так HIDMouseAcceleration хранится в HID.
    public static func fixed(_ value: Double) -> Int32 { Int32((value * 65_536).rounded()) }
    public static func double(_ fixed: Int32) -> Double { Double(fixed) / 65_536 }
}
