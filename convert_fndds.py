#!/usr/bin/env python3
"""Convert USDA FNDDS surveyDownload.json → fndds.sqlite for FoodLog app."""

import json
import sqlite3
import os

INPUT = "surveyDownload.json"
OUTPUT = os.path.join("FoodLog", "Resources", "fndds.sqlite")

# Nutrient ID → SQLite column name (32 nutrients mapped to HealthKit)
NUTRIENT_COLUMNS = {
    1008: "energy_kcal",
    1003: "protein_g",
    1004: "fat_g",
    1005: "carbohydrate_g",
    1079: "fiber_g",
    2000: "sugar_g",
    1258: "saturated_fat_g",
    1292: "monounsaturated_fat_g",
    1293: "polyunsaturated_fat_g",
    1253: "cholesterol_mg",
    1087: "calcium_mg",
    1089: "iron_mg",
    1090: "magnesium_mg",
    1091: "phosphorus_mg",
    1092: "potassium_mg",
    1093: "sodium_mg",
    1095: "zinc_mg",
    1098: "copper_mg",
    1103: "selenium_mcg",
    1162: "vitamin_c_mg",
    1165: "thiamin_mg",
    1166: "riboflavin_mg",
    1167: "niacin_mg",
    1175: "vitamin_b6_mg",
    1190: "folate_dfe_mcg",
    1178: "vitamin_b12_mcg",
    1106: "vitamin_a_rae_mcg",
    1109: "vitamin_e_mg",
    1114: "vitamin_d_mcg",
    1185: "vitamin_k_mcg",
    1057: "caffeine_mg",
    1051: "water_g",
}

def main():
    print(f"Loading {INPUT}...")
    with open(INPUT) as f:
        data = json.load(f)

    foods = data["SurveyFoods"]
    print(f"Found {len(foods)} foods")

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    conn = sqlite3.connect(OUTPUT)
    cur = conn.cursor()

    # Create foods table with denormalized nutrient columns (per 100g)
    nutrient_col_defs = ", ".join(f"{col} REAL DEFAULT 0" for col in NUTRIENT_COLUMNS.values())
    cur.execute(f"""
        CREATE TABLE foods (
            food_code INTEGER PRIMARY KEY,
            description TEXT NOT NULL,
            {nutrient_col_defs}
        )
    """)

    # Create portions table
    cur.execute("""
        CREATE TABLE portions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            food_code INTEGER NOT NULL,
            description TEXT NOT NULL,
            gram_weight REAL NOT NULL,
            FOREIGN KEY (food_code) REFERENCES foods(food_code)
        )
    """)

    # Create FTS5 virtual table for full-text search
    cur.execute("""
        CREATE VIRTUAL TABLE foods_fts USING fts5(
            description,
            food_code UNINDEXED,
            tokenize='porter unicode61'
        )
    """)

    cols = list(NUTRIENT_COLUMNS.values())
    placeholders = ", ".join(["?"] * (2 + len(cols)))
    col_names = ", ".join(["food_code", "description"] + cols)
    insert_food_sql = f"INSERT INTO foods ({col_names}) VALUES ({placeholders})"

    food_count = 0
    portion_count = 0

    for food in foods:
        food_code = food.get("foodCode")
        description = food.get("description", "")
        nutrients = food.get("foodNutrients", [])

        if not food_code or not nutrients:
            continue

        # Build nutrient lookup: nutrient_id → amount (per 100g)
        nutrient_map = {}
        for n in nutrients:
            nid = n.get("nutrient", {}).get("id")
            amount = n.get("amount", 0)
            if nid and nid in NUTRIENT_COLUMNS:
                nutrient_map[nid] = amount or 0

        values = [food_code, description]
        for nid in NUTRIENT_COLUMNS:
            values.append(nutrient_map.get(nid, 0))

        cur.execute(insert_food_sql, values)

        # Insert into FTS index
        cur.execute(
            "INSERT INTO foods_fts (description, food_code) VALUES (?, ?)",
            (description, food_code)
        )

        # Insert portions
        for p in food.get("foodPortions", []):
            gram_weight = p.get("gramWeight", 0)
            portion_desc = p.get("portionDescription", "")
            if gram_weight > 0 and portion_desc:
                cur.execute(
                    "INSERT INTO portions (food_code, description, gram_weight) VALUES (?, ?, ?)",
                    (food_code, portion_desc, gram_weight)
                )
                portion_count += 1

        food_count += 1

    conn.commit()

    # Verify
    cur.execute("SELECT COUNT(*) FROM foods")
    row_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM portions")
    portion_row_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM foods_fts")
    fts_count = cur.fetchone()[0]

    # Test FTS search
    cur.execute("""
        SELECT f.food_code, f.description, f.energy_kcal, f.protein_g
        FROM foods_fts fts
        JOIN foods f ON f.food_code = CAST(fts.food_code AS INTEGER)
        WHERE foods_fts MATCH 'chicken breast'
        LIMIT 5
    """)
    print("\nFTS test - 'chicken breast':")
    for row in cur.fetchall():
        print(f"  {row[0]}: {row[1]} ({row[2]} kcal, {row[3]}g protein)")

    conn.close()

    file_size = os.path.getsize(OUTPUT)
    print(f"\nDone! {OUTPUT}")
    print(f"  Foods: {row_count}")
    print(f"  Portions: {portion_row_count}")
    print(f"  FTS entries: {fts_count}")
    print(f"  File size: {file_size / 1024 / 1024:.1f} MB")

if __name__ == "__main__":
    main()
