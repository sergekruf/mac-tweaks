/// Распознавание «нажали и отпустили сочетание модификаторов без других клавиш» (Cmd+Shift, правый Cmd…).
/// Без зависимостей от системы: события приходят уже переведёнными в `ModifierKey` и `TapInput`.

/// Физическая клавиша-модификатор, левая и правая отдельно.
public enum ModifierKey: Hashable, CaseIterable, Sendable {
    case leftCommand, rightCommand
    case leftShift, rightShift
    case leftOption, rightOption
    case leftControl, rightControl
    case function
}

/// Что произошло с клавиатурой или мышью.
public enum TapInput: Equatable, Sendable {
    /// Изменился набор зажатых модификаторов — передаётся полный набор после изменения.
    case modifiers(Set<ModifierKey>)
    /// Нажата обычная клавиша (или кнопка мыши) — сочетание уже не «чистое».
    case otherKey
}

/// Сочетание-триггер: каждая группа должна быть представлена хотя бы одной зажатой клавишей,
/// других модификаторов быть не должно. Cmd+Shift = [[левый Cmd, правый Cmd], [левый Shift, правый Shift]].
public struct ModifierChord: Hashable, Sendable {
    public let groups: [Set<ModifierKey>]

    public init(groups: [Set<ModifierKey>]) {
        self.groups = groups
    }

    public static let commandShift = ModifierChord(groups: [[.leftCommand, .rightCommand], [.leftShift, .rightShift]])
    public static let rightCommand = ModifierChord(groups: [[.rightCommand]])

    var allowed: Set<ModifierKey> { groups.reduce(into: []) { $0.formUnion($1) } }

    func isSatisfied(by held: Set<ModifierKey>) -> Bool {
        held.isSubset(of: allowed) && groups.allSatisfy { !$0.isDisjoint(with: held) }
    }
}

/// Конечный автомат одного нажатия. Срабатывает, когда отпущены все модификаторы, если по пути
/// сочетание было набрано целиком, не было лишних модификаторов и других клавиш.
/// Порядок нажатия и отпускания не важен: Cmd→Shift и Shift→Cmd равноправны.
public struct ModifierTapDetector: Sendable {
    public let chord: ModifierChord
    private var held: Set<ModifierKey> = []
    private var reached = false
    private var spoiled = false

    public init(chord: ModifierChord) {
        self.chord = chord
    }

    /// Возвращает true, если на этом событии нужно сработать.
    public mutating func handle(_ input: TapInput) -> Bool {
        switch input {
        case .otherKey:
            // Клавиша без модификаторов (обычный набор текста) ничего не портит: сочетание ещё не начато.
            if !held.isEmpty { spoiled = true }
            return false
        case .modifiers(let now):
            held = now
            if held.isEmpty {
                let fire = reached && !spoiled
                reached = false
                spoiled = false
                return fire
            }
            if !held.isSubset(of: chord.allowed) { spoiled = true }
            if chord.isSatisfied(by: held) { reached = true }
            return false
        }
    }

    /// Сбросить состояние (например, после перезапуска перехвата).
    public mutating func reset() {
        held = []
        reached = false
        spoiled = false
    }
}
