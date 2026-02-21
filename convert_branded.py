#!/usr/bin/env python3
"""Convert USDA FoodData Central Branded Foods CSV → branded.sqlite for FoodLog app.

Download the Branded Foods CSV from https://fdc.nal.usda.gov/download-datasets/
Extract the CSV files into the repo root (or a subdirectory), then run:

    python3 convert_branded.py              # CSVs in current directory
    python3 convert_branded.py /path/to/dir # CSVs in specified directory

The script reads three CSV files:
  - food.csv            → fdc_id, description
  - branded_food.csv    → fdc_id, gtin_upc, brand_owner, serving_size, etc.
  - food_nutrient.csv   → fdc_id, nutrient_id, amount
"""

import csv
import sqlite3
import os
import sys

OUTPUT = os.path.join("FoodLog", "Resources", "branded.sqlite")

# Nutrient IDs we care about (from USDA nutrient numbering)
NUTRIENT_IDS = {
    1008: "calories",       # Energy (kcal)
    1003: "protein_g",      # Protein
    1004: "fat_g",          # Total lipid (fat)
    1005: "carbs_g",        # Carbohydrate
    1079: "fiber_g",        # Fiber, total dietary
    2000: "sugar_g",        # Sugars, total
    1093: "sodium_mg",      # Sodium
    1258: "saturated_fat_g", # Fatty acids, total saturated
}


def main():
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "."

    food_csv = os.path.join(data_dir, "food.csv")
    branded_csv = os.path.join(data_dir, "branded_food.csv")
    nutrient_csv = os.path.join(data_dir, "food_nutrient.csv")

    for path in [food_csv, branded_csv, nutrient_csv]:
        if not os.path.exists(path):
            print(f"ERROR: {path} not found")
            sys.exit(1)

    # Step 1: Build fdc_id → description map (only branded foods, data_type == "branded_food")
    print("Reading food.csv...")
    food_descriptions = {}
    with open(food_csv, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("data_type") == "branded_food":
                fdc_id = row["fdc_id"]
                food_descriptions[fdc_id] = row.get("description", "")
    print(f"  Found {len(food_descriptions)} branded food descriptions")

    # Step 2: Parse branded_food.csv for barcode + serving info
    print("Reading branded_food.csv...")
    branded_info = {}  # fdc_id → dict
    skipped_no_barcode = 0
    with open(branded_csv, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            barcode = row.get("gtin_upc", "").strip()
            if not barcode:
                skipped_no_barcode += 1
                continue

            fdc_id = row["fdc_id"]
            serving_size = row.get("serving_size", "")
            try:
                serving_size = float(serving_size) if serving_size else None
            except ValueError:
                serving_size = None

            branded_info[fdc_id] = {
                "barcode": barcode,
                "brand": row.get("brand_owner", "").strip() or row.get("brand_name", "").strip(),
                "serving_size": serving_size,
                "serving_unit": row.get("serving_size_unit", "").strip(),
                "household_serving": row.get("household_serving_fulltext", "").strip(),
            }
    print(f"  Found {len(branded_info)} products with barcodes (skipped {skipped_no_barcode} without)")

    # Step 3: Parse food_nutrient.csv for macros
    print("Reading food_nutrient.csv (this may take a moment)...")
    # Only load nutrients for fdc_ids we have branded info for
    target_fdc_ids = set(branded_info.keys())
    nutrients = {}  # fdc_id → {nutrient_col: amount}
    rows_read = 0
    with open(nutrient_csv, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows_read += 1
            if rows_read % 5_000_000 == 0:
                print(f"  ... processed {rows_read:,} nutrient rows")

            fdc_id = row["fdc_id"]
            if fdc_id not in target_fdc_ids:
                continue

            try:
                nutrient_id = int(row["nutrient_id"])
            except (ValueError, KeyError):
                continue

            if nutrient_id not in NUTRIENT_IDS:
                continue

            col_name = NUTRIENT_IDS[nutrient_id]
            try:
                amount = float(row.get("amount", 0) or 0)
            except ValueError:
                amount = 0.0

            if fdc_id not in nutrients:
                nutrients[fdc_id] = {}
            nutrients[fdc_id][col_name] = amount

    print(f"  Read {rows_read:,} total nutrient rows, got data for {len(nutrients)} products")

    # Step 4: Join and write SQLite
    print("Writing SQLite database...")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    conn = sqlite3.connect(OUTPUT)
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE branded_foods (
            barcode TEXT PRIMARY KEY,
            description TEXT NOT NULL,
            brand TEXT,
            serving_size REAL,
            serving_unit TEXT,
            household_serving TEXT,
            calories REAL DEFAULT 0,
            protein_g REAL DEFAULT 0,
            fat_g REAL DEFAULT 0,
            carbs_g REAL DEFAULT 0,
            fiber_g REAL DEFAULT 0,
            sugar_g REAL DEFAULT 0,
            sodium_mg REAL DEFAULT 0,
            saturated_fat_g REAL DEFAULT 0
        )
    """)

    insert_sql = """
        INSERT OR IGNORE INTO branded_foods
        (barcode, description, brand, serving_size, serving_unit, household_serving,
         calories, protein_g, fat_g, carbs_g, fiber_g, sugar_g, sodium_mg, saturated_fat_g)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    inserted = 0
    skipped_no_desc = 0
    skipped_no_nutrients = 0

    for fdc_id, info in branded_info.items():
        description = food_descriptions.get(fdc_id, "")
        if not description:
            skipped_no_desc += 1
            continue

        nutr = nutrients.get(fdc_id, {})
        if not nutr:
            skipped_no_nutrients += 1
            continue

        cur.execute(insert_sql, (
            info["barcode"],
            description,
            info["brand"] or None,
            info["serving_size"],
            info["serving_unit"] or None,
            info["household_serving"] or None,
            nutr.get("calories", 0),
            nutr.get("protein_g", 0),
            nutr.get("fat_g", 0),
            nutr.get("carbs_g", 0),
            nutr.get("fiber_g", 0),
            nutr.get("sugar_g", 0),
            nutr.get("sodium_mg", 0),
            nutr.get("saturated_fat_g", 0),
        ))
        inserted += 1

    conn.commit()

    # Verify
    cur.execute("SELECT COUNT(*) FROM branded_foods")
    row_count = cur.fetchone()[0]

    # Sample lookups
    print(f"\nSample entries:")
    cur.execute("SELECT barcode, description, brand, calories, protein_g, serving_size, household_serving FROM branded_foods LIMIT 5")
    for row in cur.fetchall():
        print(f"  {row[0]}: {row[1]} ({row[2]}) - {row[3]} kcal, {row[4]}g protein, serving: {row[5]}g ({row[6]})")

    conn.close()

    file_size = os.path.getsize(OUTPUT)
    print(f"\nDone! {OUTPUT}")
    print(f"  Products inserted: {inserted}")
    print(f"  Skipped (no description): {skipped_no_desc}")
    print(f"  Skipped (no nutrients): {skipped_no_nutrients}")
    print(f"  Skipped (duplicate barcode): {inserted - row_count if inserted > row_count else 0}")
    print(f"  Total rows in DB: {row_count}")
    print(f"  File size: {file_size / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
