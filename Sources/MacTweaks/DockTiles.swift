import Foundation

/// Плитки Dock в домене `com.apple.dock`: левая часть (`persistent-apps`)
/// и правая — папки и стопки (`persistent-others`).
/// Без SwiftUI, чтобы логику можно было проверить на тестовом домене.
struct DockTiles {
    enum Section: String, CaseIterable {
        case apps = "persistent-apps"
        case others = "persistent-others"
    }

    enum Spacer: String, CaseIterable {
        case regular = "spacer-tile"
        case small = "small-spacer-tile"
    }

    struct Counts: Equatable {
        var regular = 0
        var small = 0
        var total: Int { regular + small }
    }

    enum Failure: LocalizedError {
        case missing(Section)
        case unexpectedFormat(Section)

        var errorDescription: String? {
            switch self {
            case .missing(let s): "В настройках Dock нет ключа \(s.rawValue) — запись отменена."
            case .unexpectedFormat(let s): "Ключ \(s.rawValue) в неожиданном формате — запись отменена."
            }
        }
    }

    let domain: CFString

    init(domain: String = "com.apple.dock") {
        self.domain = domain as CFString
    }

    /// Свежий список плиток. Перед чтением синхронизируемся,
    /// чтобы не затереть то, что Dock записал после нашего прошлого чтения.
    func tiles(_ section: Section) throws -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        guard let value = CFPreferencesCopyAppValue(section.rawValue as CFString, domain) else {
            throw Failure.missing(section)
        }
        guard let array = value as? [Any], let tiles = array as? [[String: Any]] else {
            throw Failure.unexpectedFormat(section)
        }
        return tiles
    }

    func counts(_ section: Section) -> Counts {
        Self.counts(in: (try? tiles(section)) ?? [])
    }

    func add(_ spacer: Spacer, count: Int, to section: Section) throws {
        let current = try tiles(section)
        write(current + Array(repeating: Self.tile(spacer), count: count), to: section)
    }

    /// Убирает пробелы из обеих частей Dock, остальные плитки не трогает.
    /// Возвращает, сколько пробелов удалено.
    @discardableResult
    func removeAllSpacers() throws -> Int {
        var removed = 0
        for section in Section.allCases {
            guard let current = try? tiles(section) else { continue }
            let kept = Self.withoutSpacers(current)
            guard kept.count != current.count else { continue }
            removed += current.count - kept.count
            write(kept, to: section)
        }
        return removed
    }

    private func write(_ tiles: [[String: Any]], to section: Section) {
        CFPreferencesSetAppValue(section.rawValue as CFString, tiles as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    // MARK: Чистая логика

    /// Тот же вид, в котором Dock на macOS 27 сам хранит пробелы.
    static func tile(_ spacer: Spacer) -> [String: Any] {
        ["tile-type": spacer.rawValue, "tile-data": ["file-label": ""]]
    }

    static func spacerKind(_ tile: [String: Any]) -> Spacer? {
        (tile["tile-type"] as? String).flatMap(Spacer.init(rawValue:))
    }

    static func counts(in tiles: [[String: Any]]) -> Counts {
        tiles.reduce(into: Counts()) { counts, tile in
            switch spacerKind(tile) {
            case .regular: counts.regular += 1
            case .small: counts.small += 1
            case nil: break
            }
        }
    }

    static func withoutSpacers(_ tiles: [[String: Any]]) -> [[String: Any]] {
        tiles.filter { spacerKind($0) == nil }
    }
}

/// Резервные копии `com.apple.dock` через `defaults export/import`.
enum DockBackup {
    static let domain = "com.apple.dock"

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacTweaks/backups", isDirectory: true)
    }

    enum Failure: LocalizedError {
        case export, `import`
        var errorDescription: String? {
            switch self {
            case .export: "Не удалось сделать резервную копию Dock — изменения не внесены."
            case .import: "Не удалось восстановить настройки Dock из копии."
            }
        }
    }

    static func make() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = directory.appendingPathComponent("dock-\(formatter.string(from: Date())).plist")
        guard Shell.run("/usr/bin/defaults", ["export", domain, url.path]) == 0,
              FileManager.default.fileExists(atPath: url.path) else { throw Failure.export }
        return url
    }

    /// Имена с датой в формате yyyy-MM-dd_HH-mm-ss сортируются по времени.
    static var latest: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("dock-") && $0.pathExtension == "plist" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func restore(from url: URL) throws {
        guard Shell.run("/usr/bin/defaults", ["import", domain, url.path]) == 0 else { throw Failure.import }
        CFPreferencesAppSynchronize(domain as CFString)
    }
}
