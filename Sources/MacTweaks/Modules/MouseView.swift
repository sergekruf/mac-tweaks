import SwiftUI

/// Мышь: своё направление колеса и прокрутка по строкам без ускорения (как LinearMouse).
struct MouseView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scroller = MouseScroller.shared
    @ObservedObject private var apps = RunningApps.shared

    var body: some View {
        Form {
            Section {
                Toggle("Обратить прокрутку колеса", isOn: $settings.reverseWheel)
                Text("Колесо мыши крутит в обратную сторону, тачпад — как в системе. \(naturalScrollingNote)")
                    .font(.callout).foregroundStyle(.secondary)

                Toggle("Прокрутка по строкам, без ускорения", isOn: $settings.linearWheel)
                Stepper(value: $settings.wheelLines, in: AppSettings.wheelLinesRange) {
                    LabeledContent("Строк за щелчок колеса", value: "\(settings.wheelLines)")
                }
                .disabled(!settings.linearWheel)
                Text("Каждый щелчок колеса прокручивает одно и то же число строк, как бы быстро вы ни крутили. Без этого macOS сначала прокручивает медленно, а потом ускоряется.")
                    .font(.callout).foregroundStyle(.secondary)

                Text("Тачпад, Magic Mouse и другие устройства с плавной прокруткой не затрагиваются. Горизонтальная прокрутка (Shift + колесо, наклон колеса) работает так же.")
                    .font(.callout).foregroundStyle(.secondary)
                if settings.scrollSettings.changesAnything {
                    LabeledContent("Состояние", value: stateText)
                }
                if let error = scroller.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text("Колесо мыши")
            }

            Section {
                if apps.contains(bundleID: MouseScroller.linearMouseBundleID, name: "LinearMouse") {
                    Label("Запущен LinearMouse. Если включить те же функции и здесь, эффекты сложатся: двойное обращение вернёт колесо как было. Закройте LinearMouse (значок в строке меню → Quit) или не включайте эти функции.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                } else {
                    Text("LinearMouse не запущен. Если запустить его одновременно с этими функциями, эффекты сложатся: двойное обращение вернёт колесо как было.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("LinearMouse")
            }

            Section {
                LabeledContent("Универсальный доступ") {
                    Text(scroller.hasPermission ? "разрешён" : "не разрешён")
                        .foregroundStyle(scroller.hasPermission ? .green : .red)
                }
                if !scroller.hasPermission {
                    Text("Без этого разрешения Mac Tweaks не может менять события колеса. Нажмите «Запросить доступ», затем включите Mac Tweaks в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Запросить доступ") { scroller.requestPermission() }
                        Button("Открыть Системные настройки") { scroller.openPrivacySettings() }
                    }
                }
                Text("Mac Tweaks меняет только дельты прокрутки колеса мыши, пока приложение запущено (в том числе с закрытым окном).")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Разрешение")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Мышь")
        .onAppear { scroller.refreshPermission() }
        .task {
            // Пока раздел открыт, следим за выдачей разрешения
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                scroller.refreshPermission()
            }
        }
    }

    /// «Естественная» прокрутка в системе одна на тачпад и мышь (`com.apple.swipescrolldirection`, по умолчанию включена).
    private var naturalScrollingNote: String {
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        return natural
            ? "Сейчас в системе включена «естественная» прокрутка, с обращением колесо вниз — страница вниз."
            : "Сейчас в системе «естественная» прокрутка выключена, с обращением колесо вниз — страница вверх."
    }

    private var stateText: String {
        if scroller.isRunning { return "работает" }
        if !scroller.hasPermission { return "не работает — нет разрешения" }
        return "не работает"
    }
}
