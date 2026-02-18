import SwiftUI
import SwiftData

@main
struct FoodLogApp: App {
    var body: some Scene {
        WindowGroup {
            FoodLogView()
                .task {
                    try? await HealthKitService.shared.requestAuthorization()
                }
        }
        .modelContainer(for: FoodEntry.self)
    }
}
