import AppKit
import SwiftUI

/// Главное окно и значок в строке меню. Окно — обычный NSWindow, чтобы его можно было закрыть
/// и открыть снова из меню, а приложение при этом продолжало работать в строке меню.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let awake = KeepAwake.shared
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var menuTimer: Timer?
    private weak var remainingItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.onChange = { [weak self] in
            self?.applyActivationPolicy()
            self?.updateStatusItem()
        }
        awake.onChange = { [weak self] in self?.refreshStatusButton() }
        applyActivationPolicy()
        updateStatusItem()
        // Перехват сочетания работает всё время, пока приложение запущено, и с закрытым окном
        LayoutSwitcher.shared.apply(settings.layoutHotkey)
        MouseScroller.shared.apply(settings.scrollSettings)
        MousePointer.shared.apply(settings.pointerSettings)
        if !launchedAsLoginItem { showMainWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Клик по значку в Dock, когда окно закрыто.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        awake.stop()
        // Свойства мыши живут в системе и после выхода — возвращаем системные
        MousePointer.shared.restore()
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // MARK: - Окно

    @objc func showMainWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Mac Tweaks"
            w.contentViewController = NSHostingController(rootView: ContentView()
                .frame(minWidth: 760, minHeight: 520))
            w.isReleasedWhenClosed = false
            if !w.setFrameUsingName("MainWindow") { w.center() }
            w.setFrameAutosaveName("MainWindow")
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Активация на macOS 14+ «вежливая» и может не сработать — окно всё равно показываем поверх
        window?.orderFrontRegardless()
    }

    /// Меню приложения (видно, когда Mac Tweaks показывается в Dock).
    func makeMainMenu() -> NSMenu {
        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            menu.addItem(i)
        }
        let main = NSMenu()

        let app = NSMenu(title: "Mac Tweaks")
        add(app, "О программе Mac Tweaks", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(showMainWindow), keyEquivalent: ",")
        settingsItem.target = self
        app.addItem(settingsItem)
        app.addItem(.separator())
        add(app, "Скрыть Mac Tweaks", #selector(NSApplication.hide(_:)), "h")
        add(app, "Скрыть остальные", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Показать все", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Завершить Mac Tweaks", #selector(NSApplication.terminate(_:)), "q")

        let edit = NSMenu(title: "Правка")
        add(edit, "Отменить", Selector(("undo:")), "z")
        add(edit, "Повторить", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Вырезать", #selector(NSText.cut(_:)), "x")
        add(edit, "Скопировать", #selector(NSText.copy(_:)), "c")
        add(edit, "Вставить", #selector(NSText.paste(_:)), "v")
        add(edit, "Выбрать все", #selector(NSText.selectAll(_:)), "a")

        let window = NSMenu(title: "Окно")
        add(window, "Свернуть", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Изменить масштаб", #selector(NSWindow.performZoom(_:)))
        add(window, "Закрыть", #selector(NSWindow.performClose(_:)), "w")
        NSApp.windowsMenu = window

        for menu in [app, edit, window] {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }

    // MARK: - Dock и строка меню

    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = settings.showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // После смены политики macOS уводит приложение на задний план — возвращаем открытое окно
        if window?.isVisible == true {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate()
                self?.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func updateStatusItem() {
        if settings.showStatusItem {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.autosaveName = "MacTweaksStatusItem"
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                statusItem = item
            }
            refreshStatusButton()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func refreshStatusButton() {
        guard let button = statusItem?.button else { return }
        button.image = WrenchGlyph.statusImage(active: awake.isActive)
        button.toolTip = awake.remainingText.map { "Mac Tweaks — \($0.lowercasedFirst)" } ?? "Mac Tweaks"
        remainingItem?.title = awake.remainingText ?? ""
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Открыть Mac Tweaks…", #selector(showMainWindow)))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Не засыпать"))
        if let remaining = awake.remainingText {
            let r = NSMenuItem(title: remaining, action: nil, keyEquivalent: "")
            r.isEnabled = false
            menu.addItem(r)
            remainingItem = r
            menu.addItem(item("Выключить", #selector(turnOff)))
            menu.addItem(.separator())
        }
        let off = item("Выключено", #selector(turnOff))
        off.state = awake.isActive ? .off : .on
        menu.addItem(off)
        for minutes in KeepAwake.durations {
            let d = item(KeepAwake.title(for: minutes), #selector(chooseDuration(_:)))
            d.representedObject = minutes
            d.state = awake.isActive && awake.minutes == minutes ? .on : .off
            menu.addItem(d)
        }
        menu.addItem(.separator())
        let display = item("Не гасить экран", #selector(toggleDisplay))
        display.state = awake.keepDisplayOn ? .on : .off
        menu.addItem(display)
        menu.addItem(note("При закрытой крышке без внешнего монитора\nMac всё равно уснёт"))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Обратный отсчёт в открытом меню (меню крутит run loop в режиме eventTracking)
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.remainingItem?.title = self?.awake.remainingText ?? "" }
        }
        RunLoop.main.add(t, forMode: .common)
        menuTimer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate()
        menuTimer = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func note(_ text: String) -> NSMenuItem {
        let i = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        i.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        i.isEnabled = false
        return i
    }

    @objc private func turnOff() { awake.stop() }

    @objc private func chooseDuration(_ sender: NSMenuItem) {
        awake.start(minutes: sender.representedObject as? Int)
    }

    @objc private func toggleDisplay() { awake.keepDisplayOn.toggle() }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
