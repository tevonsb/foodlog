import Foundation
import HealthKit

final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    private static let mealIDKey = "FoodLogMealID"

    private var allDietaryTypes: Set<HKSampleType> {
        var types = Set(NutrientData.allMappings.compactMap {
            HKQuantityType.quantityType(forIdentifier: $0.identifier)
        })
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        if let caffeine = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) {
            types.insert(caffeine)
        }
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = allDietaryTypes
        try await store.requestAuthorization(toShare: types, read: types)
    }

    func saveMeal(nutrients: NutrientData, mealID: UUID, date: Date) async throws -> [String] {
        var samples: [HKQuantitySample] = []

        for mapping in NutrientData.allMappings {
            guard let value = nutrients[keyPath: mapping.keyPath], value > 0,
                  let quantityType = HKQuantityType.quantityType(forIdentifier: mapping.identifier) else {
                continue
            }
            let quantity = HKQuantity(unit: mapping.unit, doubleValue: value)
            let sample = HKQuantitySample(
                type: quantityType,
                quantity: quantity,
                start: date,
                end: date,
                metadata: [Self.mealIDKey: mealID.uuidString]
            )
            samples.append(sample)
        }

        guard !samples.isEmpty else { return [] }

        guard let correlationType = HKCorrelationType.correlationType(forIdentifier: .food) else {
            return []
        }

        let correlation = HKCorrelation(
            type: correlationType,
            start: date,
            end: date,
            objects: Set(samples),
            metadata: [Self.mealIDKey: mealID.uuidString]
        )

        try await store.save(correlation)
        return samples.map { $0.uuid.uuidString }
    }

    func deleteMeal(sampleUUIDs: [String]) async throws {
        guard !sampleUUIDs.isEmpty else { return }
        let uuids = sampleUUIDs.compactMap { UUID(uuidString: $0) }
        let predicate = HKQuery.predicateForObjects(with: Set(uuids))

        for mapping in NutrientData.allMappings {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: mapping.identifier) else { continue }
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: results ?? []) }
                }
                store.execute(query)
            }
            if !samples.isEmpty { try await store.delete(samples) }
        }

        // Query correlations by metadata key instead of by sample UUID
        guard let correlationType = HKCorrelationType.correlationType(forIdentifier: .food) else { return }

        // Find the mealID from one of the samples' metadata
        var mealIDPredicate: NSPredicate?
        for mapping in NutrientData.allMappings {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: mapping.identifier) else { continue }
            let found = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, results, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: results ?? []) }
                }
                store.execute(query)
            }
            if let sample = found.first, let mealID = sample.metadata?[Self.mealIDKey] as? String {
                mealIDPredicate = HKQuery.predicateForObjects(withMetadataKey: Self.mealIDKey, allowedValues: [mealID])
                break
            }
        }

        let correlationPredicate = mealIDPredicate ?? predicate
        let correlations = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let query = HKSampleQuery(sampleType: correlationType, predicate: correlationPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results ?? []) }
            }
            store.execute(query)
        }
        if !correlations.isEmpty { try await store.delete(correlations) }
    }

    /// Log water intake in fluid ounces. Saves to HealthKit as mL. Returns sample UUID.
    func logWater(oz: Double) async throws -> String? {
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return nil }
        let mL = oz * 29.5735
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: mL)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: .now, end: .now)
        try await store.save(sample)
        return sample.uuid.uuidString
    }

    /// Log one coffee (~95mg caffeine) to HealthKit. Returns sample UUID.
    func logCoffee() async throws -> String? {
        guard let caffeineType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine) else { return nil }
        let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: 95)
        let sample = HKQuantitySample(type: caffeineType, quantity: quantity, start: .now, end: .now)
        try await store.save(sample)
        return sample.uuid.uuidString
    }

    /// Delete a single beverage HealthKit sample by UUID.
    func deleteBeverageSample(uuid: String, type: BeverageType) async throws {
        guard let sampleUUID = UUID(uuidString: uuid) else { return }
        let predicate = HKQuery.predicateForObjects(with: Set([sampleUUID]))
        let quantityType: HKQuantityType?
        switch type {
        case .water:
            quantityType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        case .coffee:
            quantityType = HKQuantityType.quantityType(forIdentifier: .dietaryCaffeine)
        }
        guard let sampleType = quantityType else { return }
        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results ?? []) }
            }
            store.execute(query)
        }
        if !samples.isEmpty { try await store.delete(samples) }
    }
}
