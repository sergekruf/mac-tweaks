import PointerMath
import SwiftUI

/// Мышь: своё направление колеса и прокрутка по строкам без ускорения (как LinearMouse).
struct MouseView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scroller = MouseScroller.shared
    @ObservedObject private var apps = RunningApps.shared
    @ObservedObject private var pointer = MousePointer.shared

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
                Toggle("Без ускорения (как в Windows)", isOn: $settings.pointerLinear)
                Text("Курсор сдвигается строго пропорционально движению мыши: медленное и быстрое движение на одно и то же расстояние уводят курсор одинаково.")
                    .font(.callout).foregroundStyle(.secondary)

                LabeledContent("Скорость указателя") {
                    HStack {
                        Slider(value: $settings.pointerSpeed, in: PointerSettings.speedRange, step: 0.1)
                            .frame(minWidth: 180)
                        Text(String(format: "%.1f", settings.pointerSpeed))
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .disabled(!settings.pointerLinear)
                Text("Работает в режиме без ускорения и заменяет для мыши ползунок «Скорость перемещения» из Системных настроек. Меняется сразу — подвигайте и подберите удобную.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack {
                    LabeledContent("Мыши", value: pointer.mice.isEmpty ? "не подключены" : pointer.mice.joined(separator: ", "))
                    Spacer()
                    Button("Сбросить к системным") { settings.pointerLinear = false }
                        .disabled(!settings.pointerLinear)
                }
                Text("Только для мышей: тачпад не меняется. Разрешение не нужно. Работает, пока Mac Tweaks запущен; при выходе из приложения мыши возвращаются к системному поведению.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Указатель мыши")
            }

            Section {
                if apps.contains(bundleID: MouseScroller.linearMouseBundleID, name: "LinearMouse") {
                    Label("Запущен LinearMouse. Если включить те же функции и здесь, эффекты сложатся: двойное обращение вернёт колесо как было, а настройки указателя будут перебивать друг друга. Закройте LinearMouse (значок в строке меню → Quit) или не включайте эти функции.",
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
        .onAppear {
            scroller.refreshPermission()
            pointer.reloadMice()
        }
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
