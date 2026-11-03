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

    public static let maxMultiplier = 10.0
    /// Новый множитель пишется, только если отличается от текущего больше чем на 8 %. Без такого порога на постоянной
    /// скорости множитель прыгал вверх-вниз: у ступеней по 10 % почти половина смен были разворотами (по записи движений
    /// пользователя: 695 из 1477 за 60 с), курсор вёл себя чуть по-разному на одинаковых движениях.
    public static let hysteresis = 0.08

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
    /// - Parameter strength: сила ускорения: 1 — как в Windows (до ~4,5 раза), 0 — без ускорения, между — пропорционально.
    public static func multiplier(countsPerSecond: Double, base: Double, strength: Double = 1) -> Double {
        let full = relativeGain(windowsSpeed: windowsSpeed(countsPerSecond: countsPerSecond))
        let gain = 1 + min(max(strength, 0), 1) * (full - 1)
        return min(base * gain, maxMultiplier)
    }

    /// Стоит ли менять записанный множитель на новый.
    public static func shouldUpdate(current: Double?, to value: Double) -> Bool {
        guard let current else { return true }
        return abs(log(value / current)) > log(1 + hysteresis)
    }
}

/// Сглаженная скорость мыши по сырым отсчётам. Пауза дольше `idle` — новое движение, скорость начинается с нуля,
/// поэтому первые отсчёты после остановки идут с «медленным» множителем — для точного наведения.
/// Скорость считается по окну в 16 мс, а не по одному отчёту: по Bluetooth отчёты приходят неровно (бывают склеенные),
/// и скорость отдельного отчёта скачет. Разгон сглаживается медленнее, торможение — быстро: иначе при подходе к цели
/// курсор ещё летит с большим множителем и проскакивает её (так было с одной постоянной 30 мс).
/// Параметры подобраны на записи движений пользователя (M240 B по Bluetooth, отчёты ~7,5 мс).
public struct MotionSpeed {
    public private(set) var countsPerSecond: Double = 0
    private var lastTime: Double?
    private var window: [(time: Double, distance: Double)] = []

    /// Окно, по которому считается скорость, с.
    public static let window = 0.016
    /// Постоянные сглаживания при разгоне и торможении, с.
    public static let smoothingUp = 0.04
    public static let smoothingDown = 0.01
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
            window = []
        }
        lastTime = time
        window.append((time, (dx * dx + dy * dy).squareRoot()))
        window.removeAll { time - $0.time >= Self.window }
        // Длительность окна: от первого отчёта в нём плюс один интервал — сам этот отчёт тоже занимает время
        let span = time - window[0].time + Self.defaultInterval
        let instant = window.reduce(0) { $0 + $1.distance } / span
        let tau = instant > countsPerSecond ? Self.smoothingUp : Self.smoothingDown
        countsPerSecond += (1 - exp(-dt / tau)) * (instant - countsPerSecond)
        return countsPerSecond
    }

    public mutating func reset() {
        countsPerSecond = 0
        lastTime = nil
        window = []
    }
}
