import Foundation

struct TodayNutrients: Codable {
    let calories: Double
    let protein: Double
    let fiber: Double
    let waterOz: Double
    let coffees: Int
    let lastUpdated: Date

    // Secondary macros
    let carbs: Double
    let fat: Double
    let sugar: Double
    let sodium: Double
    let cholesterol: Double
    let saturatedFat: Double

    init(calories: Double, protein: Double, fiber: Double, waterOz: Double, coffees: Int,
         lastUpdated: Date, carbs: Double = 0, fat: Double = 0, sugar: Double = 0,
         sodium: Double = 0, cholesterol: Double = 0, saturatedFat: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.fiber = fiber
        self.waterOz = waterOz
        self.coffees = coffees
        self.lastUpdated = lastUpdated
        self.carbs = carbs
        self.fat = fat
        self.sugar = sugar
        self.sodium = sodium
        self.cholesterol = cholesterol
        self.saturatedFat = saturatedFat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calories = try container.decode(Double.self, forKey: .calories)
        protein = try container.decode(Double.self, forKey: .protein)
        fiber = try container.decode(Double.self, forKey: .fiber)
        waterOz = try container.decode(Double.self, forKey: .waterOz)
        coffees = try container.decode(Int.self, forKey: .coffees)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        sugar = try container.decodeIfPresent(Double.self, forKey: .sugar) ?? 0
        sodium = try container.decodeIfPresent(Double.self, forKey: .sodium) ?? 0
        cholesterol = try container.decodeIfPresent(Double.self, forKey: .cholesterol) ?? 0
        saturatedFat = try container.decodeIfPresent(Double.self, forKey: .saturatedFat) ?? 0
    }

    static let placeholder = TodayNutrients(
        calories: 1850, protein: 72, fiber: 18, waterOz: 64, coffees: 2, lastUpdated: .now,
        carbs: 210, fat: 65, sugar: 42, sodium: 1800, cholesterol: 180, saturatedFat: 22
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
