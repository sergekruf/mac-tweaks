import PointerMath
import ScrollWheel
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

    /// Модуль «Мышь»: обратить колесо и прокрутка по строкам, по умолчанию выключено.
    @Published var reverseWheel: Bool {
        didSet { defaults.set(reverseWheel, forKey: "reverseWheel"); MouseScroller.shared.apply(scrollSettings) }
    }
    @Published var linearWheel: Bool {
        didSet { defaults.set(linearWheel, forKey: "linearWheel"); MouseScroller.shared.apply(scrollSettings) }
    }
    @Published var wheelLines: Int {
        didSet { defaults.set(wheelLines, forKey: "wheelLines"); MouseScroller.shared.apply(scrollSettings) }
    }
    static let wheelLinesRange = 1...10
    /// Указатель мыши: режим и скорость для каждого режима.
    @Published var pointerMode: PointerMode {
        didSet { defaults.set(pointerMode.rawValue, forKey: "pointerMode"); MousePointer.shared.apply(pointerSettings) }
    }
    @Published var pointerSpeed: Double {
        didSet { defaults.set(pointerSpeed, forKey: "pointerSpeed"); MousePointer.shared.apply(pointerSettings) }
    }
    @Published var pointerWindowsSpeed: Double {
        didSet { defaults.set(pointerWindowsSpeed, forKey: "pointerWindowsSpeed"); MousePointer.shared.apply(pointerSettings) }
    }
    @Published var pointerWindowsStrength: Double {
        didSet { defaults.set(pointerWindowsStrength, forKey: "pointerWindowsStrength"); MousePointer.shared.apply(pointerSettings) }
    }

    var pointerSettings: PointerSettings {
        PointerSettings(mode: pointerMode, speed: pointerSpeed, windowsSpeed: pointerWindowsSpeed, windowsStrength: pointerWindowsStrength)
    }

    var scrollSettings: ScrollSettings {
        ScrollSettings(reverseWheel: reverseWheel, linesPerNotch: linearWheel ? wheelLines : nil)
    }

    var onChange: (() -> Void)?

    private init() {
        defaults.register(defaults: ["showStatusItem": true, "showInDock": true, "keepDisplayOnByDefault": false, "wheelLines": 3, "pointerSpeed": PointerSettings.defaultSpeed, "pointerWindowsSpeed": PointerSettings.defaultWindowsSpeed, "pointerWindowsStrength": PointerSettings.defaultWindowsStrength])
        let statusItem = defaults.bool(forKey: "showStatusItem")
        showStatusItem = statusItem
        showInDock = defaults.bool(forKey: "showInDock") || !statusItem
        keepDisplayOnByDefault = defaults.bool(forKey: "keepDisplayOnByDefault")
        layoutHotkey = defaults.string(forKey: "layoutHotkey").flatMap(LayoutHotkey.init) ?? .off
        reverseWheel = defaults.bool(forKey: "reverseWheel")
        linearWheel = defaults.bool(forKey: "linearWheel")
        // Раньше был только переключатель «Без ускорения» (pointerLinear)
        pointerMode = defaults.string(forKey: "pointerMode").flatMap(PointerMode.init)
            ?? (defaults.bool(forKey: "pointerLinear") ? .linear : .system)
        pointerWindowsStrength = min(max(defaults.double(forKey: "pointerWindowsStrength"), 0), 1)
        pointerWindowsSpeed = min(max(defaults.double(forKey: "pointerWindowsSpeed"), PointerSettings.windowsSpeedRange.lowerBound),
                                  PointerSettings.windowsSpeedRange.upperBound)
        pointerSpeed = min(max(defaults.double(forKey: "pointerSpeed"), PointerSettings.speedRange.lowerBound), PointerSettings.speedRange.upperBound)
        wheelLines = min(max(defaults.integer(forKey: "wheelLines"), Self.wheelLinesRange.lowerBound), Self.wheelLinesRange.upperBound)
    }
}

struct AppSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
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
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
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
