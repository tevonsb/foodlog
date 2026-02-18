import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct AddFoodView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var mealText = ""
    @State private var isLogging = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    @State private var submittedText: String?
    @State private var submittedImageData: Data?
    @State private var completedEntry: FoodEntry?

    private var canLog: Bool {
        (!mealText.isEmpty || capturedImageData != nil) && !isLogging
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Photo preview (before sending)
                    if let imageData = capturedImageData, let uiImage = UIImage(data: imageData) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            Button {
                                capturedImageData = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .padding(8)
                        }
                        .padding(.horizontal)
                    }

                    // Submitted message bubble (while loading or after completion)
                    if submittedText != nil || submittedImageData != nil {
                        VStack(alignment: .trailing, spacing: 8) {
                            if let imgData = submittedImageData, let uiImage = UIImage(data: imgData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            if let text = submittedText, !text.isEmpty {
                                Text(text)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)
                    }

                    // Loading indicator
                    if isLogging {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching nutrition database...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }

                    // Result card after completion
                    if let entry = completedEntry {
                        NavigationLink {
                            MealDetailView(entry: entry)
                        } label: {
                            MealRow(entry: entry)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    // Error message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Empty state
                    if capturedImageData == nil && !isLogging && completedEntry == nil && submittedText == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.quaternary)
                            Text("Take a photo of your meal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                }
                .padding(.top)
            }

            // Bottom input bar
            Divider()
            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }

                TextField("Describe your meal...", text: $mealText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    Task { await logMeal() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(canLog ? Color.accentColor : Color(.systemGray4))
                }
                .disabled(!canLog)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .navigationTitle("Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { imageData in
                capturedImageData = imageData
            }
        }
    }

    private func logMeal() async {
        let currentText = mealText
        let currentImageData = capturedImageData

        // Clear input immediately, show as sent bubble
        mealText = ""
        capturedImageData = nil
        submittedText = currentText
        submittedImageData = currentImageData
        completedEntry = nil
        isLogging = true
        errorMessage = nil

        do {
            let analysis: AgenticMealAnalysis
            if let imageData = currentImageData {
                analysis = try await ClaudeService.identifyFoods(imageData: imageData)
            } else {
                analysis = try await ClaudeService.identifyFoods(description: currentText)
            }

            guard !analysis.foods.isEmpty else {
                errorMessage = "Could not identify any foods."
                mealText = currentText
                capturedImageData = currentImageData
                submittedText = nil
                submittedImageData = nil
                isLogging = false
                return
            }

            let mealDate = parseMealTime(analysis.mealTime) ?? Date()

            let db = FNDDSDatabase.shared
            var nutrientsList: [NutrientData] = []
            var loggedFoods: [LoggedFood] = []

            for food in analysis.foods {
                let nutrients: NutrientData
                if food.source == "database", let foodCode = food.foodCode,
                   let dbNutrients = db.getNutrients(foodCode: foodCode, grams: food.grams) {
                    nutrients = dbNutrients
                } else {
                    nutrients = makeMacroOnlyNutrients(food)
                }
                nutrientsList.append(nutrients)

                loggedFoods.append(LoggedFood(
                    name: food.foodName,
                    matchedDescription: food.matchedDescription ?? "Estimated",
                    grams: food.grams,
                    calories: food.calories,
                    protein: food.protein,
                    carbs: food.carbs,
                    fat: food.fat,
                    source: food.source
                ))
            }

            let totalNutrients = NutrientData.combined(nutrientsList)
            let mealID = UUID()
            let sampleUUIDs = try await HealthKitService.shared.saveMeal(
                nutrients: totalNutrients,
                mealID: mealID,
                date: mealDate
            )

            let entry = FoodEntry(
                timestamp: mealDate,
                mealDescription: currentText.isEmpty ? "Meal from photo" : currentText,
                photoData: currentImageData,
                nutrients: totalNutrients,
                foods: loggedFoods,
                healthKitSampleUUIDs: sampleUUIDs
            )
            modelContext.insert(entry)
            try modelContext.save()

            completedEntry = entry
            syncWidgetData()
        } catch {
            errorMessage = error.localizedDescription
            mealText = currentText
            capturedImageData = currentImageData
            submittedText = nil
            submittedImageData = nil
        }

        isLogging = false
    }

    private func makeMacroOnlyNutrients(_ food: AgenticFoodResult) -> NutrientData {
        var n = NutrientData()
        n.calories = food.calories
        n.protein = food.protein
        n.totalFat = food.fat
        n.carbohydrates = food.carbs
        n.fiber = food.fiber
        n.sugar = food.sugar
        return n
    }

    private func parseMealTime(_ mealTimeString: String?) -> Date? {
        guard let mealTimeString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: mealTimeString) { return parsed }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: mealTimeString)
    }

    private func syncWidgetData() {
        let entries = (try? modelContext.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let todayEntries = entries.filter { Calendar.current.isDateInToday($0.timestamp) }
        let n = NutrientData.combined(todayEntries.map(\.nutrients))
        TodayNutrients(
            calories: n.calories ?? 0,
            protein: n.protein ?? 0,
            fiber: n.fiber ?? 0,
            waterOz: BeverageStore.todayWaterOz(),
            coffees: BeverageStore.todayCoffeeCount(),
            lastUpdated: .now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
