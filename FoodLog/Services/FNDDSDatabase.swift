import Foundation
import SQLite3

final class FNDDSDatabase: Sendable {
    static let shared = FNDDSDatabase()

    private let db: OpaquePointer?

    private init() {
        guard let path = Bundle.main.path(forResource: "fndds", ofType: "sqlite") else {
            print("FNDDSDatabase: fndds.sqlite not found in bundle")
            db = nil
            return
        }
        var dbPointer: OpaquePointer?
        if sqlite3_open_v2(path, &dbPointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            db = dbPointer
        } else {
            print("FNDDSDatabase: failed to open database")
            db = nil
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func search(identifiedName: String, terms: [String], grams: Double) -> MatchedFood? {
        guard let db else { return nil }

        for term in terms {
            let ftsQuery = term
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\"\($0)\"" }
                .joined(separator: " ")

            let sql = """
                SELECT f.food_code, f.description,
                    f.energy_kcal, f.protein_g, f.fat_g, f.carbohydrate_g,
                    f.fiber_g, f.sugar_g, f.saturated_fat_g, f.monounsaturated_fat_g,
                    f.polyunsaturated_fat_g, f.cholesterol_mg, f.calcium_mg, f.iron_mg,
                    f.magnesium_mg, f.phosphorus_mg, f.potassium_mg, f.sodium_mg,
                    f.zinc_mg, f.copper_mg, f.selenium_mcg, f.vitamin_c_mg,
                    f.thiamin_mg, f.riboflavin_mg, f.niacin_mg, f.vitamin_b6_mg,
                    f.folate_dfe_mcg, f.vitamin_b12_mcg, f.vitamin_a_rae_mcg,
                    f.vitamin_e_mg, f.vitamin_d_mcg, f.vitamin_k_mcg,
                    f.caffeine_mg, f.water_g
                FROM foods_fts fts
                JOIN foods f ON f.food_code = CAST(fts.food_code AS INTEGER)
                WHERE foods_fts MATCH ?
                ORDER BY rank
                LIMIT 1
                """

            if let result = executeSearch(sql: sql, param: ftsQuery, identifiedName: identifiedName, grams: grams) {
                return result
            }
        }

        if let firstTerm = terms.first {
            let sql = """
                SELECT food_code, description,
                    energy_kcal, protein_g, fat_g, carbohydrate_g,
                    fiber_g, sugar_g, saturated_fat_g, monounsaturated_fat_g,
                    polyunsaturated_fat_g, cholesterol_mg, calcium_mg, iron_mg,
                    magnesium_mg, phosphorus_mg, potassium_mg, sodium_mg,
                    zinc_mg, copper_mg, selenium_mcg, vitamin_c_mg,
                    thiamin_mg, riboflavin_mg, niacin_mg, vitamin_b6_mg,
                    folate_dfe_mcg, vitamin_b12_mcg, vitamin_a_rae_mcg,
                    vitamin_e_mg, vitamin_d_mcg, vitamin_k_mcg,
                    caffeine_mg, water_g
                FROM foods
                WHERE description LIKE ?
                LIMIT 1
                """
            let likeParam = "%\(firstTerm)%"
            if let result = executeSearch(sql: sql, param: likeParam, identifiedName: identifiedName, grams: grams) {
                return result
            }
        }

        return nil
    }

    private func executeSearch(sql: String, param: String, identifiedName: String, grams: Double) -> MatchedFood? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (param as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let foodCode = Int(sqlite3_column_int(stmt, 0))
        guard let textPtr = sqlite3_column_text(stmt, 1) else { return nil }
        let description = String(cString: textPtr)

        let scale = grams / 100.0
        var nutrients = NutrientData()
        nutrients.calories = sqlite3_column_double(stmt, 2) * scale
        nutrients.protein = sqlite3_column_double(stmt, 3) * scale
        nutrients.totalFat = sqlite3_column_double(stmt, 4) * scale
        nutrients.carbohydrates = sqlite3_column_double(stmt, 5) * scale
        nutrients.fiber = sqlite3_column_double(stmt, 6) * scale
        nutrients.sugar = sqlite3_column_double(stmt, 7) * scale
        nutrients.saturatedFat = sqlite3_column_double(stmt, 8) * scale
        nutrients.monounsaturatedFat = sqlite3_column_double(stmt, 9) * scale
        nutrients.polyunsaturatedFat = sqlite3_column_double(stmt, 10) * scale
        nutrients.cholesterol = sqlite3_column_double(stmt, 11) * scale
        nutrients.calcium = sqlite3_column_double(stmt, 12) * scale
        nutrients.iron = sqlite3_column_double(stmt, 13) * scale
        nutrients.magnesium = sqlite3_column_double(stmt, 14) * scale
        nutrients.phosphorus = sqlite3_column_double(stmt, 15) * scale
        nutrients.potassium = sqlite3_column_double(stmt, 16) * scale
        nutrients.sodium = sqlite3_column_double(stmt, 17) * scale
        nutrients.zinc = sqlite3_column_double(stmt, 18) * scale
        nutrients.copper = sqlite3_column_double(stmt, 19) * scale
        nutrients.selenium = sqlite3_column_double(stmt, 20) * scale
        nutrients.vitaminC = sqlite3_column_double(stmt, 21) * scale
        nutrients.thiamin = sqlite3_column_double(stmt, 22) * scale
        nutrients.riboflavin = sqlite3_column_double(stmt, 23) * scale
        nutrients.niacin = sqlite3_column_double(stmt, 24) * scale
        nutrients.vitaminB6 = sqlite3_column_double(stmt, 25) * scale
        nutrients.folate = sqlite3_column_double(stmt, 26) * scale
        nutrients.vitaminB12 = sqlite3_column_double(stmt, 27) * scale
        nutrients.vitaminA = sqlite3_column_double(stmt, 28) * scale
        nutrients.vitaminE = sqlite3_column_double(stmt, 29) * scale
        nutrients.vitaminD = sqlite3_column_double(stmt, 30) * scale
        nutrients.vitaminK = sqlite3_column_double(stmt, 31) * scale
        nutrients.caffeine = sqlite3_column_double(stmt, 32) * scale
        nutrients.water = sqlite3_column_double(stmt, 33) * scale

        return MatchedFood(
            identifiedName: identifiedName,
            fnddsDescription: description,
            foodCode: foodCode,
            grams: grams,
            nutrients: nutrients
        )
    }
}
