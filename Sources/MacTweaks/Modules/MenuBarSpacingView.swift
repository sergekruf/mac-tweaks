import AppKit
import SwiftUI

/// Отступы между значками в строке меню.
/// NSStatusItemSpacing — расстояние между значками,
/// NSStatusItemSelectionPadding — поле подсветки вокруг значка при клике.
@MainActor
final class MenuBarSpacingModel: ObservableObject {
    static let spacingKey = "NSStatusItemSpacing"
    static let paddingKey = "NSStatusItemSelectionPadding"
    // Значения macOS по умолчанию (когда ключи не заданы)
    static let systemSpacing = 16
    static let systemPadding = 16

    @Published var spacing = 6.0
    @Published var padding = 4.0
    @Published var status: String?

    @Published private(set) var globalSpacing: Int?
    @Published private(set) var globalPadding: Int?
    @Published private(set) var hostSpacing: Int?
    @Published private(set) var hostPadding: Int?

    init() {
        reload()
        if let s = hostSpacing ?? globalSpacing { spacing = Double(s) }
        if let p = hostPadding ?? globalPadding { padding = Double(p) }
    }

    func reload() {
        globalSpacing = GlobalDefaults.int(Self.spacingKey, host: .any)
        globalPadding = GlobalDefaults.int(Self.paddingKey, host: .any)
        hostSpacing = GlobalDefaults.int(Self.spacingKey, host: .current)
        hostPadding = GlobalDefaults.int(Self.paddingKey, host: .current)
    }

    /// Пишем в оба уровня (все компьютеры и этот Mac), чтобы на macOS 26+
    /// процессы, читающие разные уровни, получали одинаковые значения.
    func apply() {
        for host in [GlobalDefaults.Host.any, .current] {
            GlobalDefaults.set(Self.spacingKey, Int(spacing), host: host)
            GlobalDefaults.set(Self.paddingKey, Int(padding), host: host)
        }
        restartSystemMenuBar()
        reload()
        status = "Применено: \(Int(spacing)) / \(Int(padding)). Системные значки обновлены, сторонние — после их перезапуска."
    }

    func resetToSystem() {
        for host in [GlobalDefaults.Host.any, .current] {
            GlobalDefaults.set(Self.spacingKey, nil, host: host)
            GlobalDefaults.set(Self.paddingKey, nil, host: host)
        }
        spacing = Double(Self.systemSpacing)
        padding = Double(Self.systemPadding)
        restartSystemMenuBar()
        reload()
        status = "Сброшено к системным значениям."
    }

    private func restartSystemMenuBar() {
        Shell.killall(["ControlCenter", "SystemUIServer"])
    }

    /// Сторонние приложения в строке меню (агенты без значка в Dock).
    var menuBarApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .accessory,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let path = app.bundleURL?.path else { return false }
            return path.hasPrefix("/Applications") || path.hasPrefix(NSHomeDirectory() + "/Applications")
        }
    }

    func relaunchMenuBarApps() {
        let apps = menuBarApps
        let urls = apps.compactMap(\.bundleURL)
        apps.forEach { $0.terminate() }
        status = "Перезапускаю \(apps.count) прил…"
        Task {
            try? await Task.sleep(for: .seconds(2))
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            for url in urls {
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
            status = "Перезапущено приложений: \(urls.count)."
        }
    }

    func logOut() {
        // Стандартный выход с системным подтверждением
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevtlogo»")?.executeAndReturnError(nil)
    }
}

struct MenuBarSpacingView: View {
    @StateObject private var model = MenuBarSpacingModel()
    @State private var confirmRelaunch = false

    var body: some View {
        Form {
            Section {
                PreviewStrip(spacing: model.spacing, padding: model.padding)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } header: {
                Text("Предпросмотр (примерный)")
            }

            Section("Отступы") {
                SliderRow(title: "Расстояние между значками", value: $model.spacing,
                          hint: "NSStatusItemSpacing, по умолчанию \(MenuBarSpacingModel.systemSpacing)")
                SliderRow(title: "Поле подсветки при клике", value: $model.padding,
                          hint: "NSStatusItemSelectionPadding, по умолчанию \(MenuBarSpacingModel.systemPadding)")

                HStack {
                    Text("Пресеты").foregroundStyle(.secondary)
                    Spacer()
                    Button("Плотно") { model.spacing = 2; model.padding = 2 }
                    Button("Компактно") { model.spacing = 6; model.padding = 4 }
                    Button("Свободно") { model.spacing = 10; model.padding = 8 }
                }
            }

            Section {
                HStack {
                    Button("Применить") { model.apply() }
                        .keyboardShortcut(.defaultAction)
                    Button("Сбросить к системным") { model.resetToSystem() }
                    Spacer()
                }
                if let status = model.status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Перезапустить приложения в строке меню…") { confirmRelaunch = true }
                    Button("Выйти из системы…") { model.logOut() }
                }
                Text("Сторонние значки (Bartender, VPN, мессенджеры и т.п.) читают отступы только при запуске. Если они не изменились — перезапустите их или выйдите из системы и войдите снова.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Если отступы неровные")
            }

            Section("Текущие значения в системе") {
                LabeledContent("Все компьютеры", value: describe(model.globalSpacing, model.globalPadding))
                LabeledContent("Этот Mac (currentHost)", value: describe(model.hostSpacing, model.hostPadding))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Строка меню")
        .confirmationDialog("Перезапустить приложения?", isPresented: $confirmRelaunch) {
            Button("Перезапустить") { model.relaunchMenuBarApps() }
        } message: {
            Text(model.menuBarApps.compactMap(\.localizedName).joined(separator: ", "))
        }
    }

    private func describe(_ s: Int?, _ p: Int?) -> String {
        let fmt: (Int?) -> String = { $0.map(String.init) ?? "—" }
        return "интервал \(fmt(s)), подсветка \(fmt(p))"
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Stepper(value: $value, in: 0...24, step: 1) {
                    Text("\(Int(value)) pt").monospacedDigit()
                }
            }
            Slider(value: $value, in: 0...24, step: 1)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Схематичная полоска значков с текущими отступами.
private struct PreviewStrip: View {
    let spacing: Double
    let padding: Double
    private let icons = ["cloud.sun", "mic", "wifi", "battery.75percent", "magnifyingglass", "switch.2"]

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .padding(.horizontal, padding)
                    .frame(height: 22)
                    .background(index == 2 ? Color.primary.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 10)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
    }
}
