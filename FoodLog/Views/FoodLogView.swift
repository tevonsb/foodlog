import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct FoodLogView: View {
    @Binding var deepLinkAddFood: Bool

    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showAddFood = false
    @State private var todayBeverages: [BeverageEntry] = []
    @State private var fabsVisible = false
    @State private var toastMessage: String?

    // Haptics
    @State private var impactLight = UIImpactFeedbackGenerator(style: .light)
    @State private var notify = UINotificationFeedbackGenerator()

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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// Group entries by day for display
    private var groupedEntries: [(key: String, entries: [FoodEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> String in
            if calendar.isDateInToday(entry.timestamp) {
                return "Today"
            } else if calendar.isDateInYesterday(entry.timestamp) {
                return "Yesterday"
            } else {
                return Self.dayFormatter.string(from: entry.timestamp)
            }
        }
        // Sort groups: Today first, then by most recent entry
        return grouped.sorted { a, b in
            let aDate = a.value.first?.timestamp ?? .distantPast
            let bDate = b.value.first?.timestamp ?? .distantPast
            return aDate > bDate
        }.map { (key: $0.key, entries: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                mainContent

                // Floating action buttons
                fabStack

                // Toast overlay
                if let message = toastMessage {
                    toastView(message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .navigationTitle("Nutritious")
            .navigationBarTitleDisplayMode(.large)
            .glassNavigationBar()
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
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
                fabsVisible = true
            }
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

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if entries.isEmpty && todayBeverages.isEmpty {
            ContentUnavailableView(
                "Nothing logged yet",
                systemImage: "fork.knife.circle",
                description: Text("Tap + to add your first meal, or log water and coffee to get started.")
            )
        } else {
            List {
                // Today summary
                Section {
                    todaySummaryCards
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                // Beverages
                if !todayBeverages.isEmpty {
                    Section {
                        ForEach(todayBeverages) { beverage in
                            BeverageRow(entry: beverage)
                        }
                        .onDelete { indexSet in
                            Task { await deleteBeverages(at: indexSet) }
                        }
                    } header: {
                        Text("Beverages")
                    }
                }

                // Meals grouped by day
                ForEach(groupedEntries, id: \.key) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                MealRow(entry: entry)
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                await deleteGroupedEntries(group: group.entries, at: indexSet)
                            }
                        }
                    } header: {
                        Text(group.key)
                    }
                }
            }
            .refreshable {
                reloadBeverages()
                syncWidgetData()
            }
        }
    }

    // MARK: - Today summary cards

    private var todaySummaryCards: some View {
        HStack(spacing: 10) {
            SummaryCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(Int(todayNutrients.calories ?? 0))",
                label: "kcal"
            )
            SummaryCard(
                icon: "p.circle.fill",
                iconColor: .blue,
                value: "\(Int(todayNutrients.protein ?? 0))g",
                label: "protein"
            )
            SummaryCard(
                icon: "leaf.fill",
                iconColor: .green,
                value: "\(Int(todayNutrients.fiber ?? 0))g",
                label: "fiber"
            )
            SummaryCard(
                icon: "drop.fill",
                iconColor: .cyan,
                value: "\(Int(todayWaterOz))",
                label: "oz water"
            )
            SummaryCard(
                icon: "cup.and.saucer.fill",
                iconColor: .brown,
                value: "\(todayCoffeeCount)",
                label: "coffees"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - FABs

    @ViewBuilder
    private var fabStack: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                fabButtons
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        } else {
            fabButtons
                .padding(.trailing, 20)
                .padding(.bottom, 20)
        }
    }

    private var fabButtons: some View {
        VStack(spacing: 12) {
            GlassCircleButton(icon: "cup.and.saucer.fill", iconColor: .brown, size: 44, showShadow: true) {
                impactLight.impactOccurred()
                Task { await logCoffee() }
            }
            .contextMenu {
                ForEach(CoffeeVariant.allCases, id: \.displayName) { variant in
                    Button {
                        impactLight.impactOccurred()
                        Task { await logCoffeeVariant(variant) }
                    } label: {
                        Label(variant.displayName, systemImage: variant.icon)
                    }
                }
            }
            .opacity(fabsVisible ? 1 : 0)
            .offset(y: fabsVisible ? 0 : 20)

            GlassCircleButton(icon: "drop.fill", iconColor: .cyan, size: 44, showShadow: true) {
                impactLight.impactOccurred()
                Task { await logWater() }
            }
            .opacity(fabsVisible ? 1 : 0)
            .offset(y: fabsVisible ? 0 : 20)

            GlassCircleButton(icon: "plus", iconColor: .primary, size: 60, showShadow: true) {
                impactLight.impactOccurred()
                showAddFood = true
            }
            .opacity(fabsVisible ? 1 : 0)
            .offset(y: fabsVisible ? 0 : 20)
        }
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        VStack {
            toastContent(message: message)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func toastContent(message: String) -> some View {
        let base = Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

        if #available(iOS 26.0, *) {
            base
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        } else {
            base
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                toastMessage = nil
            }
        }
    }

    // MARK: - Actions

    private func reloadBeverages() {
        todayBeverages = BeverageStore.loadToday().sorted { $0.timestamp > $1.timestamp }
    }

    private func deleteGroupedEntries(group: [FoodEntry], at offsets: IndexSet) async {
        for index in offsets {
            let entry = group[index]
            if !entry.healthKitSampleUUIDs.isEmpty {
                try? await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
            }
            // Cascade-remove linked BeverageEntry
            if let beverage = todayBeverages.first(where: { $0.linkedFoodEntryID == entry.id }) {
                BeverageStore.remove(id: beverage.id)
            }
            modelContext.delete(entry)
        }
        try? modelContext.save()
        reloadBeverages()
        syncWidgetData()
    }

    private func deleteBeverages(at offsets: IndexSet) async {
        let sorted = todayBeverages
        for index in offsets {
            let beverage = sorted[index]
            if let uuid = beverage.healthKitSampleUUID {
                try? await HealthKitService.shared.deleteBeverageSample(uuid: uuid, type: beverage.type)
            }
            // Cascade-delete linked FoodEntry (and its HealthKit samples)
            if let linkedID = beverage.linkedFoodEntryID,
               let foodEntry = entries.first(where: { $0.id == linkedID }) {
                if !foodEntry.healthKitSampleUUIDs.isEmpty {
                    try? await HealthKitService.shared.deleteMeal(sampleUUIDs: foodEntry.healthKitSampleUUIDs)
                }
                modelContext.delete(foodEntry)
            }
            BeverageStore.remove(id: beverage.id)
        }
        try? modelContext.save()
        reloadBeverages()
        syncWidgetData()
    }

    private func logWater() async {
        let sampleUUID = try? await HealthKitService.shared.logWater(oz: 8)
        let entry = BeverageEntry(type: .water, amount: 8, healthKitSampleUUID: sampleUUID)
        BeverageStore.append(entry)
        reloadBeverages()
        syncWidgetData()
        notify.notificationOccurred(.success)
        showToast("8oz water logged")
    }

    private func logCoffee() async {
        let sampleUUID = try? await HealthKitService.shared.logCoffee()
        let entry = BeverageEntry(type: .coffee, amount: 1, healthKitSampleUUID: sampleUUID)
        BeverageStore.append(entry)
        reloadBeverages()
        syncWidgetData()
        notify.notificationOccurred(.success)
        showToast("Coffee logged")
    }

    private func logCoffeeVariant(_ variant: CoffeeVariant) async {
        let nutrients = variant.nutrients
        let food = variant.loggedFood
        let foodEntry = FoodEntry(
            mealDescription: variant.displayName,
            nutrients: nutrients,
            foods: [food]
        )

        let sampleUUIDs = (try? await HealthKitService.shared.saveMeal(
            nutrients: nutrients, mealID: foodEntry.id, date: foodEntry.timestamp
        )) ?? []
        foodEntry.healthKitSampleUUIDs = sampleUUIDs

        modelContext.insert(foodEntry)

        let beverage = BeverageEntry(
            type: .coffee, amount: 1,
            label: variant.displayName,
            caffeineMg: nutrients.caffeine,
            trackedViaMeal: true,
            linkedFoodEntryID: foodEntry.id
        )
        BeverageStore.append(beverage)

        reloadBeverages()
        syncWidgetData()
        notify.notificationOccurred(.success)
        showToast("\(variant.displayName) logged")
    }

    private func syncWidgetData() {
        let n = todayNutrients
        TodayNutrients(
            calories: n.calories ?? 0,
            protein: n.protein ?? 0,
            fiber: n.fiber ?? 0,
            waterOz: todayWaterOz,
            coffees: todayCoffeeCount,
            lastUpdated: .now,
            carbs: n.carbohydrates ?? 0,
            fat: n.totalFat ?? 0,
            sugar: n.sugar ?? 0,
            sodium: n.sodium ?? 0,
            cholesterol: n.cholesterol ?? 0,
            saturatedFat: n.saturatedFat ?? 0
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Summary card

private struct SummaryCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 68, height: 80)
        .cardSurface(cornerRadius: 14, background: Color(.secondarySystemGroupedBackground), strokeOpacity: 0.08, shadowOpacity: 0.02)
    }
}

// MARK: - Beverage row

private struct BeverageRow: View {
    let entry: BeverageEntry

    private var isWater: Bool { entry.type == .water }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isWater ? Color.cyan.opacity(0.12) : Color.brown.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: isWater ? "drop.fill" : "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isWater ? .cyan : .brown)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isWater ? "Water" : (entry.label ?? "Coffee"))
                    .font(.subheadline.weight(.medium))
                Text(isWater ? "\(Int(entry.amount))oz" : "\(Int(entry.caffeineMg ?? 142))mg caffeine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Meal row

struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.mealDescription)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(entry.timestamp, format: timestampFormat)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !entry.foods.isEmpty {
                Text(entry.foods.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                MacroPill(icon: "flame.fill", value: "\(Int(entry.nutrients.calories ?? 0))", unit: "kcal", color: .orange)
                MacroPill(icon: "p.circle.fill", value: "\(Int(entry.nutrients.protein ?? 0))g", unit: "P", color: .blue)
                MacroPill(icon: "leaf.fill", value: "\(Int(entry.nutrients.fiber ?? 0))g", unit: "F", color: .green)
            }
        }
        .padding(.vertical, 4)
    }

    private var timestampFormat: Date.FormatStyle {
        if Calendar.current.isDateInToday(entry.timestamp) {
            return .dateTime.hour().minute()
        } else {
            return .dateTime.month(.abbreviated).day().hour().minute()
        }
    }
}

// MARK: - Macro pill

private struct MacroPill: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .pillSurface(background: color.opacity(0.16))
    }
}

// MARK: - Coffee variant

private enum CoffeeVariant: CaseIterable {
    case black, withCream, latte

    var displayName: String {
        switch self {
        case .black: "Coffee"
        case .withCream: "Coffee with Cream"
        case .latte: "Latte"
        }
    }

    var icon: String {
        switch self {
        case .black: "cup.and.saucer.fill"
        case .withCream: "cup.and.saucer.fill"
        case .latte: "mug.fill"
        }
    }

    var nutrients: NutrientData {
        var n = NutrientData()
        switch self {
        case .black:
            // 12 fl oz brewed coffee (~355mL)
            n.calories = 4
            n.protein = 0.4
            n.caffeine = 142
        case .withCream:
            // 12 fl oz brewed coffee + 1 tbsp heavy cream
            n.calories = 56
            n.protein = 0.7
            n.totalFat = 5.4
            n.saturatedFat = 3.4
            n.carbohydrates = 0.4
            n.caffeine = 142
        case .latte:
            // 16 fl oz, double shot espresso + steamed whole milk
            n.calories = 190
            n.protein = 13
            n.totalFat = 7
            n.saturatedFat = 4.5
            n.carbohydrates = 18
            n.sugar = 17
            n.caffeine = 128
        }
        return n
    }

    var loggedFood: LoggedFood {
        let n = nutrients
        return LoggedFood(
            name: displayName,
            matchedDescription: displayName,
            grams: self == .latte ? 480 : 370,
            calories: n.calories ?? 0,
            protein: n.protein ?? 0,
            carbs: n.carbohydrates ?? 0,
            fat: n.totalFat ?? 0,
            source: "estimate"
        )
    }
}

#if DEBUG
#Preview("Food Log") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, configurations: config)
    let context = container.mainContext

    var nutrients = NutrientData()
    nutrients.calories = 620
    nutrients.protein = 38
    nutrients.carbohydrates = 64
    nutrients.totalFat = 22
    nutrients.fiber = 8
    nutrients.sugar = 10

    let foods = [
        LoggedFood(
            name: "Chicken Bowl",
            matchedDescription: "Grilled chicken, rice, salsa",
            grams: 420,
            calories: 520,
            protein: 34,
            carbs: 58,
            fat: 16,
            source: "estimate"
        ),
        LoggedFood(
            name: "Avocado",
            matchedDescription: "Half avocado",
            grams: 75,
            calories: 100,
            protein: 2,
            carbs: 6,
            fat: 9,
            source: "estimate"
        )
    ]

    let entry = FoodEntry(
        timestamp: Date().addingTimeInterval(-3600),
        mealDescription: "Lunch",
        nutrients: nutrients,
        foods: foods
    )

    context.insert(entry)

    return FoodLogView(deepLinkAddFood: .constant(false))
        .modelContainer(container)
}
#endif
