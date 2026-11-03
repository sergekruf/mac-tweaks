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
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Строка меню"
        case .dock: "Dock"
        case .keyboard: "Клавиатура"
        case .app: "Приложение"
        }
    }

    var icon: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .dock: "dock.rectangle"
        case .keyboard: "keyboard"
        case .app: "app.badge"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .menuBar: MenuBarSpacingView()
        case .dock: DockView()
        case .keyboard: KeyboardView()
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
