import SwiftUI
import SwiftData

struct MealDetailView: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var modelContext
    @State private var adjustmentText = ""
    @State private var isAdjusting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let imageData = entry.photoData, let uiImage = UIImage(data: imageData) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.mealDescription)
                        .font(.headline)
                    Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Adjust Meal") {
                HStack {
                    TextField("e.g. portion was smaller...", text: $adjustmentText, axis: .vertical)
                        .lineLimit(1...3)
                        .disabled(isAdjusting)
                    Button {
                        Task { await adjustMeal() }
                    } label: {
                        if isAdjusting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(adjustmentText.isEmpty || isAdjusting)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !entry.foods.isEmpty {
                Section("Foods") {
                    ForEach(Array(entry.foods.enumerated()), id: \.offset) { _, food in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                                .font(.headline)
                            Text(food.matchedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("\(Int(food.grams))g")
                                Spacer()
                                Text("\(Int(food.calories)) kcal")
                                Text("\(Int(food.protein))g P")
                                Text("\(Int(food.carbs))g C")
                                Text("\(Int(food.fat))g F")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Totals") {
                MacroRow(label: "Calories", value: entry.nutrients.calories, unit: "kcal")
                MacroRow(label: "Protein", value: entry.nutrients.protein, unit: "g")
                MacroRow(label: "Carbs", value: entry.nutrients.carbohydrates, unit: "g")
                MacroRow(label: "Fat", value: entry.nutrients.totalFat, unit: "g")
                MacroRow(label: "Fiber", value: entry.nutrients.fiber, unit: "g")
                MacroRow(label: "Sugar", value: entry.nutrients.sugar, unit: "g")
            }

            Section("Micronutrients") {
                let micros = entry.nutrients.nonNilNutrients().filter {
                    !["Calories", "Total Fat", "Saturated Fat", "Monounsaturated Fat",
                      "Polyunsaturated Fat", "Protein", "Carbohydrates", "Fiber", "Sugar"]
                        .contains($0.mapping.displayName)
                }
                if micros.isEmpty {
                    Text("No micronutrient data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(micros.enumerated()), id: \.offset) { _, item in
                        MacroRow(label: item.mapping.displayName, value: item.value, unit: item.mapping.displayUnit)
                    }
                }
            }

        }
        .navigationTitle("Meal Details")
    }

    private func adjustMeal() async {
        isAdjusting = true
        errorMessage = nil

        do {
            let analysis = try await ClaudeService.adjustMeal(
                currentFoods: entry.foods,
                adjustment: adjustmentText
            )

            guard !analysis.foods.isEmpty else {
                errorMessage = "Could not process the adjustment."
                isAdjusting = false
                return
            }

            // Delete old HealthKit samples
            if !entry.healthKitSampleUUIDs.isEmpty {
                try await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
            }

            let db = FNDDSDatabase.shared
            var nutrientsList: [NutrientData] = []
            var loggedFoods: [LoggedFood] = []

            for food in analysis.foods {
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

            let newNutrients = NutrientData.combined(nutrientsList)
            var mealDate = entry.timestamp
            if let mealTimeString = analysis.mealTime {
                mealDate = parseMealTime(mealTimeString) ?? entry.timestamp
            }

            let mealID = UUID()
            let newSampleUUIDs = try await HealthKitService.shared.saveMeal(
                nutrients: newNutrients,
                mealID: mealID,
                date: mealDate
            )

            entry.foods = loggedFoods
            entry.nutrients = newNutrients
            entry.healthKitSampleUUIDs = newSampleUUIDs
            entry.timestamp = mealDate
            try modelContext.save()

            adjustmentText = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isAdjusting = false
    }

    private func makeMacroOnlyNutrients(_ food: AgenticFoodResult) -> NutrientData {
        var n = NutrientData()
        n.calories = food.calories
        n.protein = food.protein
        n.totalFat = food.fat
        n.carbohydrates = food.carbs
        n.fiber = food.fiber
        n.sugar = food.sugar
        return n
    }

    private func parseMealTime(_ mealTimeString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: mealTimeString) { return parsed }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: mealTimeString)
    }
}
