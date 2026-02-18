import SwiftUI
import SwiftData

@main
struct FoodLogApp: App {
    @State private var deepLinkAddFood = false

    var body: some Scene {
        WindowGroup {
            FoodLogView(deepLinkAddFood: $deepLinkAddFood)
                .task {
                    try? await HealthKitService.shared.requestAuthorization()
                }
                .onOpenURL { url in
                    if url.host == "add-food" {
                        deepLinkAddFood = true
                    }
                }
        }
        .modelContainer(for: FoodEntry.self)
    }
}
