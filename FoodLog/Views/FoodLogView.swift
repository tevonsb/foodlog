import SwiftUI
import SwiftData
import WidgetKit

struct FoodLogView: View {
    @Binding var deepLinkAddFood: Bool

    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false
    @State private var showAddFood = false

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var todayNutrients: NutrientData {
        NutrientData.combined(todayEntries.map(\.nutrients))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No Meals Logged",
                            systemImage: "fork.knife",
                            description: Text("Tap + to log your first meal")
                        )
                    } else {
                        List {
                            if !todayEntries.isEmpty {
                                Section("Today") {
                                    HStack {
                                        SummaryItem(value: todayNutrients.calories, label: "kcal")
                                        Spacer()
                                        SummaryItem(value: todayNutrients.protein, label: "protein")
                                        Spacer()
                                        SummaryItem(value: todayNutrients.carbohydrates, label: "carbs")
                                        Spacer()
                                        SummaryItem(value: todayNutrients.totalFat, label: "fat")
                                    }
                                    .padding(.vertical, 4)
                                }
                            }

                            Section("Meals") {
                                ForEach(entries) { entry in
                                    NavigationLink(value: entry) {
                                        MealRow(entry: entry)
                                    }
                                }
                                .onDelete { indexSet in
                                    Task {
                                        await deleteEntries(at: indexSet)
                                    }
                                }
                            }
                        }
                    }
                }

                // Floating action button
                Button {
                    showAddFood = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Nutritious AI")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FoodEntry.self) { entry in
                MealDetailView(entry: entry)
            }
            .navigationDestination(isPresented: $showAddFood) {
                AddFoodView(onSaved: {
                    showAddFood = false
                    syncWidgetData()
                })
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
        }
        .onAppear {
            syncWidgetData()
        }
        .onChange(of: deepLinkAddFood) { _, newValue in
            if newValue {
                showAddFood = true
                deepLinkAddFood = false
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) async {
        for index in offsets {
            let entry = entries[index]
            if !entry.healthKitSampleUUIDs.isEmpty {
                try? await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
            }
            modelContext.delete(entry)
        }
        try? modelContext.save()
        syncWidgetData()
    }

    private func syncWidgetData() {
        let n = todayNutrients
        TodayNutrients(
            calories: n.calories ?? 0,
            protein: n.protein ?? 0,
            carbs: n.carbohydrates ?? 0,
            fat: n.totalFat ?? 0,
            fiber: n.fiber ?? 0,
            sugar: n.sugar ?? 0,
            lastUpdated: .now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct SummaryItem: View {
    let value: Double?
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value ?? 0))")
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.mealDescription)
                    .font(.headline)
                Spacer()
                Text(entry.timestamp, format: timestampFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !entry.foods.isEmpty {
                Text(entry.foods.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text("\(Int(entry.nutrients.calories ?? 0)) kcal")
                Text("\(Int(entry.nutrients.protein ?? 0))g P")
                Text("\(Int(entry.nutrients.carbohydrates ?? 0))g C")
                Text("\(Int(entry.nutrients.totalFat ?? 0))g F")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var timestampFormat: Date.FormatStyle {
        if Calendar.current.isDateInToday(entry.timestamp) {
            return .dateTime.hour().minute()
        } else {
            return .dateTime.month(.abbreviated).day().hour().minute()
        }
    }
}
