import SwiftUI
import SwiftData

@main
struct FoodLogApp: App {
    @State private var deepLinkAddFood = false

    var body: some Scene {
        WindowGroup {
            FoodLogView(
                deepLinkAddFood: $deepLinkAddFood
            )
            .task {
                try? await HealthKitService.shared.requestAuthorization()
            }
            .onOpenURL { url in
                switch url.host {
                case "add-food":
                    deepLinkAddFood = true
                default:
                    break
                }
            }
        }
        .modelContainer(for: FoodEntry.self)
    }
}
