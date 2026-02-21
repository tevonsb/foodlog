import SwiftUI
import SwiftData

struct MealDetailView: View {
    let entry: FoodEntry

    @State private var showEditView = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

                micronutrientsSection
            }

            // Floating edit button
            Button {
                showEditView = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
                    Image(systemName: "pencil")
                        .font(.title2.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle("Meal Details")
        .navigationDestination(isPresented: $showEditView) {
            AddFoodView(editingEntry: entry)
        }
    }

    // MARK: - Micronutrients

    @ViewBuilder
    private var micronutrientsSection: some View {
        let micros = entry.nutrients.nonNilNutrients().filter {
            !["Calories", "Total Fat", "Saturated Fat", "Monounsaturated Fat",
              "Polyunsaturated Fat", "Protein", "Carbohydrates", "Fiber", "Sugar"]
                .contains($0.mapping.displayName)
        }
        Section("Micronutrients") {
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
}
