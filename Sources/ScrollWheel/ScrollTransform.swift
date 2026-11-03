/// Дельты прокрутки по одной оси — три поля CGEvent, которые разные приложения читают по-разному:
/// `DeltaAxis` (целые строки), `FixedPtDeltaAxis` (строки с дробной частью, его читает AppKit как deltaY),
/// `PointDeltaAxis` (точки). Чтобы Safari, Chrome и Finder прокручивали одинаково, их надо менять согласованно.
public struct ScrollAxis: Equatable {
    public var lines: Int64
    public var fixed: Double
    public var points: Double

    public init(lines: Int64, fixed: Double, points: Double) {
        self.lines = lines
        self.fixed = fixed
        self.points = points
    }

    public static let zero = ScrollAxis(lines: 0, fixed: 0, points: 0)

    /// Направление: -1, 0 или 1. Берём первое ненулевое поле: при медленной прокрутке строки могут быть 0, а дробь — нет.
    var direction: Int64 {
        if fixed != 0 { return fixed > 0 ? 1 : -1 }
        if lines != 0 { return lines > 0 ? 1 : -1 }
        if points != 0 { return points > 0 ? 1 : -1 }
        return 0
    }

    var negated: ScrollAxis { ScrollAxis(lines: -lines, fixed: -fixed, points: -points) }
}

/// Значения события scrollWheel, которые нужны для решения.
public struct ScrollEvent: Equatable {
    /// Axis1 — вертикаль (в том числе Shift + колесо: в горизонталь её превращает уже приложение), Axis2 — горизонталь (наклон колеса).
    public var vertical: ScrollAxis
    public var horizontal: ScrollAxis
    /// `kCGScrollWheelEventIsContinuous`: 1 у тачпада, Magic Mouse и других устройств с плавной прокруткой.
    public var isContinuous: Bool
    public var scrollPhase: Int64
    public var momentumPhase: Int64

    public init(vertical: ScrollAxis, horizontal: ScrollAxis = .zero, isContinuous: Bool = false,
                scrollPhase: Int64 = 0, momentumPhase: Int64 = 0) {
        self.vertical = vertical
        self.horizontal = horizontal
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
    }

    /// Обычный щелчок колеса мыши на `lines` строк (без ускорения), как его присылает система.
    public static func wheel(lines: Int64, horizontal: Int64 = 0, pointsPerLine: Double = ScrollSettings.systemPointsPerLine) -> ScrollEvent {
        ScrollEvent(vertical: ScrollAxis(lines: lines, fixed: Double(lines), points: Double(lines) * pointsPerLine),
                    horizontal: ScrollAxis(lines: horizontal, fixed: Double(horizontal), points: Double(horizontal) * pointsPerLine))
    }
}

public struct ScrollSettings: Equatable {
    /// Столько точек в строке у события колеса, которое собирает сама система (проверено на macOS 27.2).
    public static let systemPointsPerLine: Double = 10

    /// Обратить направление колеса мыши (тачпад не трогаем).
    public var reverseWheel: Bool
    /// Строк за один щелчок колеса без ускорения; nil — как в системе.
    public var linesPerNotch: Int?
    public var pointsPerLine: Double

    public init(reverseWheel: Bool = false, linesPerNotch: Int? = nil, pointsPerLine: Double = systemPointsPerLine) {
        self.reverseWheel = reverseWheel
        self.linesPerNotch = linesPerNotch
        self.pointsPerLine = pointsPerLine
    }

    public var changesAnything: Bool { reverseWheel || linesPerNotch != nil }
}

public enum ScrollTransform {
    /// Новые дельты для события колеса мыши или nil, если событие надо пропустить как есть:
    /// тачпад и Magic Mouse (continuous), события с фазами и инерцией, или когда обе функции выключены.
    public static func apply(_ event: ScrollEvent, _ settings: ScrollSettings) -> (vertical: ScrollAxis, horizontal: ScrollAxis)? {
        guard settings.changesAnything, !event.isContinuous,
              event.scrollPhase == 0, event.momentumPhase == 0 else { return nil }
        return (axis(event.vertical, settings), axis(event.horizontal, settings))
    }

    private static func axis(_ value: ScrollAxis, _ settings: ScrollSettings) -> ScrollAxis {
        var result = value
        if let lines = settings.linesPerNotch {
            let n = value.direction * Int64(lines)
            result = ScrollAxis(lines: n, fixed: Double(n), points: Double(n) * settings.pointsPerLine)
        }
        return settings.reverseWheel ? result.negated : result
    }
}
