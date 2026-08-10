import Foundation

/// On-disk persistence: one JSON file per day under Application Support.
///
/// No database on purpose. The data is a handful of dictionaries of counters, the access
/// pattern is "write today, read a date range", and a directory of dated JSON files is
/// inspectable with `cat` — which matters for a product whose central claim is that it
/// isn't recording your text. A user can read the files and verify that themselves.
public struct StatsStore: Sendable {

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Fumble/days/`
    public static func defaultDirectory(
        fileManager: FileManager = .default,
        home: URL? = nil
    ) -> URL {
        let base: URL
        if let home {
            base = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        } else {
            base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        return base
            .appendingPathComponent("Fumble", isDirectory: true)
            .appendingPathComponent("days", isDirectory: true)
    }

    public static func `default`() -> StatsStore {
        StatsStore(directory: defaultDirectory())
    }

    // MARK: - Filenames

    static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public func url(for date: Date) -> URL {
        directory.appendingPathComponent("\(Self.filenameFormatter.string(from: date)).json")
    }

    // MARK: - Read / write

    public func load(_ date: Date) throws -> DayStats? {
        let fileURL = url(for: date)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(DayStats.self, from: data)
        // A future version's file is not something we can safely reason about; ignore rather
        // than misreport. Older versions are readable because fields only get added.
        guard decoded.schemaVersion <= DayStats.currentSchemaVersion else { return nil }
        return decoded
    }

    /// Writes atomically. The app flushes every 30 seconds and on quit, so a crash
    /// mid-write is a realistic event; a truncated day file would lose the whole day.
    public func save(_ day: DayStats) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(day)
        let target = url(for: day.date)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
    }

    /// Every day file present, oldest first. Corrupt or unreadable files are skipped rather
    /// than throwing — one bad day should never make the history unopenable.
    public func loadAll() -> [DayStats] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .compactMap { name -> DayStats? in
                let fileURL = directory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: fileURL),
                      let day = try? JSONDecoder().decode(DayStats.self, from: data),
                      day.schemaVersion <= DayStats.currentSchemaVersion
                else { return nil }
                return day
            }
            .sorted { $0.date < $1.date }
    }

    public func load(from start: Date, to end: Date) -> [DayStats] {
        loadAll().filter { $0.date >= start && $0.date <= end }
    }

    /// Deletes everything. Wired to a visible button — an app with this much access needs a
    /// one-click way out, and it needs to actually work.
    public func deleteAllData() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public var totalBytesOnDisk: UInt64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return 0
        }
        return names.reduce(into: UInt64(0)) { total, name in
            let path = directory.appendingPathComponent(name).path
            if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 {
                total += size
            }
        }
    }
}
