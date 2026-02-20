import SwiftUI
import SwiftData
import WidgetKit

struct FoodLogView: View {
    @Binding var deepLinkAddFood: Bool

    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showAddFood = false
    @State private var todayBeverages: [BeverageEntry] = []

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var todayNutrients: NutrientData {
        NutrientData.combined(todayEntries.map(\.nutrients))
    }

    private var todayWaterOz: Double {
        todayBeverages.filter { $0.type == .water }.reduce(0) { $0 + $1.amount }
    }

    private var todayCoffeeCount: Int {
        todayBeverages.filter { $0.type == .coffee }.count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if entries.isEmpty && todayBeverages.isEmpty {
                        ContentUnavailableView(
                            "Nothing logged yet",
                            systemImage: "fork.knife.circle",
                            description: Text("Tap the + to add your first meal, or log water and coffee to get started.")
                        )
                    } else {
                        List {
                            Section("Today") {
                                HStack {
                                    SummaryItem(value: todayNutrients.calories, label: "kcal")
                                    Spacer()
                                    SummaryItem(value: todayNutrients.protein, label: "protein")
                                    Spacer()
                                    SummaryItem(value: todayNutrients.fiber, label: "fiber")
                                    Spacer()
                                    SummaryItem(value: todayWaterOz, label: "oz water")
                                    Spacer()
                                    SummaryItem(value: Double(todayCoffeeCount), label: "coffees")
                                }
                                .padding(.vertical, 4)
                            }

                            if !todayBeverages.isEmpty {
                                Section("Beverages") {
                                    ForEach(todayBeverages) { beverage in
                                        BeverageRow(entry: beverage)
                                    }
                                    .onDelete { indexSet in
                                        Task { await deleteBeverages(at: indexSet) }
                                    }
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

                // Floating action buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await logCoffee() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.title3.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.brown)
                        }
                        .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await logWater() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
                            Image(systemName: "drop.fill")
                                .font(.title3.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.cyan)
                        }
                        .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showAddFood = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
                            Image(systemName: "plus")
                                .font(.title.weight(.bold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain)
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
                AddFoodView()
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
            reloadBeverages()
            syncWidgetData()
        }
        .onChange(of: entries.count) {
            syncWidgetData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                reloadBeverages()
            }
        }
        .onChange(of: deepLinkAddFood) { _, newValue in
            if newValue {
                showAddFood = true
                deepLinkAddFood = false
            }
        }
    }

    private func reloadBeverages() {
        todayBeverages = BeverageStore.loadToday().sorted { $0.timestamp > $1.timestamp }
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

    private func deleteBeverages(at offsets: IndexSet) async {
        let sorted = todayBeverages
        for index in offsets {
            let beverage = sorted[index]
            if let uuid = beverage.healthKitSampleUUID {
                try? await HealthKitService.shared.deleteBeverageSample(uuid: uuid, type: beverage.type)
            }
            BeverageStore.remove(id: beverage.id)
        }
        reloadBeverages()
        syncWidgetData()
    }

    private func logWater() async {
        let sampleUUID = try? await HealthKitService.shared.logWater(oz: 8)
        let entry = BeverageEntry(type: .water, amount: 8, healthKitSampleUUID: sampleUUID)
        BeverageStore.append(entry)
        reloadBeverages()
        syncWidgetData()
    }

    private func logCoffee() async {
        let sampleUUID = try? await HealthKitService.shared.logCoffee()
        let entry = BeverageEntry(type: .coffee, amount: 1, healthKitSampleUUID: sampleUUID)
        BeverageStore.append(entry)
        reloadBeverages()
        syncWidgetData()
    }

    private func syncWidgetData() {
        let n = todayNutrients
        TodayNutrients(
            calories: n.calories ?? 0,
            protein: n.protein ?? 0,
            fiber: n.fiber ?? 0,
            waterOz: todayWaterOz,
            coffees: todayCoffeeCount,
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

private struct BeverageRow: View {
    let entry: BeverageEntry

    var body: some View {
        HStack {
            Image(systemName: entry.type == .water ? "drop.fill" : "cup.and.saucer.fill")
                .foregroundStyle(entry.type == .water ? .cyan : .brown)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type == .water ? "Water" : "Coffee")
                    .font(.subheadline)
                Text(entry.type == .water ? "\(Int(entry.amount))oz" : "95mg caffeine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MealRow: View {
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
                Text("\(Int(entry.nutrients.fiber ?? 0))g Fiber")
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

