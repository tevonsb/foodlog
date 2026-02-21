import SwiftUI
import SwiftData

struct MealDetailView: View {
    let entry: FoodEntry

    @State private var showEdit = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader
                    mealInfo
                    foodCards
                    totalsSection
                    micronutrientsSection
                    Color.clear.frame(height: 80)
                }
            }

            editButton
        }
        .navigationTitle("Meal Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showEdit) {
            AddFoodView(editingEntry: entry)
        }
    }

    // MARK: - Edit FAB

    private var editButton: some View {
        Button {
            showEdit = true
        } label: {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                Image(systemName: "pencil")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(DetailBounceButtonStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Hero header

    @ViewBuilder
    private var heroHeader: some View {
        if let imageData = entry.photoData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
        }
    }

    // MARK: - Meal info

    private var mealInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.mealDescription)
                .font(.title2.weight(.bold))
            Text(entry.timestamp, format: .dateTime.weekday(.wide).month(.abbreviated).day().year().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Macro summary bar

    private var macroSummaryBar: some View {
        HStack(spacing: 0) {
            MacroStat(label: "Calories", value: entry.nutrients.calories, unit: "kcal", color: .orange)
            Spacer()
            MacroStat(label: "Protein", value: entry.nutrients.protein, unit: "g", color: .blue)
            Spacer()
            MacroStat(label: "Carbs", value: entry.nutrients.carbohydrates, unit: "g", color: .purple)
            Spacer()
            MacroStat(label: "Fat", value: entry.nutrients.totalFat, unit: "g", color: .pink)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Food cards

    @ViewBuilder
    private var foodCards: some View {
        if !entry.foods.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Foods")
                    .font(.headline)
                    .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    ForEach(Array(entry.foods.enumerated()), id: \.offset) { _, food in
                        foodCard(food)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
    }

    private func foodCard(_ food: LoggedFood) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(food.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(food.grams))g")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if !food.matchedDescription.isEmpty {
                HStack(spacing: 6) {
                    let isDB = food.source == "database" || food.source == "barcode"
                    Image(systemName: isDB ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(isDB ? .green : .purple)
                    Text(food.matchedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                FoodMacroPill(value: "\(Int(food.calories))", label: "kcal", color: .orange)
                FoodMacroPill(value: "\(Int(food.protein))g", label: "P", color: .blue)
                FoodMacroPill(value: "\(Int(food.carbs))g", label: "C", color: .purple)
                FoodMacroPill(value: "\(Int(food.fat))g", label: "F", color: .pink)
                Spacer()
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Totals section

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Totals")
                .font(.headline)
                .padding(.horizontal, 20)

            // Big 4 macros
            macroSummaryBar

            // Secondary macros
            VStack(spacing: 0) {
                MacroRow(label: "Fiber", value: entry.nutrients.fiber, unit: "g")
                Divider().padding(.leading, 16)
                MacroRow(label: "Sugar", value: entry.nutrients.sugar, unit: "g")
                Divider().padding(.leading, 16)
                MacroRow(label: "Cholesterol", value: entry.nutrients.cholesterol, unit: "mg")
                Divider().padding(.leading, 16)
                MacroRow(label: "Sodium", value: entry.nutrients.sodium, unit: "mg")
            }
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
        .padding(.top, 20)
    }

    // MARK: - Micronutrients section

    private var micronutrientsSection: some View {
        let vitamins = filterMicros(category: "vitamin")
        let minerals = filterMicros(category: "mineral")
        let other = filterMicros(category: "other")

        return VStack(alignment: .leading, spacing: 10) {
            Text("Micronutrients")
                .font(.headline)
                .padding(.horizontal, 20)

            if vitamins.isEmpty && minerals.isEmpty && other.isEmpty {
                Text("No micronutrient data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                if !vitamins.isEmpty {
                    microGroup(title: "Vitamins", items: vitamins)
                }
                if !minerals.isEmpty {
                    microGroup(title: "Minerals", items: minerals)
                }
                if !other.isEmpty {
                    microGroup(title: "Other", items: other)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func microGroup(title: String, items: [(NutrientData.NutrientMapping, Double)]) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MacroRow(label: item.0.displayName, value: item.1, unit: item.0.displayUnit)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func filterMicros(category: String) -> [(NutrientData.NutrientMapping, Double)] {
        let macroNames = Set(["Calories", "Total Fat", "Saturated Fat", "Monounsaturated Fat",
                              "Polyunsaturated Fat", "Protein", "Carbohydrates", "Fiber", "Sugar",
                              "Cholesterol", "Sodium"])
        let vitaminNames = Set(["Vitamin A", "Vitamin B6", "Vitamin B12", "Vitamin C", "Vitamin D",
                                "Vitamin E", "Vitamin K", "Thiamin", "Riboflavin", "Niacin",
                                "Folate", "Biotin", "Pantothenic Acid"])
        let mineralNames = Set(["Calcium", "Iron", "Magnesium", "Manganese", "Phosphorus",
                                "Potassium", "Zinc", "Chromium", "Copper", "Iodine",
                                "Molybdenum", "Selenium", "Chloride"])

        return entry.nutrients.nonNilNutrients().compactMap { item in
            let name = item.mapping.displayName
            if macroNames.contains(name) { return nil }
            switch category {
            case "vitamin": return vitaminNames.contains(name) ? (item.mapping, item.value) : nil
            case "mineral": return mineralNames.contains(name) ? (item.mapping, item.value) : nil
            case "other":
                return !vitaminNames.contains(name) && !mineralNames.contains(name) ? (item.mapping, item.value) : nil
            default: return nil
            }
        }
    }

}

// MARK: - Macro stat (big 4)

private struct MacroStat: View {
    let label: String
    let value: Double?
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(formatValue)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }

    private var formatValue: String {
        guard let value else { return "—" }
        if unit == "kcal" { return "\(Int(value))" }
        return "\(Int(value))\(unit)"
    }
}

// MARK: - Food macro pill

private struct FoodMacroPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Bounce button style

private struct DetailBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
