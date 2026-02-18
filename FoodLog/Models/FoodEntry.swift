import Foundation
import SwiftData

@Model
final class FoodEntry {
    var id: UUID
    var timestamp: Date
    var mealDescription: String
    @Attribute(.externalStorage) var photoData: Data?
    var nutrientsJSON: Data
    var foodsJSON: Data
    var healthKitSampleUUIDs: [String]

    init(
        timestamp: Date = .now,
        mealDescription: String,
        photoData: Data? = nil,
        nutrients: NutrientData,
        foods: [LoggedFood] = [],
        healthKitSampleUUIDs: [String] = []
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.mealDescription = mealDescription
        self.photoData = photoData
        self.nutrientsJSON = (try? JSONEncoder().encode(nutrients)) ?? Data()
        self.foodsJSON = (try? JSONEncoder().encode(foods)) ?? Data()
        self.healthKitSampleUUIDs = healthKitSampleUUIDs
    }

    var nutrients: NutrientData {
        get {
            (try? JSONDecoder().decode(NutrientData.self, from: nutrientsJSON)) ?? NutrientData()
        }
        set {
            nutrientsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var foods: [LoggedFood] {
        get {
            (try? JSONDecoder().decode([LoggedFood].self, from: foodsJSON)) ?? []
        }
        set {
            foodsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
