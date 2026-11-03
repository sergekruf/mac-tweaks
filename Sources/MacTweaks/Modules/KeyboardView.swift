import SwiftUI

/// Клавиатура: смена языка ввода по Command+Shift (как CommandShift.app).
struct KeyboardView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var switcher = LayoutSwitcher.shared
    @ObservedObject private var apps = RunningApps.shared

    var body: some View {
        Form {
            Section {
                Toggle("Command+Shift меняет язык", isOn: Binding(
                    get: { settings.layoutHotkey == .commandShift },
                    set: { settings.layoutHotkey = $0 ? .commandShift : .off }))
                Text("Нажмите и отпустите Command и Shift (в любом порядке, левые или правые) — включится следующая раскладка. Если между нажатием и отпусканием была другая клавиша (⌘⇧4, ⌘⇧Z), язык не меняется и сочетание работает как обычно.")
                    .font(.callout).foregroundStyle(.secondary)
                if settings.layoutHotkey != .off {
                    LabeledContent("Состояние", value: stateText)
                }
                if let error = switcher.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                if apps.contains(bundleID: LayoutSwitcher.commandShiftBundleID, name: "CommandShift") {
                    Label("Запущен CommandShift. Если включить переключение и здесь, язык сменится дважды и вернётся обратно. Закройте CommandShift (значок в строке меню → Quit) или не включайте эту функцию.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Переключение языка")
            }

            Section {
                LabeledContent("Мониторинг ввода") {
                    Text(switcher.hasPermission ? "разрешён" : "не разрешён")
                        .foregroundStyle(switcher.hasPermission ? .green : .red)
                }
                if !switcher.hasPermission {
                    Text("Без этого разрешения Mac Tweaks не видит нажатий и Command+Shift не работает. Нажмите «Запросить доступ», затем включите Mac Tweaks в Системных настройках → Конфиденциальность и безопасность → Мониторинг ввода.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Запросить доступ") { switcher.requestPermission() }
                        Button("Открыть Системные настройки") { switcher.openPrivacySettings() }
                    }
                }
                Text("Mac Tweaks только слушает клавиши-модификаторы и факт нажатия других клавиш, ничего не записывает и не меняет.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Разрешение")
            }

            Section {
                if switcher.sources.isEmpty {
                    Text("Нет включённых раскладок").foregroundStyle(.secondary)
                }
                ForEach(switcher.sources) { source in
                    HStack {
                        Text(source.name)
                        Spacer()
                        if source.id == switcher.currentSourceID {
                            Text("сейчас").foregroundStyle(.secondary)
                        }
                    }
                }
                if switcher.sources.count == 1 {
                    Text("Включена одна раскладка — переключаться не на что. Добавьте раскладку в Системных настройках → Клавиатура → Источники ввода.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Раскладки по кругу")
            } footer: {
                Text("Порядок — как в меню источников ввода. Список берётся из системы.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Клавиатура")
        .onAppear {
            switcher.refreshPermission()
            switcher.reloadSources()
        }
        .task {
            // Пока раздел открыт, следим за выдачей разрешения
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                switcher.refreshPermission()
            }
        }
    }

    private var stateText: String {
        if switcher.isRunning { return "работает" }
        if !switcher.hasPermission { return "не работает — нет разрешения" }
        return "не работает"
    }
}
