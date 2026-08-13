import Foundation
import Testing
@testable import FumbleCore

@Suite("StatsStore")
struct StatsStoreTests {

    private func makeTemporaryStore() -> StatsStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FumbleTests-\(UUID().uuidString)", isDirectory: true)
        return StatsStore(directory: directory)
    }

    private func cleanUp(_ store: StatsStore) {
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("saves and reloads a day unchanged")
    func roundTrip() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }

        var day = DayStats(date: Calendar.current.startOfDay(for: Date()))
        day.totalPresses = 1_234
        day.activeSeconds = 456.7
        var stat = KeyStat()
        stat.presses = 99
        stat.latency.add(milliseconds: 120)
        day.keys[0] = stat

        try store.save(day)
        let loaded = try #require(try store.load(day.date))
        #expect(loaded == day)
    }

    @Test("missing day returns nil rather than throwing")
    func missingDay() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }
        #expect(try store.load(Date(timeIntervalSince1970: 0)) == nil)
    }

    @Test("save overwrites the same day rather than accumulating files")
    func overwrite() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }

        let date = Calendar.current.startOfDay(for: Date())
        var day = DayStats(date: date)
        day.totalPresses = 10
        try store.save(day)
        day.totalPresses = 20
        try store.save(day)

        #expect(store.loadAll().count == 1)
        #expect(try store.load(date)?.totalPresses == 20)
    }

    @Test("loadAll returns days oldest first and skips corrupt files")
    func loadAllSkipsCorrupt() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }

        for offset in [0, 86_400, 172_800] {
            var day = DayStats(date: Date(timeIntervalSince1970: Double(offset)))
            day.totalPresses = UInt64(offset)
            try store.save(day)
        }
        // A truncated file must not make the whole history unopenable.
        try "{ not json".write(
            to: store.directory.appendingPathComponent("1999-01-01.json"),
            atomically: true, encoding: .utf8
        )

        let all = store.loadAll()
        #expect(all.count == 3)
        #expect(all.map(\.date) == all.map(\.date).sorted())
    }

    @Test("a pre-v2 day file (no motor fields) still loads, with latency intact")
    func loadsLegacyFileWithoutMotorFields() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }

        // Hand-write a v1-shaped file: per-key latency present, but no motorLatency or
        // motorClassification. This is exactly what broke when the schema changed.
        let date = Calendar.current.startOfDay(for: Date())
        let stamp = StatsStore.filenameFormatter.string(from: date)
        let epoch = date.timeIntervalSinceReferenceDate
        let legacy = """
        {"schemaVersion":1,"date":\(epoch),"totalPresses":300,"totalCorrections":5,
         "activeSeconds":120,"rejectedSynthetic":0,"rejectedSecureInput":0,
         "rejectedAutorepeat":0,"discardedPauses":2,"apps":{},"bigrams":{},
         "keys":{"6":{"presses":300,"corrections":5,"latency":{"c":[0,0,0,0,0,0,0,0,0,300,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"n":300,"s":27000}}}}
        """
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try legacy.write(to: store.directory.appendingPathComponent("\(stamp).json"),
                         atomically: true, encoding: .utf8)

        let loaded = try #require(try store.load(date))
        #expect(loaded.totalPresses == 300)
        // The recovered latency must still be usable: overallLatency falls back to the per-key
        // histograms when motorLatency is absent.
        #expect(loaded.overallLatency.total == 300)
        #expect(loaded.motorLatency.total == 0)          // absent in the file, defaulted
        #expect(loaded.motorClassification.total == 0)   // absent in the file, defaulted
    }

    @Test("a future schema version is ignored rather than misread")
    func futureSchema() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }

        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        day.schemaVersion = DayStats.currentSchemaVersion + 1
        try store.save(day)

        #expect(try store.load(day.date) == nil)
        #expect(store.loadAll().isEmpty)
    }

    @Test("deleteAllData removes everything")
    func deleteAll() throws {
        let store = makeTemporaryStore()
        defer { cleanUp(store) }

        try store.save(DayStats(date: Date(timeIntervalSince1970: 0)))
        #expect(store.totalBytesOnDisk > 0)

        try store.deleteAllData()
        #expect(store.loadAll().isEmpty)
        #expect(store.totalBytesOnDisk == 0)
    }

    @Test("day merging sums every counter")
    func merging() {
        var a = DayStats(date: Date(timeIntervalSince1970: 0))
        a.totalPresses = 100
        a.activeSeconds = 50
        a.keys[0] = { var stat = KeyStat(); stat.presses = 60; return stat }()

        var b = DayStats(date: Date(timeIntervalSince1970: 86_400))
        b.totalPresses = 200
        b.activeSeconds = 75
        b.keys[0] = { var stat = KeyStat(); stat.presses = 40; return stat }()

        let merged = a.merged(with: b)
        #expect(merged.totalPresses == 300)
        #expect(merged.activeSeconds == 125)
        #expect(merged.keys[0]?.presses == 100)
    }
}
