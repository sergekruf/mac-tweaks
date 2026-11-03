import Foundation

/// Кривая «Повышенной точности указателя» Windows (значения по умолчанию SmoothMouseXCurve/SmoothMouseYCurve).
/// X — скорость мыши: отсчёты за кадр 1/60 с, делённые на 3,5; Y — скорость указателя. Между точками — прямые.
/// Нам нужна только форма: во сколько раз коэффициент на этой скорости больше, чем на самых медленных движениях.
/// Абсолютный масштаб задаёт пользователь ползунком («скорость на медленных движениях»).
public enum WindowsCurve {
    static let speeds: [Double] = [0, 0.43, 1.25, 3.86, 40]
    static let outputs: [Double] = [0, 1.37, 5.30, 24.30, 568]

    /// Коэффициент на медленных движениях (первый отрезок).
    static var slowGain: Double { outputs[1] / speeds[1] }

    /// Множитель пишется ступенями по ~10 %, чтобы не дёргать систему на каждый отсчёт мыши:
    /// от медленных до самых быстрых движений — около 16 ступеней.
    public static let stepRatio = 1.1
    public static let maxMultiplier = 10.0

    /// Скорость по Windows из отсчётов мыши в секунду.
    public static func windowsSpeed(countsPerSecond: Double) -> Double {
        countsPerSecond / 60 / 3.5
    }

    /// 1 на медленных движениях, около 4,5 на самых быстрых.
    public static func relativeGain(windowsSpeed x: Double) -> Double {
        guard x > speeds[1] else { return 1 }
        guard x < speeds[speeds.count - 1] else { return (outputs[outputs.count - 1] / speeds[speeds.count - 1]) / slowGain }
        let i = speeds.lastIndex { $0 <= x }!
        let t = (x - speeds[i]) / (speeds[i + 1] - speeds[i])
        let y = outputs[i] + t * (outputs[i + 1] - outputs[i])
        return (y / x) / slowGain
    }

    /// Множитель HIDMouseAcceleration для текущей скорости мыши.
    public static func multiplier(countsPerSecond: Double, base: Double) -> Double {
        let gain = relativeGain(windowsSpeed: windowsSpeed(countsPerSecond: countsPerSecond))
        let steps = (log(gain) / log(stepRatio)).rounded()
        return min(base * pow(stepRatio, steps), maxMultiplier)
    }
}

/// Сглаженная скорость мыши по сырым отсчётам. Пауза дольше `idle` — новое движение, скорость начинается с нуля,
/// поэтому первые отсчёты после остановки идут с «медленным» множителем — для точного наведения.
public struct MotionSpeed {
    public private(set) var countsPerSecond: Double = 0
    private var lastTime: Double?

    /// Постоянная сглаживания, с.
    public static let smoothing = 0.03
    /// Пауза, после которой движение считается новым, с.
    public static let idle = 0.08
    /// Интервал отчётов мыши по умолчанию (125 Гц) — для первого отсчёта движения.
    static let defaultInterval = 0.008

    public init() {}

    /// - Parameters:
    ///   - dx, dy: сдвиг в отсчётах мыши за один отчёт.
    ///   - time: время отчёта, с.
    @discardableResult
    public mutating func add(dx: Double, dy: Double, time: Double) -> Double {
        var dt = Self.defaultInterval
        if let lastTime, time - lastTime < Self.idle {
            dt = max(time - lastTime, 0.001)
        } else {
            countsPerSecond = 0
        }
        lastTime = time
        let instant = (dx * dx + dy * dy).squareRoot() / dt
        countsPerSecond += (1 - exp(-dt / Self.smoothing)) * (instant - countsPerSecond)
        return countsPerSecond
    }

    public mutating func reset() {
        countsPerSecond = 0
        lastTime = nil
    }
}
