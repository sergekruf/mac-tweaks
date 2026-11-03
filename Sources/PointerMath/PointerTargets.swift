/// Что Mac Tweaks делает с указателем мыши. Значения пишутся в свойства HID-службы мыши:
/// `HIDMouseAcceleration` (кривая ускорения, −1 — без ускорения) и `HIDPointerResolution` (чем меньше, тем быстрее курсор).
public struct PointerSettings: Equatable {
    /// Курсор движется строго пропорционально мыши, как в Windows без «Повышенной точности».
    public var disableAcceleration: Bool
    /// Множитель скорости относительно исходной у мыши; 1 — как было.
    public var speed: Double

    public static let speedRange = 0.3...3.0

    public init(disableAcceleration: Bool = false, speed: Double = 1) {
        self.disableAcceleration = disableAcceleration
        self.speed = speed
    }

    /// Ничего не меняем — значения мыши должны совпадать с системными.
    public var isDefault: Bool { !disableAcceleration && speed == 1 }
}

/// Значения, которые должны стоять у одной мыши.
public struct PointerTargets: Equatable {
    public var acceleration: Double
    public var resolution: Double

    public init(acceleration: Double, resolution: Double) {
        self.acceleration = acceleration
        self.resolution = resolution
    }
}

public enum PointerMath {
    /// Без ускорения — особое значение HIDMouseAcceleration.
    public static let noAcceleration = -1.0
    /// Разрешение по умолчанию, если у мыши свойство не задано (400 точек на дюйм, как в IOHIDFamily).
    public static let defaultResolution = 400.0
    /// Пределы HIDPointerResolution, которые принимает система.
    public static let resolutionRange = 10.0...1995.0

    /// - Parameters:
    ///   - systemAcceleration: текущее ускорение из Системных настроек (ползунок «Скорость перемещения»).
    ///   - initialResolution: разрешение мыши до того, как Mac Tweaks его менял; nil — не было задано.
    public static func targets(_ settings: PointerSettings, systemAcceleration: Double, initialResolution: Double?) -> PointerTargets {
        let base = initialResolution ?? defaultResolution
        let speed = min(max(settings.speed, PointerSettings.speedRange.lowerBound), PointerSettings.speedRange.upperBound)
        let resolution = min(max(base / speed, resolutionRange.lowerBound), resolutionRange.upperBound)
        return PointerTargets(acceleration: settings.disableAcceleration ? noAcceleration : systemAcceleration,
                              resolution: speed == 1 ? base : resolution)
    }

    /// IOFixed (16.16) ↔ Double — так эти свойства хранятся в HID.
    public static func fixed(_ value: Double) -> Int32 { Int32((value * 65_536).rounded()) }
    public static func double(_ fixed: Int32) -> Double { Double(fixed) / 65_536 }
}
