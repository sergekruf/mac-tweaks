import ServiceManagement
import SwiftUI

/// Настройки самого Mac Tweaks. Хранятся в UserDefaults приложения (ru.tokarev.mactweaks).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    /// Значок и Dock одновременно не скрываются: иначе к приложению не добраться.
    @Published var showStatusItem: Bool {
        didSet {
            if !showStatusItem && !showInDock { showInDock = true }
            defaults.set(showStatusItem, forKey: "showStatusItem")
            onChange?()
        }
    }
    @Published var showInDock: Bool {
        didSet {
            if !showInDock && !showStatusItem { showStatusItem = true }
            defaults.set(showInDock, forKey: "showInDock")
            onChange?()
        }
    }
    @Published var keepDisplayOnByDefault: Bool {
        didSet { defaults.set(keepDisplayOnByDefault, forKey: "keepDisplayOnByDefault") }
    }
    /// Сочетание для смены языка ввода (модуль «Клавиатура»), по умолчанию выключено.
    @Published var layoutHotkey: LayoutHotkey {
        didSet {
            defaults.set(layoutHotkey.rawValue, forKey: "layoutHotkey")
            LayoutSwitcher.shared.apply(layoutHotkey)
        }
    }

    var onChange: (() -> Void)?

    private init() {
        defaults.register(defaults: ["showStatusItem": true, "showInDock": true, "keepDisplayOnByDefault": false])
        let statusItem = defaults.bool(forKey: "showStatusItem")
        showStatusItem = statusItem
        showInDock = defaults.bool(forKey: "showInDock") || !statusItem
        keepDisplayOnByDefault = defaults.bool(forKey: "keepDisplayOnByDefault")
        layoutHotkey = defaults.string(forKey: "layoutHotkey").flatMap(LayoutHotkey.init) ?? .off
    }
}

struct AppSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var awake = KeepAwake.shared
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Значок в строке меню", isOn: $settings.showStatusItem)
                    .disabled(!settings.showInDock)
                Toggle("Значок в Dock", isOn: $settings.showInDock)
                    .disabled(!settings.showStatusItem)
                Text("Одновременно скрыть оба нельзя, иначе к приложению не добраться. Без значка в Dock окно открывается из меню значка.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Где показывать Mac Tweaks")
            }

            Section("Запуск") {
                Toggle("Открывать при входе в систему", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setLaunchAtLogin))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Нужно разрешить в Системных настройках → Основные → Объекты входа.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Открыть") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                Text("При входе в систему окно не открывается, приложение сразу уходит в строку меню.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    LabeledContent("Сейчас", value: awake.remainingText ?? "выключено")
                }
                Toggle("Не гасить экран по умолчанию", isOn: $settings.keepDisplayOnByDefault)
                Text("Режим включается в меню значка Mac Tweaks. Без «Не гасить экран» Mac не засыпает, но дисплей гаснет как обычно. Галочка в меню действует до выхода из приложения, при следующем запуске берётся значение отсюда.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("При закрытой крышке без внешнего монитора Mac всё равно уснёт: этот режим не отменяет сон по крышке и не трогает системные настройки сна.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Не засыпать")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Приложение")
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Не получилось: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}
