import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct AddFoodView: View {
    var editingEntry: FoodEntry?

    @Environment(\.modelContext) private var modelContext

    // Input state
    @State private var mealText = ""
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    @State private var scannedBarcode: String?

    // Processing state
    @State private var isLogging = false
    @State private var currentProgress: [ProgressItem] = []
    @State private var errorMessage: String?

    // Conversation state (unified)
    @State private var conversation: [ConversationItem] = []
    @State private var sessionEntries: [FoodEntry] = []  // Only entries from THIS session
    @State private var activeEntry: FoodEntry?

    // Haptics
    @State private var impactLight = UIImpactFeedbackGenerator(style: .light)
    @State private var notify = UINotificationFeedbackGenerator()

    private var canSend: Bool {
        (!mealText.isEmpty || capturedImageData != nil) && !isLogging
    }

    private var pinnedCardHeight: CGFloat {
        sessionEntries.isEmpty ? 0 : 60
    }

    var body: some View {
        VStack(spacing: 0) {
            scrollContent
            if !sessionEntries.isEmpty {
                pinnedMealCards
            }
            inputBar
        }
        .navigationTitle(editingEntry != nil ? "Edit Meal" : "Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onImageCaptured: { imageData in
                    capturedImageData = imageData
                    Task { await sendMessage() }
                },
                onBarcodeScanned: { barcode in
                    scannedBarcode = barcode
                }
            )
        }
        .onChange(of: scannedBarcode) {
            if let barcode = scannedBarcode {
                scannedBarcode = nil
                Task { await processBarcode(barcode) }
            }
        }
        .onAppear {
            if let editingEntry, activeEntry == nil {
                activeEntry = editingEntry
                sessionEntries = [editingEntry]

                let foodSummary = editingEntry.foods.map { food in
                    "\(food.name) — \(Int(food.grams))g, \(Int(food.calories)) kcal"
                }.joined(separator: "\n")

                conversation.append(.agentMessage(
                    id: UUID(),
                    text: "\(editingEntry.mealDescription)\n\(foodSummary)"
                ))
            }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Conversation timeline (threaded messages)
                    ForEach(conversation) { item in
                        conversationItemView(item)
                    }

                    // Live progress for current interaction
                    if isLogging {
                        liveProgressView
                    }

                    // Error view
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Empty state
                    if conversation.isEmpty && !isLogging {
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

                    // Spacer so pinned cards don't overlap
                    Color.clear.frame(height: pinnedCardHeight)

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.top)
            }
            .onChange(of: conversation.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isLogging) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Conversation item view

    @ViewBuilder
    private func conversationItemView(_ item: ConversationItem) -> some View {
        switch item {
        case .userMessage(_, let text, let imageData):
            VStack(alignment: .trailing, spacing: 8) {
                if let imgData = imageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if let text, !text.isEmpty {
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

        case .agentProgress(_, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
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
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.opacity)

        case .agentMessage(_, let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .transition(.opacity)
        }
    }

    // MARK: - Live progress view

    private var liveProgressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !currentProgress.isEmpty {
                ForEach(currentProgress) { item in
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
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16)
                Text("Analyzing...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Pinned meal cards

    private var pinnedMealCards: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sessionEntries) { entry in
                        pinnedMealCard(for: entry)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func pinnedMealCard(for entry: FoodEntry) -> some View {
        let cardContent = HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mealDescription)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(Int(entry.nutrients.calories ?? 0))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.blue)
                        Text("\(Int(entry.nutrients.protein ?? 0))g")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if editingEntry == nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )

        if editingEntry == nil {
            NavigationLink {
                MealDetailView(entry: entry)
            } label: {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    // MARK: - Input bar

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

    private enum ConversationItem: Identifiable {
        case userMessage(id: UUID, text: String?, imageData: Data?)
        case agentProgress(id: UUID, items: [ProgressItem])
        case agentMessage(id: UUID, text: String)

        var id: UUID {
            switch self {
            case .userMessage(let id, _, _): return id
            case .agentProgress(let id, _): return id
            case .agentMessage(let id, _): return id
            }
        }
    }

    private struct ProgressItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    // MARK: - Send message

    private func sendMessage() async {
        let currentText = mealText
        let currentImageData = capturedImageData

        // Clear input immediately
        await MainActor.run {
            mealText = ""
            capturedImageData = nil
        }

        // Add user message to conversation
        conversation.append(.userMessage(id: UUID(), text: currentText.isEmpty ? nil : currentText, imageData: currentImageData))

        currentProgress = []
        isLogging = true
        errorMessage = nil

        if let activeEntry {
            await adjustExistingEntry(entry: activeEntry, text: currentText)
        } else {
            await createNewEntries(text: currentText, imageData: currentImageData)
        }

        // Freeze current progress into conversation
        if !currentProgress.isEmpty {
            conversation.append(.agentProgress(id: UUID(), items: currentProgress))
        }

        isLogging = false
        currentProgress = []
    }

    // MARK: - Barcode processing

    private func processBarcode(_ barcode: String) async {
        conversation.append(.userMessage(id: UUID(), text: "Scanned barcode: \(barcode)", imageData: nil))
        currentProgress = []
        isLogging = true
        errorMessage = nil

        guard let product = BarcodeDatabase.shared.lookup(barcode: barcode) else {
            errorMessage = "Product not found in database. Try taking a photo instead."
            isLogging = false
            return
        }

        currentProgress.append(ProgressItem(
            icon: "barcode",
            text: "Found: \(product.brand ?? "") \(product.description)",
            color: .green
        ))

        do {
            let analysis = try await ClaudeService.analyzeBarcodeProduct(product)
            let meals = analysis.resolvedMeals

            let description = product.brand != nil
                ? "\(product.brand!) \(product.description)"
                : product.description

            await processCompletedMeals(meals, text: description, imageData: nil)
            notify.notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            notify.notificationOccurred(.error)
        }

        if !currentProgress.isEmpty {
            conversation.append(.agentProgress(id: UUID(), items: currentProgress))
        }
        isLogging = false
        currentProgress = []
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
            currentProgress.append(ProgressItem(
                icon: "magnifyingglass",
                text: "Searching for \(query)...",
                color: .secondary
            ))
        case .searchResult(let query, let count):
            if let idx = currentProgress.lastIndex(where: { $0.text.contains(query) }) {
                currentProgress[idx] = ProgressItem(
                    icon: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: count > 0 ? "Found \(count) matches for \(query)" : "No matches for \(query)",
                    color: count > 0 ? .green : .orange
                )
            }
        case .estimating(let foodName):
            currentProgress.append(ProgressItem(
                icon: "brain",
                text: "Estimating nutrition for \(foodName)",
                color: .purple
            ))
        case .thinking, .completed, .failed:
            break
        }
    }

    // MARK: - Process completed meals

    private func processCompletedMeals(_ meals: [AgenticMealResult], text: String, imageData: Data?) async {
        guard !meals.isEmpty, meals.contains(where: { !$0.foods.isEmpty }) else {
            let msg = meals.first?.message
            if let msg, !msg.isEmpty {
                conversation.append(.agentMessage(id: UUID(), text: msg))
            } else {
                errorMessage = "Could not identify any foods."
            }
            return
        }

        let messages = meals.compactMap(\.message).filter { !$0.isEmpty }
        if !messages.isEmpty {
            conversation.append(.agentMessage(id: UUID(), text: messages.joined(separator: " ")))
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

                let description = generateMealDescription(from: meal, fallbackText: text)

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

                sessionEntries.append(entry)
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
            conversation.append(.agentMessage(id: UUID(), text: msg))
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

            // Update in sessionEntries
            if let idx = sessionEntries.firstIndex(where: { $0.id == entry.id }) {
                sessionEntries[idx] = entry
            }

            syncWidgetData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func generateMealDescription(from meal: AgenticMealResult, fallbackText: String) -> String {
        // Use meal label if provided (e.g., "Breakfast", "Lunch")
        if let label = meal.mealLabel, !label.isEmpty {
            return label
        }

        // Create a smart summary from the first 2-3 foods
        let foodNames = meal.foods.prefix(3).map { $0.foodName }
        if !foodNames.isEmpty {
            let summary = foodNames.joined(separator: ", ")
            // Truncate if too long
            if summary.count > 45 {
                let truncated = String(summary.prefix(42)) + "..."
                return truncated
            }
            return summary
        }

        // Fallback to user's input text or default
        return fallbackText.isEmpty ? "Meal" : fallbackText
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
