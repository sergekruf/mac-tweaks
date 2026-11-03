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
                Picker("Режим", selection: $settings.pointerMode) {
                    Text("Как в системе").tag(PointerMode.system)
                    Text("Без ускорения").tag(PointerMode.linear)
                    Text("Как в Windows").tag(PointerMode.windows)
                }
                .pickerStyle(.segmented)
                Text(modeNote)
                    .font(.callout).foregroundStyle(.secondary)

                switch settings.pointerMode {
                case .system:
                    EmptyView()
                case .linear:
                    speedSlider("Скорость указателя", value: $settings.pointerSpeed, in: PointerSettings.speedRange)
                case .windows:
                    speedSlider("Скорость на медленных движениях", value: $settings.pointerWindowsSpeed, in: PointerSettings.windowsSpeedRange)
                    if !pointer.motionPermission {
                        Text("Нужен «Мониторинг ввода»: без него Mac Tweaks не видит скорость мыши. Включите Mac Tweaks в Системных настройках → Конфиденциальность и безопасность → Мониторинг ввода.")
                            .font(.callout).foregroundStyle(.red)
                        Button("Открыть Системные настройки") { EventTapPermission.inputMonitoring.openSettings() }
                    } else if !pointer.motionRunning {
                        Text("Не удалось подключиться к мыши. Перезапустите Mac Tweaks.")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
                if settings.pointerMode != .system && !pointer.systemLinear {
                    Text("В системе включено «Ускорение указателя» — тогда Mac Tweaks меняет уровень ускорения Apple, а не скорость, и режимы работают не так, как описано.")
                        .font(.callout).foregroundStyle(.orange)
                }

                HStack {
                    LabeledContent("Мыши", value: pointer.mice.isEmpty ? "не подключены" : pointer.mice.joined(separator: ", "))
                    Spacer()
                    Button("Сбросить к системным") { settings.pointerMode = .system }
                        .disabled(settings.pointerMode == .system)
                }
                Text("Только для мышей: тачпад не меняется. Работает, пока Mac Tweaks запущен; при выходе из приложения мыши возвращаются к системному поведению.")
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

    private var modeNote: String {
        switch settings.pointerMode {
        case .system:
            "Mac Tweaks указатель не трогает."
        case .linear:
            "Курсор сдвигается строго пропорционально движению мыши: медленное и быстрое движение на одно и то же расстояние уводят курсор одинаково."
        case .windows:
            "Как «Повышенная точность указателя» в Windows: при медленном движении курсор идёт медленно и точно — легко попасть в мелкую кнопку, при быстром разгоняется (до ~4,5 раза), чтобы пересечь экран коротким движением."
        }
    }

    private func speedSlider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 0.05)
                    .frame(minWidth: 180)
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
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
