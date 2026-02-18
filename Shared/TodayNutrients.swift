import Foundation

struct TodayNutrients: Codable {
    let calories: Double
    let protein: Double
    let fiber: Double
    let waterOz: Double
    let coffees: Int
    let lastUpdated: Date

    static let placeholder = TodayNutrients(
        calories: 1850, protein: 72, fiber: 18, waterOz: 64, coffees: 2, lastUpdated: .now
    )

    static let empty = TodayNutrients(
        calories: 0, protein: 0, fiber: 0, waterOz: 0, coffees: 0, lastUpdated: .now
    )

    private static let suiteName = "group.com.tevon.foodlog"
    private static let key = "todayNutrients"

    static func load() -> TodayNutrients {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let nutrients = try? JSONDecoder().decode(TodayNutrients.self, from: data) else {
            return .empty
        }
        if !Calendar.current.isDateInToday(nutrients.lastUpdated) {
            return .empty
        }
        return nutrients
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.suiteName) else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
