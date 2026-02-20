import Foundation

enum FoodProvider: String, CaseIterable, Identifiable {
    case onDevice = "on_device"
    case claude = "claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: return "On-Device (Apple)"
        case .claude: return "Claude (Cloud)"
        }
    }

    var subtitle: String {
        switch self {
        case .onDevice: return "Private, offline, no API costs"
        case .claude: return "More accurate, requires API key"
        }
    }
}

enum FoodIdentificationProvider {
    private static let providerKey = "food_identification_provider"

    static var current: FoodProvider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey),
                  let provider = FoodProvider(rawValue: raw) else {
                return .claude // default
            }
            return provider
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerKey)
        }
    }

    /// Whether the on-device provider is available on this device.
    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return true
        }
        #endif
        return false
    }

    /// The effective provider — falls back to Claude if on-device isn't available.
    static var effective: FoodProvider {
        if current == .onDevice && !onDeviceAvailable {
            return .claude
        }
        return current
    }

    // MARK: - Routing

    static func identifyFoods(description: String) async throws -> AgenticMealAnalysis {
        switch effective {
        case .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                return try await OnDeviceLLMService.identifyFoods(description: description)
            }
            #endif
            return try await ClaudeService.identifyFoods(description: description)
        case .claude:
            return try await ClaudeService.identifyFoods(description: description)
        }
    }

    static func identifyFoods(imageData: Data) async throws -> AgenticMealAnalysis {
        // Images always go through Claude — on-device model is text-only
        return try await ClaudeService.identifyFoods(imageData: imageData)
    }

    static func adjustMeal(currentFoods: [LoggedFood], adjustment: String) async throws -> AgenticMealAnalysis {
        switch effective {
        case .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                return try await OnDeviceLLMService.adjustMeal(currentFoods: currentFoods, adjustment: adjustment)
            }
            #endif
            return try await ClaudeService.adjustMeal(currentFoods: currentFoods, adjustment: adjustment)
        case .claude:
            return try await ClaudeService.adjustMeal(currentFoods: currentFoods, adjustment: adjustment)
        }
    }
}
