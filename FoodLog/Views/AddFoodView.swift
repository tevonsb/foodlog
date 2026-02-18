import SwiftUI
import SwiftData
import UIKit

struct AddFoodView: View {
    var onSaved: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var mealText = ""
    @State private var isLogging = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var capturedImageData: Data?

    private var canLog: Bool {
        (!mealText.isEmpty || capturedImageData != nil) && !isLogging
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(spacing: 16) {
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

                    if isLogging {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Analyzing your meal...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if capturedImageData == nil && !isLogging {
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

            // Bottom input bar (messaging style)
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
        isLogging = true
        errorMessage = nil

        do {
            let analysis: AgenticMealAnalysis
            if let imageData = capturedImageData {
                analysis = try await ClaudeService.identifyFoods(imageData: imageData)
            } else {
                analysis = try await ClaudeService.identifyFoods(description: mealText)
            }

            guard !analysis.foods.isEmpty else {
                errorMessage = "Could not identify any foods."
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
                mealDescription: mealText.isEmpty ? "Meal from photo" : mealText,
                photoData: capturedImageData,
                nutrients: totalNutrients,
                foods: loggedFoods,
                healthKitSampleUUIDs: sampleUUIDs
            )
            modelContext.insert(entry)
            try modelContext.save()

            onSaved?()
        } catch {
            errorMessage = error.localizedDescription
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

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
