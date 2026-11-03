import Foundation

/// Работа с глобальными настройками (аналог `defaults write -globalDomain`)
/// и перезапуск системных процессов.
enum GlobalDefaults {
    enum Host { case any, current }

    private static func cfHost(_ host: Host) -> CFString {
        host == .any ? kCFPreferencesAnyHost : kCFPreferencesCurrentHost
    }

    static func int(_ key: String, host: Host) -> Int? {
        let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, cfHost(host))
        return (value as? NSNumber)?.intValue
    }

    /// nil удаляет ключ — система возвращается к значению по умолчанию.
    static func set(_ key: String, _ value: Int?, host: Host) {
        CFPreferencesSetValue(key as CFString, value.map { $0 as NSNumber },
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, cfHost(host))
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, cfHost(host))
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func killall(_ names: [String]) {
        run("/usr/bin/killall", names)
    }
}
