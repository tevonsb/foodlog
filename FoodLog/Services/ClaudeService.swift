import Foundation

struct ClaudeService {
    enum ClaudeError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key set. Add your Claude API key in Settings."
            case .invalidResponse: return "Could not parse Claude's response."
            case .apiError(let message): return message
            }
        }
    }

    private static var systemPrompt: String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        You are a food identification assistant. The current date/time is \(now).

        When given a food description or photo, identify each distinct food item and estimate its portion in grams.

        Return ONLY a JSON object (no markdown, no explanation) with this structure:
        {
          "foods": [
            {
              "food_name": "chicken breast, grilled",
              "estimated_grams": 120,
              "search_terms": ["chicken breast grilled", "chicken breast", "chicken"]
            }
          ],
          "meal_time": "2025-01-15T08:00:00Z"
        }

        Rules:
        - Break composite meals into individual ingredients (e.g. a burrito -> tortilla, rice, beans, meat, cheese)
        - Estimate realistic portion sizes in grams
        - For search_terms, provide 2-4 terms from most specific to least specific. These will be used to search a USDA food database, so use common food names
        - If you see a photo, identify everything visible on the plate/in the meal
        - If the user mentions a time context (e.g. "for breakfast", "for lunch", "yesterday", "this morning"), infer a reasonable meal_time as an ISO8601 string. For example, "I had eggs for breakfast" said in the evening should produce a morning timestamp for today. "yesterday" should use yesterday's date.
        - If no time context is mentioned, omit the meal_time field entirely
        """
    }

    private static var adjustmentSystemPrompt: String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        You are a food identification assistant. The current date/time is \(now).

        The user has already logged a meal and wants to adjust it. You will receive the current foods in the meal and the user's adjustment request.

        Return ONLY a JSON object (no markdown, no explanation) with the COMPLETE updated meal:
        {
          "foods": [
            {
              "food_name": "chicken breast, grilled",
              "estimated_grams": 120,
              "search_terms": ["chicken breast grilled", "chicken breast", "chicken"]
            }
          ],
          "meal_time": "2025-01-15T08:00:00Z"
        }

        Rules:
        - Return ALL foods for the meal (not just the changed ones)
        - Apply the user's adjustment: smaller/larger portions, remove items, add items, etc.
        - Keep search_terms with 2-4 terms from most specific to least specific
        - If the adjustment implies a time change, include meal_time. Otherwise omit it.
        """
    }

    static func identifyFoods(description: String) async throws -> MealAnalysis {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "Identify the foods in this meal: \(description)"]
        ]
        return try await callClaude(messages: messages, system: systemPrompt)
    }

    static func identifyFoods(imageData: Data) async throws -> MealAnalysis {
        let base64Image = imageData.base64EncodedString()
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]],
                    ["type": "text", "text": "Identify each food item in this meal photo."]
                ]
            ]
        ]
        return try await callClaude(messages: messages, system: systemPrompt)
    }

    static func adjustMeal(currentFoods: [LoggedFood], adjustment: String) async throws -> MealAnalysis {
        let foodDescriptions = currentFoods.map { food in
            "\(food.name): \(Int(food.grams))g (\(Int(food.calories)) kcal, \(Int(food.protein))g protein, \(Int(food.carbs))g carbs, \(Int(food.fat))g fat)"
        }.joined(separator: "\n")

        let messages: [[String: Any]] = [
            ["role": "user", "content": """
            Current meal contents:
            \(foodDescriptions)

            Adjustment: \(adjustment)
            """]
        ]
        return try await callClaude(messages: messages, system: adjustmentSystemPrompt)
    }

    private static func callClaude(messages: [[String: Any]], system: String) async throws -> MealAnalysis {
        guard let apiKey = KeychainService.getAPIKey(), !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": system,
            "messages": messages
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError("API returned \(httpResponse.statusCode): \(errorBody)")
        }

        return try parseResponse(data: data)
    }

    private static func parseResponse(data: Data) throws -> MealAnalysis {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeError.invalidResponse
        }

        // Try parsing as MealAnalysis object first ({"foods": [...], "meal_time": "..."})
        if let objectRange = text.range(of: "\\{\\s*\"foods\"\\s*:\\s*\\[", options: .regularExpression) {
            // Find the full JSON object starting from the match
            let startIndex = objectRange.lowerBound
            let substring = String(text[startIndex...])
            if let jsonData = substring.data(using: .utf8) {
                // Try to find valid JSON by parsing progressively
                if let analysis = try? JSONDecoder().decode(MealAnalysis.self, from: jsonData) {
                    return analysis
                }
                // Try trimming trailing content after the object
                if let endRange = substring.range(of: "\\}\\s*$", options: .regularExpression) {
                    let trimmed = String(substring[...endRange.upperBound])
                    if let trimmedData = trimmed.data(using: .utf8),
                       let analysis = try? JSONDecoder().decode(MealAnalysis.self, from: trimmedData) {
                        return analysis
                    }
                }
            }
        }

        // Fallback: try parsing the whole text as MealAnalysis
        if let textData = text.data(using: .utf8),
           let analysis = try? JSONDecoder().decode(MealAnalysis.self, from: textData) {
            return analysis
        }

        // Fallback: parse as bare array and wrap in MealAnalysis
        let jsonString: String
        if let range = text.range(of: "\\[\\s*\\{[\\s\\S]*\\}\\s*\\]", options: .regularExpression) {
            jsonString = String(text[range])
        } else {
            jsonString = text
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeError.invalidResponse
        }

        let foods = try JSONDecoder().decode([IdentifiedFood].self, from: jsonData)
        return MealAnalysis(foods: foods, mealTime: nil)
    }
}
