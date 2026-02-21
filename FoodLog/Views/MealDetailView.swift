import SwiftUI
import SwiftData

struct MealDetailView: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isAdjustFocused: Bool
    @State private var adjustmentText = ""
    @State private var isAdjusting = false
    @State private var errorMessage: String?
    @State private var adjustmentProgress: [ProgressItem] = []
    @State private var adjustmentMessage: String?
    @State private var sendPressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader
                    mealInfo
                    foodCards
                    totalsSection
                    micronutrientsSection
                    // Bottom padding for the floating input bar
                    Color.clear.frame(height: 80)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            adjustmentBar
        }
        .navigationTitle("Meal Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
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

    // MARK: - Adjustment bar

    private var adjustmentBar: some View {
        VStack(spacing: 0) {
            // Progress & messages above the bar
            if !adjustmentProgress.isEmpty || adjustmentMessage != nil || errorMessage != nil {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(adjustmentProgress) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.caption)
                                .foregroundStyle(item.color)
                                .frame(width: 16)
                            Text(item.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let msg = adjustmentMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
            }

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Adjust meal...", text: $adjustmentText, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($isAdjustFocused)
                    .disabled(isAdjusting)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                Button {
                    sendPressed = true
                    Task { await adjustMeal() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        sendPressed = false
                    }
                } label: {
                    Group {
                        if isAdjusting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    adjustmentText.isEmpty ? Color(.systemGray4) : Color.accentColor
                                )
                        }
                    }
                    .scaleEffect(sendPressed ? 0.8 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: sendPressed)
                }
                .disabled(adjustmentText.isEmpty || isAdjusting)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Progress item model

    private struct ProgressItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    // MARK: - Adjust meal

    private func adjustMeal() async {
        isAdjusting = true
        errorMessage = nil
        adjustmentProgress = []
        adjustmentMessage = nil

        let stream = ClaudeService.adjustMeal(currentFoods: entry.foods, adjustment: adjustmentText)

        for await event in stream {
            switch event {
            case .searching(let query):
                withAnimation(.easeOut(duration: 0.25)) {
                    adjustmentProgress.append(ProgressItem(
                        icon: "magnifyingglass",
                        text: "Searching for \(query)...",
                        color: .secondary
                    ))
                }

            case .searchResult(let query, let count):
                withAnimation {
                    if let idx = adjustmentProgress.lastIndex(where: { $0.text.contains(query) }) {
                        adjustmentProgress[idx] = ProgressItem(
                            icon: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            text: count > 0 ? "Found \(count) matches for \(query)" : "No matches for \(query)",
                            color: count > 0 ? .green : .orange
                        )
                    }
                }

            case .estimating(let foodName):
                withAnimation {
                    adjustmentProgress.append(ProgressItem(
                        icon: "brain",
                        text: "Estimating nutrition for \(foodName)",
                        color: .purple
                    ))
                }

            case .thinking:
                break

            case .completed(let meals):
                guard let meal = meals.first, !meal.foods.isEmpty else {
                    errorMessage = "Could not process the adjustment."
                    break
                }

                if let msg = meal.message, !msg.isEmpty {
                    withAnimation { adjustmentMessage = msg }
                }

                let processed = MealProcessing.processAnalysis(meal, fallbackDate: entry.timestamp)

                do {
                    if !entry.healthKitSampleUUIDs.isEmpty {
                        try await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
                    }

                    let mealID = UUID()
                    let newSampleUUIDs = try await HealthKitService.shared.saveMeal(
                        nutrients: processed.nutrients,
                        mealID: mealID,
                        date: processed.mealDate
                    )

                    entry.foods = processed.foods
                    entry.nutrients = processed.nutrients
                    entry.healthKitSampleUUIDs = newSampleUUIDs
                    entry.timestamp = processed.mealDate
                    try modelContext.save()

                    adjustmentText = ""
                    isAdjustFocused = false
                } catch {
                    errorMessage = error.localizedDescription
                }

            case .failed(let error):
                errorMessage = error.localizedDescription
            }
        }

        isAdjusting = false
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
