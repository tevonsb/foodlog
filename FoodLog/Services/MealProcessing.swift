import Foundation

enum MealProcessing {
    struct ProcessedMeal {
        let nutrients: NutrientData
        let foods: [LoggedFood]
        let mealDate: Date
        let mealLabel: String?
        let message: String?
    }

    static func processAnalysis(_ meal: AgenticMealResult, fallbackDate: Date) -> ProcessedMeal {
        let db = FNDDSDatabase.shared
        var nutrientsList: [NutrientData] = []
        var loggedFoods: [LoggedFood] = []

        for food in meal.foods {
            let nutrients: NutrientData
            if food.source == "database", let foodCode = food.foodCode,
               let dbNutrients = db.getNutrients(foodCode: foodCode, grams: food.grams) {
                nutrients = dbNutrients
            } else {
                nutrients = makeMacroOnlyNutrients(food)
            }
            nutrientsList.append(nutrients)

            loggedFoods.append(LoggedFood(
                name: food.foodName,
                matchedDescription: food.matchedDescription ?? "Estimated",
                grams: food.grams,
                calories: food.calories,
                protein: food.protein,
                carbs: food.carbs,
                fat: food.fat,
                source: food.source
            ))
        }

        let totalNutrients = NutrientData.combined(nutrientsList)
        let mealDate = parseMealTime(meal.mealTime) ?? fallbackDate

        return ProcessedMeal(
            nutrients: totalNutrients,
            foods: loggedFoods,
            mealDate: mealDate,
            mealLabel: meal.mealLabel,
            message: meal.message
        )
    }

    static func makeMacroOnlyNutrients(_ food: AgenticFoodResult) -> NutrientData {
        var n = NutrientData()
        n.calories = food.calories
        n.protein = food.protein
        n.totalFat = food.fat
        n.carbohydrates = food.carbs
        n.fiber = food.fiber
        n.sugar = food.sugar
        return n
    }

    static func parseMealTime(_ mealTimeString: String?) -> Date? {
        guard let mealTimeString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: mealTimeString) { return parsed }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: mealTimeString)
    }
}
