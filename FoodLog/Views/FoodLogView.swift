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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Nutritious")
            .navigationBarTitleDisplayMode(.large)
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
                        Image(systemName: "gearshape.fill")
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
    }

    // MARK: - FABs

    private var fabStack: some View {
        VStack(spacing: 12) {
            Button {
                impactLight.impactOccurred()
                Task { await logCoffee() }
            } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.brown)
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(BounceButtonStyle())
            .opacity(fabsVisible ? 1 : 0)
            .offset(y: fabsVisible ? 0 : 20)

            Button {
                impactLight.impactOccurred()
                Task { await logWater() }
            } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                    Image(systemName: "drop.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.cyan)
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(BounceButtonStyle())
            .opacity(fabsVisible ? 1 : 0)
            .offset(y: fabsVisible ? 0 : 20)

            Button {
                impactLight.impactOccurred()
                showAddFood = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.gradient)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
            }
            .buttonStyle(BounceButtonStyle())
            .opacity(fabsVisible ? 1 : 0)
            .offset(y: fabsVisible ? 0 : 20)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.3)) {
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                Text(isWater ? "Water" : "Coffee")
                    .font(.subheadline.weight(.medium))
                Text(isWater ? "\(Int(entry.amount))oz" : "95mg caffeine")
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
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Bounce button style

private struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
