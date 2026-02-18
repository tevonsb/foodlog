import Foundation
import HealthKit

struct NutrientData: Codable, Sendable {
    // MARK: - Macros
    var calories: Double?
    var totalFat: Double?
    var saturatedFat: Double?
    var monounsaturatedFat: Double?
    var polyunsaturatedFat: Double?
    var protein: Double?
    var carbohydrates: Double?
    var fiber: Double?
    var sugar: Double?
    var cholesterol: Double?

    // MARK: - Vitamins
    var vitaminA: Double?
    var vitaminB6: Double?
    var vitaminB12: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var vitaminE: Double?
    var vitaminK: Double?
    var thiamin: Double?
    var riboflavin: Double?
    var niacin: Double?
    var folate: Double?
    var biotin: Double?
    var pantothenicAcid: Double?

    // MARK: - Minerals
    var calcium: Double?
    var iron: Double?
    var magnesium: Double?
    var manganese: Double?
    var phosphorus: Double?
    var potassium: Double?
    var sodium: Double?
    var zinc: Double?
    var chromium: Double?
    var copper: Double?
    var iodine: Double?
    var molybdenum: Double?
    var selenium: Double?
    var chloride: Double?

    // MARK: - Other
    var water: Double?
    var caffeine: Double?

    // MARK: - Init

    init() {}

    // MARK: - Scaling & Combining

    func scaled(by factor: Double) -> NutrientData {
        var result = NutrientData()
        for mapping in Self.allMappings {
            if let value = self[keyPath: mapping.keyPath] {
                result[keyPath: mapping.writableKeyPath] = value * factor
            }
        }
        return result
    }

    static func combined(_ items: [NutrientData]) -> NutrientData {
        var result = NutrientData()
        for item in items {
            for mapping in allMappings {
                if let value = item[keyPath: mapping.keyPath] {
                    let current = result[keyPath: mapping.keyPath] ?? 0
                    result[keyPath: mapping.writableKeyPath] = current + value
                }
            }
        }
        return result
    }

    // MARK: - HealthKit Mapping

    struct NutrientMapping {
        let keyPath: KeyPath<NutrientData, Double?>
        let writableKeyPath: WritableKeyPath<NutrientData, Double?>
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let displayName: String
        let displayUnit: String
    }

    static let allMappings: [NutrientMapping] = [
        // Macros
        .init(keyPath: \.calories, writableKeyPath: \.calories, identifier: .dietaryEnergyConsumed, unit: .kilocalorie(), displayName: "Calories", displayUnit: "kcal"),
        .init(keyPath: \.totalFat, writableKeyPath: \.totalFat, identifier: .dietaryFatTotal, unit: .gramUnit(with: .none), displayName: "Total Fat", displayUnit: "g"),
        .init(keyPath: \.saturatedFat, writableKeyPath: \.saturatedFat, identifier: .dietaryFatSaturated, unit: .gramUnit(with: .none), displayName: "Saturated Fat", displayUnit: "g"),
        .init(keyPath: \.monounsaturatedFat, writableKeyPath: \.monounsaturatedFat, identifier: .dietaryFatMonounsaturated, unit: .gramUnit(with: .none), displayName: "Monounsaturated Fat", displayUnit: "g"),
        .init(keyPath: \.polyunsaturatedFat, writableKeyPath: \.polyunsaturatedFat, identifier: .dietaryFatPolyunsaturated, unit: .gramUnit(with: .none), displayName: "Polyunsaturated Fat", displayUnit: "g"),
        .init(keyPath: \.protein, writableKeyPath: \.protein, identifier: .dietaryProtein, unit: .gramUnit(with: .none), displayName: "Protein", displayUnit: "g"),
        .init(keyPath: \.carbohydrates, writableKeyPath: \.carbohydrates, identifier: .dietaryCarbohydrates, unit: .gramUnit(with: .none), displayName: "Carbohydrates", displayUnit: "g"),
        .init(keyPath: \.fiber, writableKeyPath: \.fiber, identifier: .dietaryFiber, unit: .gramUnit(with: .none), displayName: "Fiber", displayUnit: "g"),
        .init(keyPath: \.sugar, writableKeyPath: \.sugar, identifier: .dietarySugar, unit: .gramUnit(with: .none), displayName: "Sugar", displayUnit: "g"),
        .init(keyPath: \.cholesterol, writableKeyPath: \.cholesterol, identifier: .dietaryCholesterol, unit: .gramUnit(with: .milli), displayName: "Cholesterol", displayUnit: "mg"),

        // Vitamins
        .init(keyPath: \.vitaminA, writableKeyPath: \.vitaminA, identifier: .dietaryVitaminA, unit: .gramUnit(with: .micro), displayName: "Vitamin A", displayUnit: "mcg"),
        .init(keyPath: \.vitaminB6, writableKeyPath: \.vitaminB6, identifier: .dietaryVitaminB6, unit: .gramUnit(with: .milli), displayName: "Vitamin B6", displayUnit: "mg"),
        .init(keyPath: \.vitaminB12, writableKeyPath: \.vitaminB12, identifier: .dietaryVitaminB12, unit: .gramUnit(with: .micro), displayName: "Vitamin B12", displayUnit: "mcg"),
        .init(keyPath: \.vitaminC, writableKeyPath: \.vitaminC, identifier: .dietaryVitaminC, unit: .gramUnit(with: .milli), displayName: "Vitamin C", displayUnit: "mg"),
        .init(keyPath: \.vitaminD, writableKeyPath: \.vitaminD, identifier: .dietaryVitaminD, unit: .gramUnit(with: .micro), displayName: "Vitamin D", displayUnit: "mcg"),
        .init(keyPath: \.vitaminE, writableKeyPath: \.vitaminE, identifier: .dietaryVitaminE, unit: .gramUnit(with: .milli), displayName: "Vitamin E", displayUnit: "mg"),
        .init(keyPath: \.vitaminK, writableKeyPath: \.vitaminK, identifier: .dietaryVitaminK, unit: .gramUnit(with: .micro), displayName: "Vitamin K", displayUnit: "mcg"),
        .init(keyPath: \.thiamin, writableKeyPath: \.thiamin, identifier: .dietaryThiamin, unit: .gramUnit(with: .milli), displayName: "Thiamin", displayUnit: "mg"),
        .init(keyPath: \.riboflavin, writableKeyPath: \.riboflavin, identifier: .dietaryRiboflavin, unit: .gramUnit(with: .milli), displayName: "Riboflavin", displayUnit: "mg"),
        .init(keyPath: \.niacin, writableKeyPath: \.niacin, identifier: .dietaryNiacin, unit: .gramUnit(with: .milli), displayName: "Niacin", displayUnit: "mg"),
        .init(keyPath: \.folate, writableKeyPath: \.folate, identifier: .dietaryFolate, unit: .gramUnit(with: .micro), displayName: "Folate", displayUnit: "mcg"),
        .init(keyPath: \.biotin, writableKeyPath: \.biotin, identifier: .dietaryBiotin, unit: .gramUnit(with: .micro), displayName: "Biotin", displayUnit: "mcg"),
        .init(keyPath: \.pantothenicAcid, writableKeyPath: \.pantothenicAcid, identifier: .dietaryPantothenicAcid, unit: .gramUnit(with: .milli), displayName: "Pantothenic Acid", displayUnit: "mg"),

        // Minerals
        .init(keyPath: \.calcium, writableKeyPath: \.calcium, identifier: .dietaryCalcium, unit: .gramUnit(with: .milli), displayName: "Calcium", displayUnit: "mg"),
        .init(keyPath: \.iron, writableKeyPath: \.iron, identifier: .dietaryIron, unit: .gramUnit(with: .milli), displayName: "Iron", displayUnit: "mg"),
        .init(keyPath: \.magnesium, writableKeyPath: \.magnesium, identifier: .dietaryMagnesium, unit: .gramUnit(with: .milli), displayName: "Magnesium", displayUnit: "mg"),
        .init(keyPath: \.manganese, writableKeyPath: \.manganese, identifier: .dietaryManganese, unit: .gramUnit(with: .milli), displayName: "Manganese", displayUnit: "mg"),
        .init(keyPath: \.phosphorus, writableKeyPath: \.phosphorus, identifier: .dietaryPhosphorus, unit: .gramUnit(with: .milli), displayName: "Phosphorus", displayUnit: "mg"),
        .init(keyPath: \.potassium, writableKeyPath: \.potassium, identifier: .dietaryPotassium, unit: .gramUnit(with: .milli), displayName: "Potassium", displayUnit: "mg"),
        .init(keyPath: \.sodium, writableKeyPath: \.sodium, identifier: .dietarySodium, unit: .gramUnit(with: .milli), displayName: "Sodium", displayUnit: "mg"),
        .init(keyPath: \.zinc, writableKeyPath: \.zinc, identifier: .dietaryZinc, unit: .gramUnit(with: .milli), displayName: "Zinc", displayUnit: "mg"),
        .init(keyPath: \.chromium, writableKeyPath: \.chromium, identifier: .dietaryChromium, unit: .gramUnit(with: .micro), displayName: "Chromium", displayUnit: "mcg"),
        .init(keyPath: \.copper, writableKeyPath: \.copper, identifier: .dietaryCopper, unit: .gramUnit(with: .milli), displayName: "Copper", displayUnit: "mg"),
        .init(keyPath: \.iodine, writableKeyPath: \.iodine, identifier: .dietaryIodine, unit: .gramUnit(with: .micro), displayName: "Iodine", displayUnit: "mcg"),
        .init(keyPath: \.molybdenum, writableKeyPath: \.molybdenum, identifier: .dietaryMolybdenum, unit: .gramUnit(with: .micro), displayName: "Molybdenum", displayUnit: "mcg"),
        .init(keyPath: \.selenium, writableKeyPath: \.selenium, identifier: .dietarySelenium, unit: .gramUnit(with: .micro), displayName: "Selenium", displayUnit: "mcg"),
        .init(keyPath: \.chloride, writableKeyPath: \.chloride, identifier: .dietaryChloride, unit: .gramUnit(with: .milli), displayName: "Chloride", displayUnit: "mg"),

        // Other
        .init(keyPath: \.water, writableKeyPath: \.water, identifier: .dietaryWater, unit: .literUnit(with: .milli), displayName: "Water", displayUnit: "mL"),
        .init(keyPath: \.caffeine, writableKeyPath: \.caffeine, identifier: .dietaryCaffeine, unit: .gramUnit(with: .milli), displayName: "Caffeine", displayUnit: "mg"),
    ]

    func nonNilNutrients() -> [(mapping: NutrientMapping, value: Double)] {
        NutrientData.allMappings.compactMap { mapping in
            guard let value = self[keyPath: mapping.keyPath] else { return nil }
            return (mapping, value)
        }
    }
}
