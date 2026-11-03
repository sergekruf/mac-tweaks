import SwiftUI

@main
struct MacTweaksApp: App {
    var body: some Scene {
        WindowGroup("Mac Tweaks") {
            ContentView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Один раздел настроек. Новые фишки добавляются сюда отдельным кейсом.
enum TweakModule: String, CaseIterable, Identifiable {
    case menuBar
    case dock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: "Строка меню"
        case .dock: "Dock"
        }
    }

    var icon: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .dock: "dock.rectangle"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .menuBar: MenuBarSpacingView()
        case .dock: DockView()
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
