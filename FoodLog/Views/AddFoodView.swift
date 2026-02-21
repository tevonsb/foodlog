import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct AddFoodView: View {
    @Environment(\.modelContext) private var modelContext

    // Input state
    @State private var mealText = ""
    @State private var showCamera = false
    @State private var capturedImageData: Data?

    // Processing state
    @State private var isLogging = false
    @State private var progressEvents: [ProgressItem] = []
    @State private var errorMessage: String?

    // Conversation state
    @State private var submittedMessages: [ChatBubble] = []
    @State private var completedEntries: [FoodEntry] = []
    @State private var activeEntry: FoodEntry?
    @State private var agentMessage: String?

    // Haptics
    @State private var impactLight = UIImpactFeedbackGenerator(style: .light)
    @State private var notify = UINotificationFeedbackGenerator()

    private var canSend: Bool {
        (!mealText.isEmpty || capturedImageData != nil) && !isLogging
    }

    var body: some View {
        VStack(spacing: 0) {
            scrollContent
            inputBar
        }
        .navigationTitle("Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { imageData in
                capturedImageData = imageData
                // Auto-submit photo immediately
                Task { await sendMessage() }
            }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    photoPreview
                    chatBubbles
                    progressSection
                    agentMessageView
                    resultCards
                    errorView
                    emptyState
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.top)
            }
            .onChange(of: progressEvents.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: completedEntries.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var photoPreview: some View {
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
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
        }
    }

    @ViewBuilder
    private var chatBubbles: some View {
        ForEach(submittedMessages) { bubble in
            VStack(alignment: .trailing, spacing: 8) {
                if let imgData = bubble.imageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if let text = bubble.text, !text.isEmpty {
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
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if !progressEvents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(progressEvents) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.caption)
                            .foregroundStyle(item.color)
                            .frame(width: 16)
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if isLogging {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16)
                        Text("Analyzing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .transition(.opacity)
        } else if isLogging {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing your meal...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var agentMessageView: some View {
        if let msg = agentMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var resultCards: some View {
        ForEach(0..<completedEntries.count, id: \.self) { index in
            resultCard(for: completedEntries[index], index: index)
        }
    }

    private func resultCard(for entry: FoodEntry, index: Int) -> some View {
        NavigationLink {
            MealDetailView(entry: entry)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if completedEntries.count > 1 {
                    Text("Meal \(index + 1)")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
                MealRow(entry: entry)
            }
            .padding(12)
            .background(
                LinearGradient(colors: [Color(.secondarySystemBackground), Color(.secondarySystemBackground).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var errorView: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if capturedImageData == nil && !isLogging && completedEntries.isEmpty && submittedMessages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                Text("Log your next meal")
                    .font(.headline)
                Text("Snap a photo or type a quick description. We'll identify foods and track your nutrition.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    impactLight.impactOccurred()
                    showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }

                TextField(activeEntry != nil ? "Edit this meal..." : "Describe your meal...", text: $mealText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.8))

                Button {
                    impactLight.impactOccurred()
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .scaleEffect(canSend ? 1.0 : 0.98)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Models

    private struct ChatBubble: Identifiable {
        let id = UUID()
        let text: String?
        let imageData: Data?
    }

    private struct ProgressItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    // MARK: - Send message (routes to create or adjust)

    private func sendMessage() async {
        let currentText = mealText
        let currentImageData = capturedImageData

        mealText = ""
        capturedImageData = nil
        submittedMessages.append(ChatBubble(text: currentText.isEmpty ? nil : currentText, imageData: currentImageData))
        progressEvents = []
        isLogging = true
        errorMessage = nil
        agentMessage = nil

        if let activeEntry {
            await adjustExistingEntry(entry: activeEntry, text: currentText)
        } else {
            await createNewEntries(text: currentText, imageData: currentImageData)
        }

        isLogging = false
    }

    // MARK: - Create new entries

    private func createNewEntries(text: String, imageData: Data?) async {
        let stream: AsyncStream<AgentEvent>
        if let imageData {
            stream = ClaudeService.identifyFoods(imageData: imageData)
        } else {
            stream = ClaudeService.identifyFoods(description: text)
        }

        for await event in stream {
            handleProgressEvent(event)
            if case .completed(let meals) = event {
                await processCompletedMeals(meals, text: text, imageData: imageData)
                notify.notificationOccurred(.success)
            }
            if case .failed(let error) = event {
                errorMessage = error.localizedDescription
                notify.notificationOccurred(.error)
            }
        }
    }

    private func handleProgressEvent(_ event: AgentEvent) {
        switch event {
        case .searching(let query):
            progressEvents.append(ProgressItem(
                icon: "magnifyingglass",
                text: "Searching for \(query)...",
                color: .secondary
            ))
        case .searchResult(let query, let count):
            if let idx = progressEvents.lastIndex(where: { $0.text.contains(query) }) {
                progressEvents[idx] = ProgressItem(
                    icon: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: count > 0 ? "Found \(count) matches for \(query)" : "No matches for \(query)",
                    color: count > 0 ? .green : .orange
                )
            }
        case .estimating(let foodName):
            progressEvents.append(ProgressItem(
                icon: "brain",
                text: "Estimating nutrition for \(foodName)",
                color: .purple
            ))
        case .thinking, .completed, .failed:
            break
        }
    }

    // MARK: - Process completed meals into FoodEntries

    private func processCompletedMeals(_ meals: [AgenticMealResult], text: String, imageData: Data?) async {
        guard !meals.isEmpty, meals.contains(where: { !$0.foods.isEmpty }) else {
            let msg = meals.first?.message
            if let msg, !msg.isEmpty {
                agentMessage = msg
            } else {
                errorMessage = "Could not identify any foods."
            }
            return
        }

        let messages = meals.compactMap(\.message).filter { !$0.isEmpty }
        if !messages.isEmpty {
            agentMessage = messages.joined(separator: " ")
        }

        for (index, meal) in meals.enumerated() {
            guard !meal.foods.isEmpty else { continue }

            let processed = MealProcessing.processAnalysis(meal, fallbackDate: Date())
            let mealID = UUID()

            do {
                let sampleUUIDs = try await HealthKitService.shared.saveMeal(
                    nutrients: processed.nutrients,
                    mealID: mealID,
                    date: processed.mealDate
                )

                let description: String
                if let label = meal.mealLabel {
                    description = label
                } else if !text.isEmpty {
                    description = text
                } else {
                    description = "Meal from photo"
                }

                let entry = FoodEntry(
                    timestamp: processed.mealDate,
                    mealDescription: description,
                    photoData: index == 0 ? imageData : nil,
                    nutrients: processed.nutrients,
                    foods: processed.foods,
                    healthKitSampleUUIDs: sampleUUIDs
                )
                modelContext.insert(entry)
                try modelContext.save()

                completedEntries.append(entry)
                activeEntry = entry
                syncWidgetData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Adjust existing entry

    private func adjustExistingEntry(entry: FoodEntry, text: String) async {
        let stream = ClaudeService.adjustMeal(currentFoods: entry.foods, adjustment: text)

        for await event in stream {
            handleProgressEvent(event)
            if case .completed(let meals) = event {
                await applyAdjustment(meals: meals, entry: entry)
                notify.notificationOccurred(.success)
            }
            if case .failed(let error) = event {
                errorMessage = error.localizedDescription
                notify.notificationOccurred(.error)
            }
        }
    }

    private func applyAdjustment(meals: [AgenticMealResult], entry: FoodEntry) async {
        guard let meal = meals.first, !meal.foods.isEmpty else {
            errorMessage = "Could not process the adjustment."
            return
        }

        if let msg = meal.message, !msg.isEmpty {
            agentMessage = msg
        }

        let processed = MealProcessing.processAnalysis(meal, fallbackDate: entry.timestamp)

        do {
            if !entry.healthKitSampleUUIDs.isEmpty {
                try await HealthKitService.shared.deleteMeal(sampleUUIDs: entry.healthKitSampleUUIDs)
            }

            let mealID = UUID()
            let newSampleUUIDs = try await HealthKitService.shared.saveMeal(
                nutrients: processed.nutrients,
                mealID: mealID,
                date: processed.mealDate
            )

            entry.foods = processed.foods
            entry.nutrients = processed.nutrients
            entry.healthKitSampleUUIDs = newSampleUUIDs
            entry.timestamp = processed.mealDate
            try modelContext.save()

            if let idx = completedEntries.firstIndex(where: { $0.id == entry.id }) {
                completedEntries[idx] = entry
            }
            syncWidgetData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

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
