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
        }
        .navigationTitle("Meal Details")
    }

    private func adjustMeal() async {
        isAdjusting = true
        errorMessage = nil

        do {
            // 1. Call Claude for adjustment
            let analysis = try await ClaudeService.adjustMeal(
                currentFoods: entry.foods,
                adjustment: adjustmentText
            )

            // 2. Match returned foods against FNDDS
            let db = FNDDSDatabase.shared
            var matched: [MatchedFood] = []
            for food in analysis.foods {
                if let match = db.search(
                    identifiedName: food.foodName,
                    terms: food.searchTerms,
                    grams: food.estimatedGrams
                ) {
                    matched.append(match)
                }
            }

            guard !matched.isEmpty else {
                errorMessage = "Could not find matching foods in the database."
                isAdjusting = false
                return
            }

            // 3. Delete old HealthKit samples
            if !entry.healthKitSampleUUIDs.isEmpty {
                try await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
            }

            // 4. Compute new nutrients and optionally update timestamp
            let newNutrients = NutrientData.combined(matched.map(\.nutrients))

            var mealDate = entry.timestamp
            if let mealTimeString = analysis.mealTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: mealTimeString) {
                    mealDate = parsed
                } else {
                    formatter.formatOptions = [.withInternetDateTime]
                    if let parsed = formatter.date(from: mealTimeString) {
                        mealDate = parsed
                    }
                }
            }

            // 5. Save new HealthKit samples
            let mealID = UUID()
            let newSampleUUIDs = try await HealthKitService.shared.saveMeal(
                nutrients: newNutrients,
                mealID: mealID,
                date: mealDate
            )

            // 6. Update SwiftData entry
            let newLoggedFoods = matched.map { food in
                LoggedFood(
                    name: food.identifiedName,
                    matchedDescription: food.fnddsDescription,
                    grams: food.grams,
                    calories: food.nutrients.calories ?? 0,
                    protein: food.nutrients.protein ?? 0,
                    carbs: food.nutrients.carbohydrates ?? 0,
                    fat: food.nutrients.totalFat ?? 0
                )
            }

            entry.foods = newLoggedFoods
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
}
