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
    var healthKitSampleUUID: String?
    let label: String?
    let caffeineMg: Double?
    let trackedViaMeal: Bool

    init(type: BeverageType, amount: Double, healthKitSampleUUID: String? = nil, label: String? = nil, caffeineMg: Double? = nil, trackedViaMeal: Bool = false) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.amount = amount
        self.healthKitSampleUUID = healthKitSampleUUID
        self.label = label
        self.caffeineMg = caffeineMg
        self.trackedViaMeal = trackedViaMeal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(BeverageType.self, forKey: .type)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        amount = try c.decode(Double.self, forKey: .amount)
        healthKitSampleUUID = try c.decodeIfPresent(String.self, forKey: .healthKitSampleUUID)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        caffeineMg = try c.decodeIfPresent(Double.self, forKey: .caffeineMg)
        trackedViaMeal = (try c.decodeIfPresent(Bool.self, forKey: .trackedViaMeal)) ?? false
    }

    /// Needs HealthKit sync only if it doesn't already have a sample AND isn't tracked via a FoodEntry meal.
    var needsHealthKitSync: Bool { healthKitSampleUUID == nil && !trackedViaMeal }
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

    static func markSynced(id: UUID, healthKitSampleUUID: String) {
        var entries = loadAll()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].healthKitSampleUUID = healthKitSampleUUID
            save(entries)
        }
    }

    static func unsyncedEntries() -> [BeverageEntry] {
        loadToday().filter { $0.needsHealthKitSync }
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
