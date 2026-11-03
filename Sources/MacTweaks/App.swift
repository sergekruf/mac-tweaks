import SwiftUI

/// Запуск без SwiftUI App: при одной сцене Settings SwiftUI сам открывает пустое окно настроек.
/// Главное окно, значок в строке меню и меню приложения ведёт AppDelegate.
@main
@MainActor
enum MacTweaksMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.mainMenu = delegate.makeMainMenu()
        app.run()
    }
}

/// Один раздел настроек. Новые фишки добавляются сюда отдельным кейсом.
enum TweakModule: String, CaseIterable, Identifiable {
    case menuBar
    case dock
    case keyboard
    case mouse
    case keepAwake
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Строка меню"
        case .dock: "Dock"
        case .keyboard: "Клавиатура"
        case .mouse: "Мышь"
        case .keepAwake: "Не засыпать"
        case .app: "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .dock: "dock.rectangle"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .keepAwake: "cup.and.saucer"
        case .app: "gearshape"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .menuBar: MenuBarSpacingView()
        case .dock: DockView()
        case .keyboard: KeyboardView()
        case .mouse: MouseView()
        case .keepAwake: KeepAwakeView()
        case .app: AppSettingsView()
        }
    }
}

struct ContentView: View {
    @State private var selection: TweakModule? = .menuBar

    var body: some View {
        NavigationSplitView {
            List(TweakModule.allCases, selection: $selection) { module in
                Label(module.title, systemImage: module.icon).tag(module)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let selection {
                selection.view
            } else {
                Text("Выберите раздел").foregroundStyle(.secondary)
            }
        }
    }
}
