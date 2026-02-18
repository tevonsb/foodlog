import SwiftUI
import SwiftData
import PhotosUI

struct AddFoodView: View {
    var onSaved: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var mealText = ""
    @State private var isLogging = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var capturedImageData: Data?

    var body: some View {
        Form {
            if let imageData = capturedImageData, let uiImage = UIImage(data: imageData) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .onTapGesture {
                            capturedImageData = nil
                        }
                }
            }

            Section {
                TextField("Describe your meal...", text: $mealText, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                HStack(spacing: 16) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("Photos", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                Button {
                    Task { await logMeal() }
                } label: {
                    if isLogging {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Log Meal")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mealText.isEmpty && capturedImageData == nil || isLogging)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Food")
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { imageData in
                capturedImageData = imageData
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    if let image = UIImage(data: data),
                       let resized = resizeImage(image, maxDimension: 1024),
                       let jpeg = resized.jpegData(compressionQuality: 0.8) {
                        capturedImageData = jpeg
                    }
                }
            }
        }
    }

    private func logMeal() async {
        isLogging = true
        errorMessage = nil

        do {
            // 1. Analyze with Claude
            let analysis: MealAnalysis
            if let imageData = capturedImageData {
                analysis = try await ClaudeService.identifyFoods(imageData: imageData)
            } else {
                analysis = try await ClaudeService.identifyFoods(description: mealText)
            }

            // 2. Match against FNDDS
            let db = FNDDSDatabase.shared
            var matched: [MatchedFood] = []
            for food in analysis.foods {
                if let match = db.search(
                    identifiedName: food.foodName,
                    terms: food.searchTerms,
                    grams: food.estimatedGrams
                ) {
                    matched.append(match)
                }
            }

            guard !matched.isEmpty else {
                errorMessage = "Could not find matching foods in the database."
                isLogging = false
                return
            }

            // 3. Parse optional meal time
            let mealDate: Date
            if let mealTimeString = analysis.mealTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: mealTimeString) {
                    mealDate = parsed
                } else {
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    mealDate = formatter.date(from: mealTimeString) ?? Date()
                }
            } else {
                mealDate = Date()
            }

            // 4. Save to HealthKit
            let totalNutrients = NutrientData.combined(matched.map(\.nutrients))
            let mealID = UUID()
            let sampleUUIDs = try await HealthKitService.shared.saveMeal(
                nutrients: totalNutrients,
                mealID: mealID,
                date: mealDate
            )

            // 5. Save to SwiftData
            let loggedFoods = matched.map { food in
                LoggedFood(
                    name: food.identifiedName,
                    matchedDescription: food.fnddsDescription,
                    grams: food.grams,
                    calories: food.nutrients.calories ?? 0,
                    protein: food.nutrients.protein ?? 0,
                    carbs: food.nutrients.carbohydrates ?? 0,
                    fat: food.nutrients.totalFat ?? 0
                )
            }

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
