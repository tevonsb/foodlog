#!/usr/bin/env python3
"""
Downloads and processes USDA SR Legacy food database into a compact JSON file
for bundling with the FoodLog iOS app.

Output: ../FoodLog/Resources/usda_foods.json
"""

import csv
import json
import os
import sys
import urllib.request
import zipfile
from io import TextIOWrapper
from pathlib import Path

DOWNLOAD_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip"
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR / "usda_raw"
OUTPUT_DIR = SCRIPT_DIR.parent / "FoodLog" / "Resources"
OUTPUT_FILE = OUTPUT_DIR / "usda_foods.json"

# USDA nutrient IDs we care about (maps to NutrientData field names)
NUTRIENT_MAP = {
    1008: "calories",
    1004: "totalFat",
    1258: "saturatedFat",
    1292: "monounsaturatedFat",
    1293: "polyunsaturatedFat",
    1003: "protein",
    1005: "carbohydrates",
    1079: "fiber",
    2000: "sugar",
    1253: "cholesterol",
    1106: "vitaminA",
    1175: "vitaminB6",
    1178: "vitaminB12",
    1162: "vitaminC",
    1114: "vitaminD",
    1109: "vitaminE",
    1185: "vitaminK",
    1165: "thiamin",
    1166: "riboflavin",
    1167: "niacin",
    1177: "folate",
    1176: "biotin",
    1170: "pantothenicAcid",
    1087: "calcium",
    1089: "iron",
    1090: "magnesium",
    1101: "manganese",
    1091: "phosphorus",
    1092: "potassium",
    1093: "sodium",
    1095: "zinc",
    1096: "chromium",
    1098: "copper",
    1100: "iodine",
    1102: "molybdenum",
    1103: "selenium",
    1088: "chloride",
    1051: "water",
    1057: "caffeine",
}

NUTRIENT_IDS = set(NUTRIENT_MAP.keys())


def download_data():
    zip_path = DATA_DIR / "sr_legacy.zip"
    if zip_path.exists():
        print("ZIP already downloaded, skipping download.")
        return zip_path

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Downloading USDA SR Legacy data from {DOWNLOAD_URL}...")
    urllib.request.urlretrieve(DOWNLOAD_URL, zip_path)
    print(f"Downloaded to {zip_path}")
    return zip_path


def extract_data(zip_path):
    extract_dir = DATA_DIR / "extracted"
    if extract_dir.exists():
        print("Already extracted, skipping.")
        return extract_dir

    print("Extracting ZIP...")
    with zipfile.ZipFile(zip_path, 'r') as zf:
        zf.extractall(extract_dir)
    print(f"Extracted to {extract_dir}")
    return extract_dir


def find_csv(extract_dir, name):
    """Find a CSV file in the extracted directory (may be nested)."""
    for path in extract_dir.rglob(name):
        return path
    raise FileNotFoundError(f"Could not find {name} in {extract_dir}")


def load_foods(extract_dir):
    """Load food.csv -> {fdc_id: description}"""
    foods = {}
    csv_path = find_csv(extract_dir, "food.csv")
    print(f"Loading foods from {csv_path}...")
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row['fdc_id'])
            foods[fdc_id] = row['description']
    print(f"  Loaded {len(foods)} foods")
    return foods


def load_categories(extract_dir):
    """Load food_category.csv -> {id: description}"""
    categories = {}
    csv_path = find_csv(extract_dir, "food_category.csv")
    print(f"Loading categories from {csv_path}...")
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            categories[int(row['id'])] = row['description']
    print(f"  Loaded {len(categories)} categories")
    return categories


def load_food_categories(extract_dir):
    """Load food.csv to get food_category_id for each food."""
    food_cats = {}
    csv_path = find_csv(extract_dir, "food.csv")
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row['fdc_id'])
            cat_id = row.get('food_category_id', '')
            if cat_id:
                food_cats[fdc_id] = int(cat_id)
    return food_cats


def load_nutrients(extract_dir, food_ids):
    """Load food_nutrient.csv -> {fdc_id: {nutrient_field: amount}}"""
    nutrients = {}
    csv_path = find_csv(extract_dir, "food_nutrient.csv")
    print(f"Loading nutrients from {csv_path}...")
    count = 0
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row['fdc_id'])
            if fdc_id not in food_ids:
                continue
            nutrient_id = int(row['nutrient_id'])
            if nutrient_id not in NUTRIENT_IDS:
                continue
            amount_str = row.get('amount', '')
            if not amount_str:
                continue
            try:
                amount = float(amount_str)
            except ValueError:
                continue

            field_name = NUTRIENT_MAP[nutrient_id]
            if fdc_id not in nutrients:
                nutrients[fdc_id] = {}
            nutrients[fdc_id][field_name] = round(amount, 4)
            count += 1

    print(f"  Loaded {count} nutrient values for {len(nutrients)} foods")
    return nutrients


def load_portions(extract_dir, food_ids):
    """Load food_portion.csv -> {fdc_id: [{desc, grams}]}"""
    portions = {}
    csv_path = find_csv(extract_dir, "food_portion.csv")
    print(f"Loading portions from {csv_path}...")
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row['fdc_id'])
            if fdc_id not in food_ids:
                continue

            desc = row.get('modifier', '') or row.get('portion_description', '')
            gram_weight = row.get('gram_weight', '')
            if not gram_weight or not desc:
                continue
            try:
                grams = float(gram_weight)
            except ValueError:
                continue

            amount = row.get('amount', '1')
            try:
                amt = float(amount)
            except ValueError:
                amt = 1.0

            if amt != 1.0:
                desc = f"{amt} {desc}" if desc else str(amt)

            if fdc_id not in portions:
                portions[fdc_id] = []
            portions[fdc_id].append({"desc": desc.strip(), "grams": round(grams, 1)})

    print(f"  Loaded portions for {len(portions)} foods")
    return portions


def build_database(foods, categories, food_cats, nutrients, portions):
    """Build the final compact database."""
    print("Building database...")
    db = []
    for fdc_id, name in foods.items():
        if fdc_id not in nutrients:
            continue  # Skip foods with no nutrient data

        entry = {
            "id": fdc_id,
            "name": name,
        }

        cat_id = food_cats.get(fdc_id)
        if cat_id and cat_id in categories:
            entry["category"] = categories[cat_id]

        entry["nutrients"] = nutrients[fdc_id]

        if fdc_id in portions:
            entry["portions"] = portions[fdc_id]

        db.append(entry)

    # Sort by name for consistency
    db.sort(key=lambda x: x["name"].lower())
    print(f"  Built database with {len(db)} foods")
    return db


def main():
    zip_path = download_data()
    extract_dir = extract_data(zip_path)

    foods = load_foods(extract_dir)
    categories = load_categories(extract_dir)
    food_cats = load_food_categories(extract_dir)
    nutrients = load_nutrients(extract_dir, set(foods.keys()))
    portions = load_portions(extract_dir, set(foods.keys()))

    db = build_database(foods, categories, food_cats, nutrients, portions)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Writing to {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(db, f, separators=(',', ':'))

    file_size = os.path.getsize(OUTPUT_FILE)
    print(f"Done! Output: {OUTPUT_FILE} ({file_size / 1024 / 1024:.1f} MB)")
    print(f"Foods: {len(db)}")


if __name__ == '__main__':
    main()
