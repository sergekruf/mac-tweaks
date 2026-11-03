import SwiftUI

/// Режим «не засыпать»: то же, что в меню значка, плюс значение «не гасить экран» по умолчанию.
struct KeepAwakeView: View {
    @ObservedObject private var awake = KeepAwake.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    LabeledContent("Сейчас", value: awake.remainingText ?? "выключено")
                }
                Picker("Не засыпать", selection: Binding(
                    get: { awake.isActive ? Choice.duration(awake.minutes) : .off },
                    set: { choice in
                        switch choice {
                        case .off: awake.stop()
                        case .duration(let minutes): awake.start(minutes: minutes)
                        }
                    })) {
                    Text("Выключено").tag(Choice.off)
                    ForEach(KeepAwake.durations, id: \.self) { minutes in
                        Text(KeepAwake.title(for: minutes)).tag(Choice.duration(minutes))
                    }
                }
                if let error = awake.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Text("Срок отсчитывается заново при каждом выборе. Включать и выключать режим можно и из меню значка Mac Tweaks в строке меню.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Режим")
            }

            Section {
                Toggle("Не гасить экран сейчас", isOn: $awake.keepDisplayOn)
                Toggle("Не гасить экран по умолчанию", isOn: $settings.keepDisplayOnByDefault)
                Text("Без «Не гасить экран» Mac не засыпает, но дисплей гаснет как обычно. «Сейчас» действует до выхода из приложения, при следующем запуске берётся значение «по умолчанию».")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Экран")
            }

            Section {
                Text("При закрытой крышке без внешнего монитора Mac всё равно уснёт: этот режим не отменяет сон по крышке и не трогает системные настройки сна.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Не засыпать")
    }

    private enum Choice: Hashable {
        case off
        case duration(Int?)
    }
}
