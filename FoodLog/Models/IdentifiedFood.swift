import Foundation

/// A single food result from the agentic tool-use loop
struct AgenticFoodResult: Codable, Sendable {
    let foodName: String
    let grams: Double
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let fiber: Double
    let sugar: Double
    let source: String // "database" or "estimate"
    let foodCode: Int?
    let matchedDescription: String?

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case grams, calories, protein, fat, carbs, fiber, sugar, source
        case foodCode = "food_code"
        case matchedDescription = "matched_description"
    }
}

/// Complete meal analysis from the agentic loop
struct AgenticMealAnalysis: Codable, Sendable {
    let foods: [AgenticFoodResult]
    let mealTime: String?

    enum CodingKeys: String, CodingKey {
        case foods
        case mealTime = "meal_time"
    }
}

/// Simplified Codable struct for SwiftData storage in FoodEntry.foodsJSON
struct LoggedFood: Codable, Sendable {
    let name: String
    let matchedDescription: String
    let grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let source: String?

    init(name: String, matchedDescription: String, grams: Double, calories: Double, protein: Double, carbs: Double, fat: Double, source: String? = nil) {
        self.name = name
        self.matchedDescription = matchedDescription
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        matchedDescription = try c.decode(String.self, forKey: .matchedDescription)
        grams = try c.decode(Double.self, forKey: .grams)
        calories = try c.decode(Double.self, forKey: .calories)
        protein = try c.decode(Double.self, forKey: .protein)
        carbs = try c.decode(Double.self, forKey: .carbs)
        fat = try c.decode(Double.self, forKey: .fat)
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}
