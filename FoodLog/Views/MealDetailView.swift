import SwiftUI
import SwiftData

struct MealDetailView: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var modelContext
    @State private var adjustmentText = ""
    @State private var isAdjusting = false
    @State private var errorMessage: String?
    @State private var adjustmentProgress: [ProgressItem] = []
    @State private var adjustmentMessage: String?

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

                // Live progress during adjustment
                if !adjustmentProgress.isEmpty {
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
                }

                // Agent message
                if let msg = adjustmentMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    // MARK: - Progress item model

    private struct ProgressItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    private func adjustMeal() async {
        isAdjusting = true
        errorMessage = nil
        adjustmentProgress = []
        adjustmentMessage = nil

        let stream = ClaudeService.adjustMeal(currentFoods: entry.foods, adjustment: adjustmentText)

        for await event in stream {
            switch event {
            case .searching(let query):
                adjustmentProgress.append(ProgressItem(
                    icon: "magnifyingglass",
                    text: "Searching for \(query)...",
                    color: .secondary
                ))

            case .searchResult(let query, let count):
                if let idx = adjustmentProgress.lastIndex(where: { $0.text.contains(query) }) {
                    adjustmentProgress[idx] = ProgressItem(
                        icon: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        text: count > 0 ? "Found \(count) matches for \(query)" : "No matches for \(query)",
                        color: count > 0 ? .green : .orange
                    )
                }

            case .estimating(let foodName):
                adjustmentProgress.append(ProgressItem(
                    icon: "brain",
                    text: "Estimating nutrition for \(foodName)",
                    color: .purple
                ))

            case .thinking:
                break

            case .completed(let meals):
                guard let meal = meals.first, !meal.foods.isEmpty else {
                    errorMessage = "Could not process the adjustment."
                    break
                }

                if let msg = meal.message, !msg.isEmpty {
                    adjustmentMessage = msg
                }

                let processed = MealProcessing.processAnalysis(meal, fallbackDate: entry.timestamp)

                do {
                    // Delete old HealthKit samples
                    if !entry.healthKitSampleUUIDs.isEmpty {
                        try await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
                    }

                    // Save new HealthKit samples
                    let mealID = UUID()
                    let newSampleUUIDs = try await HealthKitService.shared.saveMeal(
                        nutrients: processed.nutrients,
                        mealID: mealID,
                        date: processed.mealDate
                    )

                    // Update the entry in-place
                    entry.foods = processed.foods
                    entry.nutrients = processed.nutrients
                    entry.healthKitSampleUUIDs = newSampleUUIDs
                    entry.timestamp = processed.mealDate
                    try modelContext.save()

                    adjustmentText = ""
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
