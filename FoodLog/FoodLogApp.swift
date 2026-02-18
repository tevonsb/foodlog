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
                await syncPendingBeverages()
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

    private func syncPendingBeverages() async {
        for entry in BeverageStore.unsyncedEntries() {
            do {
                let uuid: String?
                switch entry.type {
                case .water:
                    uuid = try await HealthKitService.shared.logWater(oz: entry.amount)
                case .coffee:
                    uuid = try await HealthKitService.shared.logCoffee()
                }
                if let uuid {
                    BeverageStore.markSynced(id: entry.id, healthKitSampleUUID: uuid)
                }
            } catch {
                break // HealthKit unavailable, stop trying
            }
        }
    }
}
