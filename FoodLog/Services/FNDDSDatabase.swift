import Foundation
import SQLite3

struct FNDDSSearchResult: Sendable {
    let foodCode: Int
    let description: String
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let carbsPer100g: Double
    let fiberPer100g: Double
    let sugarPer100g: Double
    let portions: [(description: String, grams: Double)]
}

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

    // MARK: - Agentic search methods

    private func sanitizeFTSQuery(_ query: String) -> String {
        query.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map { String($0) }
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " ")
    }

    func searchTopN(query: String, limit: Int = 3) -> [FNDDSSearchResult] {
        guard let db else { return [] }

        let ftsQuery = sanitizeFTSQuery(query)
        guard !ftsQuery.isEmpty else { return [] }

        let sql = """
            SELECT f.food_code, f.description,
                f.energy_kcal, f.protein_g, f.fat_g, f.carbohydrate_g,
                f.fiber_g, f.sugar_g
            FROM foods_fts fts
            JOIN foods f ON f.food_code = CAST(fts.food_code AS INTEGER)
            WHERE foods_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [FNDDSSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let foodCode = Int(sqlite3_column_int(stmt, 0))
            guard let textPtr = sqlite3_column_text(stmt, 1) else { continue }
            let description = String(cString: textPtr)

            let portions = fetchPortions(foodCode: foodCode)

            results.append(FNDDSSearchResult(
                foodCode: foodCode,
                description: description,
                caloriesPer100g: sqlite3_column_double(stmt, 2),
                proteinPer100g: sqlite3_column_double(stmt, 3),
                fatPer100g: sqlite3_column_double(stmt, 4),
                carbsPer100g: sqlite3_column_double(stmt, 5),
                fiberPer100g: sqlite3_column_double(stmt, 6),
                sugarPer100g: sqlite3_column_double(stmt, 7),
                portions: portions
            ))
        }
        return results
    }

    private func fetchPortions(foodCode: Int) -> [(description: String, grams: Double)] {
        guard let db else { return [] }

        let sql = "SELECT description, gram_weight FROM portions WHERE food_code = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(foodCode))

        var portions: [(String, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let textPtr = sqlite3_column_text(stmt, 0) else { continue }
            let desc = String(cString: textPtr)
            let grams = sqlite3_column_double(stmt, 1)
            portions.append((desc, grams))
        }
        return portions
    }

    func getNutrients(foodCode: Int, grams: Double) -> NutrientData? {
        guard let db else { return nil }

        let sql = """
            SELECT energy_kcal, protein_g, fat_g, carbohydrate_g,
                fiber_g, sugar_g, saturated_fat_g, monounsaturated_fat_g,
                polyunsaturated_fat_g, cholesterol_mg, calcium_mg, iron_mg,
                magnesium_mg, phosphorus_mg, potassium_mg, sodium_mg,
                zinc_mg, copper_mg, selenium_mcg, vitamin_c_mg,
                thiamin_mg, riboflavin_mg, niacin_mg, vitamin_b6_mg,
                folate_dfe_mcg, vitamin_b12_mcg, vitamin_a_rae_mcg,
                vitamin_e_mg, vitamin_d_mcg, vitamin_k_mcg,
                caffeine_mg, water_g
            FROM foods WHERE food_code = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(foodCode))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let scale = grams / 100.0
        var nutrients = NutrientData()
        nutrients.calories = sqlite3_column_double(stmt, 0) * scale
        nutrients.protein = sqlite3_column_double(stmt, 1) * scale
        nutrients.totalFat = sqlite3_column_double(stmt, 2) * scale
        nutrients.carbohydrates = sqlite3_column_double(stmt, 3) * scale
        nutrients.fiber = sqlite3_column_double(stmt, 4) * scale
        nutrients.sugar = sqlite3_column_double(stmt, 5) * scale
        nutrients.saturatedFat = sqlite3_column_double(stmt, 6) * scale
        nutrients.monounsaturatedFat = sqlite3_column_double(stmt, 7) * scale
        nutrients.polyunsaturatedFat = sqlite3_column_double(stmt, 8) * scale
        nutrients.cholesterol = sqlite3_column_double(stmt, 9) * scale
        nutrients.calcium = sqlite3_column_double(stmt, 10) * scale
        nutrients.iron = sqlite3_column_double(stmt, 11) * scale
        nutrients.magnesium = sqlite3_column_double(stmt, 12) * scale
        nutrients.phosphorus = sqlite3_column_double(stmt, 13) * scale
        nutrients.potassium = sqlite3_column_double(stmt, 14) * scale
        nutrients.sodium = sqlite3_column_double(stmt, 15) * scale
        nutrients.zinc = sqlite3_column_double(stmt, 16) * scale
        nutrients.copper = sqlite3_column_double(stmt, 17) * scale
        nutrients.selenium = sqlite3_column_double(stmt, 18) * scale
        nutrients.vitaminC = sqlite3_column_double(stmt, 19) * scale
        nutrients.thiamin = sqlite3_column_double(stmt, 20) * scale
        nutrients.riboflavin = sqlite3_column_double(stmt, 21) * scale
        nutrients.niacin = sqlite3_column_double(stmt, 22) * scale
        nutrients.vitaminB6 = sqlite3_column_double(stmt, 23) * scale
        nutrients.folate = sqlite3_column_double(stmt, 24) * scale
        nutrients.vitaminB12 = sqlite3_column_double(stmt, 25) * scale
        nutrients.vitaminA = sqlite3_column_double(stmt, 26) * scale
        nutrients.vitaminE = sqlite3_column_double(stmt, 27) * scale
        nutrients.vitaminD = sqlite3_column_double(stmt, 28) * scale
        nutrients.vitaminK = sqlite3_column_double(stmt, 29) * scale
        nutrients.caffeine = sqlite3_column_double(stmt, 30) * scale
        nutrients.water = sqlite3_column_double(stmt, 31) * scale
        return nutrients
    }

}
