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
        perform {
            try tiles.add(spacer, count: count, to: section)
            let kind = spacer == .regular ? "обычных" : "узких"
            let place = section == .apps ? "к приложениям" : "в правую часть"
            return "Добавлено \(kind) пробелов \(place): \(count). Dock перезапущен — перетащите пробелы на нужные места."
        }
    }

    func removeAll() {
        perform {
            let removed = try tiles.removeAllSpacers()
            return removed == 0 ? "Пробелов в Dock нет." : "Убрано пробелов: \(removed). Dock перезапущен."
        }
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

    /// Резервная копия перед первой записью, запись, перезапуск Dock.
    private func perform(_ change: () throws -> String) {
        do {
            if !backedUp {
                _ = try DockBackup.make()
                backedUp = true
            }
            status = try change()
            Shell.killall(["Dock"])
        } catch {
            status = error.localizedDescription
        }
        reload()
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
                SpacerRow(title: "В правой части", hint: "Папки, стопки и корзина. На macOS 27 может не работать — проверьте.") { spacer in
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
