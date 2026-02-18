import AppIntents
import WidgetKit

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description: IntentDescription = "Log 8oz of water"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let entry = BeverageEntry(type: .water, amount: 8)
        BeverageStore.append(entry)

        syncWidgetNutrients()
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

struct LogCoffeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Coffee"
    static var description: IntentDescription = "Log one coffee (95mg caffeine)"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let entry = BeverageEntry(type: .coffee, amount: 1)
        BeverageStore.append(entry)

        syncWidgetNutrients()
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

// Shared helper to update TodayNutrients with current beverage counts.
// Only updates water/coffee fields; preserves existing meal nutrient data.
private func syncWidgetNutrients() {
    let existing = TodayNutrients.load()
    TodayNutrients(
        calories: existing.calories,
        protein: existing.protein,
        fiber: existing.fiber,
        waterOz: BeverageStore.todayWaterOz(),
        coffees: BeverageStore.todayCoffeeCount(),
        lastUpdated: .now
    ).save()
}
