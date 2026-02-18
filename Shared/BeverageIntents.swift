import AppIntents
import HealthKit
import WidgetKit

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description: IntentDescription = "Log 8oz of water"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let store = HKHealthStore()
        var sampleUUID: String?

        if HKHealthStore.isHealthDataAvailable(),
           let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            let mL = 8.0 * 29.5735
            let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: mL)
            let sample = HKQuantitySample(type: waterType, quantity: quantity, start: .now, end: .now)
            try? await store.save(sample)
            sampleUUID = sample.uuid.uuidString
        }

        let entry = BeverageEntry(type: .water, amount: 8, healthKitSampleUUID: sampleUUID)
        BeverageStore.append(entry)

        // Update shared widget data
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
        let store = HKHealthStore()
        var sampleUUID: String?

        if HKHealthStore.isHealthDataAvailable(),
           let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) {
            let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: 95)
            let sample = HKQuantitySample(type: caffeineType, quantity: quantity, start: .now, end: .now)
            try? await store.save(sample)
            sampleUUID = sample.uuid.uuidString
        }

        let entry = BeverageEntry(type: .coffee, amount: 1, healthKitSampleUUID: sampleUUID)
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
