import Foundation
import HealthKit

final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    private static let mealIDKey = "FoodLogMealID"

    private var allDietaryTypes: Set<HKSampleType> {
        Set(NutrientData.allMappings.compactMap {
            HKQuantityType.quantityType(forIdentifier: $0.identifier)
        })
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
}
