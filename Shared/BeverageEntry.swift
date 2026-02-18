import Foundation

enum BeverageType: String, Codable {
    case water
    case coffee
}

struct BeverageEntry: Codable, Identifiable {
    let id: UUID
    let type: BeverageType
    let timestamp: Date
    let amount: Double // oz for water, count (1) for coffee
    let healthKitSampleUUID: String?

    init(type: BeverageType, amount: Double, healthKitSampleUUID: String? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.amount = amount
        self.healthKitSampleUUID = healthKitSampleUUID
    }
}

struct BeverageStore {
    private static let suiteName = "group.com.tevon.foodlog"
    private static let key = "beverageEntries"

    static func loadToday() -> [BeverageEntry] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([BeverageEntry].self, from: data) else {
            return []
        }
        return entries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    static func append(_ entry: BeverageEntry) {
        var entries = loadAll()
        entries.append(entry)
        save(entries)
    }

    static func remove(id: UUID) {
        var entries = loadAll()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    static func todayWaterOz() -> Double {
        loadToday().filter { $0.type == .water }.reduce(0) { $0 + $1.amount }
    }

    static func todayCoffeeCount() -> Int {
        loadToday().filter { $0.type == .coffee }.count
    }

    // MARK: - Private

    private static func loadAll() -> [BeverageEntry] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([BeverageEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private static func save(_ entries: [BeverageEntry]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        // Only keep today's entries to prevent unbounded growth
        let todayEntries = entries.filter { Calendar.current.isDateInToday($0.timestamp) }
        if let data = try? JSONEncoder().encode(todayEntries) {
            defaults.set(data, forKey: key)
        }
    }
}
