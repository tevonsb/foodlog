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
    @FocusState private var isInputFocused: Bool

    // Processing state
    @State private var isLogging = false
    @State private var currentProgress: [ProgressItem] = []
    @State private var errorMessage: String?

    // Conversation state (unified)
    @State private var conversation: [ConversationItem] = []
    @State private var sessionEntries: [FoodEntry] = []
    @State private var activeEntry: FoodEntry?

    // Animation state
    @State private var emptyStateVisible = false
    @State private var sendButtonPressed = false
    @State private var cardsAppeared = false

    // Haptics
    @State private var impactLight = UIImpactFeedbackGenerator(style: .light)
    @State private var impactMedium = UIImpactFeedbackGenerator(style: .medium)
    @State private var notify = UINotificationFeedbackGenerator()

    private var canSend: Bool {
        (!mealText.isEmpty || capturedImageData != nil) && !isLogging
    }

    var body: some View {
        VStack(spacing: 0) {
            scrollContent
            if !sessionEntries.isEmpty {
                floatingMealCards
            }
            inputBar
        }
        .navigationTitle(editingEntry != nil ? "Edit Meal" : "Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .glassNavigationBar()
        .onAppear {
            isInputFocused = true
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
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(conversation) { item in
                        conversationItemView(item)
                    }

                    if isLogging {
                        liveProgressView
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    if conversation.isEmpty && !isLogging {
                        emptyState
                    }

                    Color.clear.frame(height: sessionEntries.isEmpty ? 1 : 80)
                        .id("bottom")
                }
                .padding(.top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { isInputFocused = false }
            .onChange(of: conversation.count) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom")
                }
            }
            .onChange(of: isLogging) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom")
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .symbolEffect(.pulse.byLayer)
            Text("Log your next meal")
                .font(.title3.weight(.semibold))
            Text("Snap a photo or type a quick description.\nWe'll identify foods and track your nutrition.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .opacity(emptyStateVisible ? 1 : 0)
        .offset(y: emptyStateVisible ? 0 : 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                emptyStateVisible = true
            }
        }
    }

    // MARK: - Conversation item view

    @ViewBuilder
    private func conversationItemView(_ item: ConversationItem) -> some View {
        switch item {
        case .userMessage(_, let text, let imageData):
            userMessageBubble(text: text, imageData: imageData)

        case .agentProgress(_, let items):
            agentProgressBubble(items: items)

        case .agentMessage(_, let text):
            agentMessageBubble(text: text)
        }
    }

    private func userMessageBubble(text: String?, imageData: Data?) -> some View {
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
                    .background(Color.accentColor.gradient)
                    .foregroundStyle(.white)
                    .clipShape(BubbleShape(isUser: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func agentProgressBubble(items: [ProgressItem]) -> some View {
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
        .clipShape(BubbleShape(isUser: false))
        .cardSurface(
            cornerRadius: 18,
            background: Color(.secondarySystemBackground),
            strokeOpacity: 0.08,
            shadowOpacity: 0.0
        )
        .padding(.horizontal)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func agentMessageBubble(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity),
                removal: .opacity
            ))
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
                            .contentTransition(.symbolEffect(.replace))
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        .clipShape(BubbleShape(isUser: false))
        .cardSurface(
            cornerRadius: 18,
            background: Color(.secondarySystemBackground),
            strokeOpacity: 0.08,
            shadowOpacity: 0.0
        )
        .padding(.horizontal)
    }

    // MARK: - Floating meal cards

    private var floatingMealCards: some View {
        VStack(spacing: 8) {
            ForEach(Array(sessionEntries.enumerated()), id: \.offset) { _, entry in
                floatingMealCard(for: entry)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func floatingMealCard(for entry: FoodEntry) -> some View {
        let cardContent = HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.gradient)
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.mealDescription)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(Int(entry.nutrients.calories ?? 0))", systemImage: "flame.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Label("\(Int(entry.nutrients.protein ?? 0))g", systemImage: "p.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }

            Spacer(minLength: 8)
            if editingEntry == nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardSurface(cornerRadius: 14, background: Color(.tertiarySystemBackground), strokeOpacity: 0.08, shadowOpacity: 0.03)

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
            HStack(alignment: .bottom, spacing: 10) {
                GlassCircleButton(icon: "camera.fill", iconColor: .primary, size: 40) {
                    impactLight.impactOccurred()
                    showCamera = true
                }

                TextField(activeEntry != nil ? "Edit this meal..." : "Describe your meal...", text: $mealText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .textFieldStyle(.plain)
                    .liquidGlassInputStyle(cornerRadius: 20)

                GlassCircleButton(icon: "arrow.up", iconColor: canSend ? Color.primary : .secondary, size: 40) {
                    sendButtonPressed = true
                    impactMedium.impactOccurred()
                    Task { await sendMessage() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        sendButtonPressed = false
                    }
                }
                .scaleEffect(sendButtonPressed ? 0.86 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: sendButtonPressed)
                .opacity(canSend ? 1.0 : 0.45)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

        await MainActor.run {
            mealText = ""
            capturedImageData = nil
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            conversation.append(.userMessage(id: UUID(), text: currentText.isEmpty ? nil : currentText, imageData: currentImageData))
        }

        currentProgress = []
        isLogging = true
        errorMessage = nil

        if let activeEntry {
            await adjustExistingEntry(entry: activeEntry, text: currentText)
        } else {
            await createNewEntries(text: currentText, imageData: currentImageData)
        }

        if !currentProgress.isEmpty {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                conversation.append(.agentProgress(id: UUID(), items: currentProgress))
            }
        }

        isLogging = false
        currentProgress = []
    }

    // MARK: - Barcode processing

    private func processBarcode(_ barcode: String) async {
        withAnimation {
            conversation.append(.userMessage(id: UUID(), text: "Scanned barcode: \(barcode)", imageData: nil))
        }
        currentProgress = []
        isLogging = true
        errorMessage = nil

        guard let product = BarcodeDatabase.shared.lookup(barcode: barcode) else {
            errorMessage = "Product not found in database. Try taking a photo instead."
            isLogging = false
            return
        }

        withAnimation {
            currentProgress.append(ProgressItem(
                icon: "barcode",
                text: "Found: \(product.brand ?? "") \(product.description)",
                color: .green
            ))
        }

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
            withAnimation {
                conversation.append(.agentProgress(id: UUID(), items: currentProgress))
            }
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
            withAnimation(.easeOut(duration: 0.25)) {
                handleProgressEvent(event)
            }
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
                withAnimation {
                    conversation.append(.agentMessage(id: UUID(), text: msg))
                }
            } else {
                errorMessage = "Could not identify any foods."
            }
            return
        }

        let messages = meals.compactMap(\.message).filter { !$0.isEmpty }
        if !messages.isEmpty {
            withAnimation {
                conversation.append(.agentMessage(id: UUID(), text: messages.joined(separator: " ")))
            }
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

                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    sessionEntries.append(entry)
                    activeEntry = entry
                }
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
            withAnimation(.easeOut(duration: 0.25)) {
                handleProgressEvent(event)
            }
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
            // Show Claude's message if available (e.g. clarification), otherwise generic error
            if let msg = meals.first?.message, !msg.isEmpty {
                conversation.append(.agentMessage(id: UUID(), text: msg))
            } else {
                errorMessage = "Could not process the adjustment."
            }
            return
        }

        if let msg = meal.message, !msg.isEmpty {
            withAnimation {
                conversation.append(.agentMessage(id: UUID(), text: msg))
            }
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

            if let idx = sessionEntries.firstIndex(where: { $0.id == entry.id }) {
                withAnimation {
                    sessionEntries[idx] = entry
                }
            }

            syncWidgetData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func generateMealDescription(from meal: AgenticMealResult, fallbackText: String) -> String {
        if let label = meal.mealLabel, !label.isEmpty {
            return label
        }

        let foodNames = meal.foods.prefix(3).map { $0.foodName }
        if !foodNames.isEmpty {
            let summary = foodNames.joined(separator: ", ")
            if summary.count > 45 {
                let truncated = String(summary.prefix(42)) + "..."
                return truncated
            }
            return summary
        }

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
            lastUpdated: .now,
            carbs: n.carbohydrates ?? 0,
            fat: n.totalFat ?? 0,
            sugar: n.sugar ?? 0,
            sodium: n.sodium ?? 0,
            cholesterol: n.cholesterol ?? 0,
            saturatedFat: n.saturatedFat ?? 0
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Chat bubble shape

private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailRadius: CGFloat = 6
        var path = Path()

        if isUser {
            // User bubble: rounded on all corners, slightly tighter on bottom-right
            path.addRoundedRect(
                in: rect,
                cornerRadii: .init(
                    topLeading: radius,
                    bottomLeading: radius,
                    bottomTrailing: tailRadius,
                    topTrailing: radius
                )
            )
        } else {
            // Agent bubble: rounded on all corners, slightly tighter on bottom-left
            path.addRoundedRect(
                in: rect,
                cornerRadii: .init(
                    topLeading: radius,
                    bottomLeading: tailRadius,
                    bottomTrailing: radius,
                    topTrailing: radius
                )
            )
        }
        return path
    }
}

#if DEBUG
#Preview("Add Meal") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, configurations: config)

    return NavigationStack {
        AddFoodView()
    }
    .modelContainer(container)
}
#endif
