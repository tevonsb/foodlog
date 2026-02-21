import Foundation
import SQLite3

struct BarcodeSearchResult: Sendable {
    let barcode: String
    let description: String
    let brand: String?
    let servingSize: Double?
    let servingUnit: String?
    let householdServing: String?
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let saturatedFat: Double
}

final class BarcodeDatabase: Sendable {
    static let shared = BarcodeDatabase()

    private let db: OpaquePointer?

    private init() {
        guard let path = Bundle.main.path(forResource: "branded", ofType: "sqlite") else {
            print("BarcodeDatabase: branded.sqlite not found in bundle")
            db = nil
            return
        }
        var dbPointer: OpaquePointer?
        if sqlite3_open_v2(path, &dbPointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            db = dbPointer
        } else {
            print("BarcodeDatabase: failed to open database")
            db = nil
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func lookup(barcode: String) -> BarcodeSearchResult? {
        guard let db else { return nil }

        let sql = """
            SELECT barcode, description, brand, serving_size, serving_unit,
                   household_serving, calories, protein_g, fat_g, carbs_g,
                   fiber_g, sugar_g, sodium_mg, saturated_fat_g
            FROM branded_foods
            WHERE barcode = ?
            LIMIT 1
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (barcode as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let barcodeVal = String(cString: sqlite3_column_text(stmt, 0))
        let description = String(cString: sqlite3_column_text(stmt, 1))

        let brand: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2)) : nil

        let servingSize: Double? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
            ? sqlite3_column_double(stmt, 3) : nil

        let servingUnit: String? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 4)) : nil

        let householdServing: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 5)) : nil

        return BarcodeSearchResult(
            barcode: barcodeVal,
            description: description,
            brand: brand,
            servingSize: servingSize,
            servingUnit: servingUnit,
            householdServing: householdServing,
            calories: sqlite3_column_double(stmt, 6),
            protein: sqlite3_column_double(stmt, 7),
            fat: sqlite3_column_double(stmt, 8),
            carbs: sqlite3_column_double(stmt, 9),
            fiber: sqlite3_column_double(stmt, 10),
            sugar: sqlite3_column_double(stmt, 11),
            sodium: sqlite3_column_double(stmt, 12),
            saturatedFat: sqlite3_column_double(stmt, 13)
        )
    }
}
