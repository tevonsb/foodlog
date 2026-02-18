import Foundation

/// Claude's full response: foods plus optional inferred meal time
struct MealAnalysis: Codable, Sendable {
    let foods: [IdentifiedFood]
    let mealTime: String? // ISO8601, only when user implies a time

    enum CodingKeys: String, CodingKey {
        case foods
        case mealTime = "meal_time"
    }
}

/// Claude's response: identified food item with estimated portion
struct IdentifiedFood: Codable, Sendable {
    let foodName: String
    let estimatedGrams: Double
    let searchTerms: [String]

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case estimatedGrams = "estimated_grams"
        case searchTerms = "search_terms"
    }
}

/// After FNDDS lookup: matched food with scaled nutrients
struct MatchedFood: Sendable {
    let identifiedName: String
    let fnddsDescription: String
    let foodCode: Int
    let grams: Double
    let nutrients: NutrientData
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
}
