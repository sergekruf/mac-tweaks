import AppKit
import SwiftUI

/// Пустые промежутки между значками в Dock.
/// Пробел — плитка с `tile-type` = `spacer-tile` (обычный) или `small-spacer-tile` (узкий)
/// в `persistent-apps` (приложения) или `persistent-others` (папки и стопки справа).
@MainActor
final class DockModel: ObservableObject {
    @Published var count = 1
    @Published var status: String?
    @Published private(set) var counts: [DockTiles.Section: DockTiles.Counts] = [:]
    @Published private(set) var lastBackup: URL?
    @Published private(set) var busy = false

    private let tiles = DockTiles()
    /// Копия делается один раз за запуск приложения — перед первой записью.
    private var backedUp = false

    init() { reload() }

    func reload() {
        for section in DockTiles.Section.allCases {
            counts[section] = tiles.counts(section)
        }
        lastBackup = DockBackup.latest
    }

    func add(_ spacer: DockTiles.Spacer, to section: DockTiles.Section) {
        let tiles = tiles, n = count
        let expected = tiles.counts(section)[spacer] + n
        let missing = { max(0, expected - tiles.counts(section)[spacer]) }
        let kind = spacer == .regular ? "обычных" : "узких"
        let place = section == .apps ? "к приложениям" : "в правую часть"
        perform(done: "Добавлено \(kind) пробелов \(place): \(n). Dock перезапущен — перетащите пробелы на нужные места.",
                change: { try tiles.add(spacer, count: n, to: section) },
                pending: missing,
                redo: { try tiles.add(spacer, count: missing(), to: section) })
    }

    func removeAll() {
        let tiles = tiles
        let pending = { DockTiles.Section.allCases.reduce(0) { $0 + tiles.counts($1).total } }
        perform(done: "Пробелы убраны. Dock перезапущен.",
                change: { try tiles.removeAllSpacers() },
                pending: pending,
                redo: { try tiles.removeAllSpacers() })
    }

    func restoreLatest() {
        guard let url = lastBackup else { return }
        do {
            try DockBackup.restore(from: url)
            Shell.killall(["Dock"])
            status = "Восстановлено из \(url.lastPathComponent). Dock перезапущен."
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    func revealBackups() {
        let dir = DockBackup.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([lastBackup ?? dir])
    }

    /// Резервная копия перед первой записью, запись, перезапуск Dock и проверка.
    /// Dock при завершении сохраняет свой список значков из памяти (например, после
    /// перетаскивания) и может затереть нашу запись. Поэтому после перезапуска
    /// перечитываем настройки и при необходимости вносим изменение ещё раз.
    private func perform(done: String,
                         change: () throws -> Void,
                         pending: @escaping () -> Int,
                         redo: @escaping () throws -> Void) {
        do {
            if !backedUp {
                _ = try DockBackup.make()
                backedUp = true
            }
            try change()
        } catch {
            status = error.localizedDescription
            reload()
            return
        }
        busy = true
        status = "Перезапускаю Dock…"
        Task {
            await Self.restartDock()
            var text = done
            if pending() > 0 {
                do {
                    try redo()
                    await Self.restartDock()
                    text += pending() > 0
                        ? " Dock снова затёр изменение — попробуйте ещё раз."
                        : " Dock при перезапуске записал старый список значков, изменение внесено повторно."
                } catch {
                    text = error.localizedDescription
                }
            }
            status = text
            busy = false
            reload()
        }
    }

    /// `killall Dock` и ожидание, пока launchd запустит новый процесс Dock.
    private static func restartDock() async {
        let oldPID = dockPID
        Shell.killall(["Dock"])
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(200))
            if let pid = dockPID, pid != oldPID { break }
        }
        try? await Task.sleep(for: .milliseconds(800))
    }

    private static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }
}

struct DockView: View {
    @StateObject private var model = DockModel()
    @State private var confirmRemove = false
    @State private var confirmRestore = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $model.count, in: 1...5) {
                    LabeledContent("Сколько добавить за раз", value: "\(model.count)")
                }
                SpacerRow(title: "Среди приложений", hint: "Левая часть Dock, до разделителя") { spacer in
                    model.add(spacer, to: .apps)
                }
                SpacerRow(title: "В правой части", hint: "Папки, стопки и корзина") { spacer in
                    model.add(spacer, to: .others)
                }
                Text("Пробел появляется в конце выбранной части Dock. Перетащите его мышью на нужное место, как обычный значок. Лишний пробел можно вытащить из Dock, как любой значок.")
                    .font(.callout).foregroundStyle(.secondary)
                if let status = model.status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Пробелы между значками")
            }

            Section("Сейчас в Dock") {
                LabeledContent("Среди приложений", value: describe(model.counts[.apps]))
                LabeledContent("В правой части", value: describe(model.counts[.others]))
                HStack {
                    Button("Убрать все пробелы…") { confirmRemove = true }
                        .disabled(totalSpacers == 0)
                    Button("Обновить") { model.reload() }
                    Spacer()
                }
            }

            Section {
                LabeledContent("Последняя копия", value: model.lastBackup?.lastPathComponent ?? "нет")
                HStack {
                    Button("Восстановить из последней копии…") { confirmRestore = true }
                        .disabled(model.lastBackup == nil)
                    Button("Показать в Finder") { model.revealBackups() }
                    Spacer()
                }
                Text("Копия всех настроек Dock делается автоматически перед первым изменением после запуска Mac Tweaks.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Резервная копия")
            }
        }
        .formStyle(.grouped)
        .disabled(model.busy)
        .navigationTitle("Dock")
        .confirmationDialog("Убрать все пробелы из Dock?", isPresented: $confirmRemove) {
            Button("Убрать", role: .destructive) { model.removeAll() }
        } message: {
            Text("Остальные значки останутся на местах. Dock перезапустится.")
        }
        .confirmationDialog("Восстановить настройки Dock?", isPresented: $confirmRestore) {
            Button("Восстановить", role: .destructive) { model.restoreLatest() }
        } message: {
            Text("Все настройки Dock вернутся к копии \(model.lastBackup?.lastPathComponent ?? ""). Изменения после неё пропадут. Dock перезапустится.")
        }
    }

    private var totalSpacers: Int {
        model.counts.values.reduce(0) { $0 + $1.total }
    }

    private func describe(_ counts: DockTiles.Counts?) -> String {
        guard let counts, counts.total > 0 else { return "нет пробелов" }
        return "обычных \(counts.regular), узких \(counts.small)"
    }
}

private struct SpacerRow: View {
    let title: String
    let hint: String
    let add: (DockTiles.Spacer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button("Добавить пробел") { add(.regular) }
                Button("Добавить узкий пробел") { add(.small) }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }
}
