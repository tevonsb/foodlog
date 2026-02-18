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

    // MARK: - Tool definition

    private static let searchToolDefinition: [String: Any] = [
        "name": "search_food_database",
        "description": "Search the USDA FNDDS food database. Returns top 3 matches with macros per 100g and available portion sizes. Use this to find nutrition data for specific foods.",
        "input_schema": [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query for the food database. Use common food names. The database uses descriptions like 'Chicken breast, roasted' or 'Rice, white, cooked'. Try simple terms first (e.g. 'beef meatball' not 'homemade Italian-style beef meatballs')."
                ]
            ],
            "required": ["query"]
        ] as [String: Any]
    ]

    // MARK: - System prompts

    private static var agenticSystemPrompt: String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        You are a food nutrition assistant. The current date/time is \(now).

        You have access to a USDA FNDDS food database via the search_food_database tool. Your job is to:
        1. Identify each food item in the user's meal
        2. Search the database for each food to get accurate nutrition data
        3. Evaluate whether the database matches are reasonable
        4. Return final nutrition values for each food

        ## How to use the database
        - Search for each food individually (e.g. "chicken breast", "white rice", "beef meatball")
        - The database returns results per 100g with available portion sizes
        - Database descriptions follow USDA format: "Food, preparation method" (e.g. "Chicken breast, grilled")
        - Try simple, common terms first. If results are poor, try alternative terms.
        - You can make multiple searches in a single response by calling the tool multiple times.

        ## Evaluating matches
        - CHECK that the matched food makes sense for what the user ate
        - CHECK that macros are plausible. For example:
          - Meat/poultry/fish: typically 20-30g protein per 100g
          - Cooked grains/pasta: typically 3-5g protein per 100g
          - Vegetables: typically 1-3g protein per 100g
          - Cheese: typically 20-28g protein per 100g
        - If a match looks wrong (e.g. a soup returned for "meatballs"), search again with different terms
        - If no good match exists, use your own knowledge to estimate (set source to "estimate")

        ## When to override with estimates
        - Database returned obviously wrong food (e.g. "Soup, meatball" for plain meatballs)
        - No results found after trying 2+ queries
        - Complex/mixed dishes where individual ingredients are hard to isolate
        - Restaurant or branded foods not in USDA database
        When estimating, use your nutrition knowledge to provide realistic values.

        ## Final response format
        After you have gathered all nutrition data, respond with ONLY a JSON object (no markdown, no explanation):
        {
          "foods": [
            {
              "food_name": "Beef meatballs",
              "grams": 90,
              "calories": 207,
              "protein": 16.2,
              "fat": 13.5,
              "carbs": 5.4,
              "fiber": 0.3,
              "sugar": 1.2,
              "source": "database",
              "food_code": 27111500,
              "matched_description": "Meatball, beef"
            }
          ],
          "meal_time": "2025-01-15T08:00:00Z"
        }

        Rules:
        - Break composite meals into individual ingredients
        - Estimate realistic portion sizes in grams
        - "source" must be "database" (with food_code and matched_description) or "estimate" (food_code null, matched_description null)
        - Scale the per-100g values to the actual portion grams in your final answer
        - If the user mentions a time context, include meal_time as ISO8601. Otherwise omit it.
        - Round nutrient values to 1 decimal place
        """
    }

    private static var agenticAdjustmentPrompt: String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        You are a food nutrition assistant. The current date/time is \(now).

        The user has already logged a meal and wants to adjust it. You will receive the current foods and the adjustment request.

        You have access to a USDA FNDDS food database via the search_food_database tool.

        Apply the user's adjustment (change portions, add/remove foods, etc.) and return the COMPLETE updated meal.

        For any NEW foods added, search the database to get accurate nutrition data. For existing foods where only the portion changes, you can scale the existing values.

        ## Evaluating matches
        - CHECK that the matched food makes sense
        - CHECK that macros are plausible (meat ~20-30g protein/100g, grains ~3-5g/100g, etc.)
        - If a match looks wrong, try different search terms or use your own estimate

        ## Final response format
        Return ONLY a JSON object (no markdown, no explanation):
        {
          "foods": [
            {
              "food_name": "chicken breast, grilled",
              "grams": 120,
              "calories": 198,
              "protein": 37.2,
              "fat": 4.3,
              "carbs": 0,
              "fiber": 0,
              "sugar": 0,
              "source": "database",
              "food_code": 24198210,
              "matched_description": "Chicken breast, grilled"
            }
          ],
          "meal_time": "2025-01-15T08:00:00Z"
        }

        Rules:
        - Return ALL foods for the meal (not just the changed ones)
        - "source": "database" (with food_code/matched_description) or "estimate" (nulls)
        - Scale values to actual portion grams
        - Round nutrient values to 1 decimal place
        - If the adjustment implies a time change, include meal_time. Otherwise omit it.
        """
    }

    // MARK: - Model selection

    private static let haikuModel = "claude-haiku-4-5-20251001"
    private static let sonnetModel = "claude-sonnet-4-6"

    // MARK: - Public API

    static func identifyFoods(description: String) async throws -> AgenticMealAnalysis {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "Identify the foods and their nutrition in this meal: \(description)"]
        ]
        return try await runAgenticLoop(messages: messages, system: agenticSystemPrompt, model: haikuModel)
    }

    static func identifyFoods(imageData: Data) async throws -> AgenticMealAnalysis {
        let base64Image = imageData.base64EncodedString()
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]],
                    ["type": "text", "text": "Identify each food item in this meal photo and provide nutrition data."]
                ]
            ]
        ]
        // Use Sonnet for images — better at visual food identification
        return try await runAgenticLoop(messages: messages, system: agenticSystemPrompt, model: sonnetModel)
    }

    static func adjustMeal(currentFoods: [LoggedFood], adjustment: String) async throws -> AgenticMealAnalysis {
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
        return try await runAgenticLoop(messages: messages, system: agenticAdjustmentPrompt, model: haikuModel)
    }

    // MARK: - Agentic loop

    private static func runAgenticLoop(messages: [[String: Any]], system: String, model: String) async throws -> AgenticMealAnalysis {
        var conversationMessages = messages
        let maxIterations = 4

        for iteration in 0..<maxIterations {
            let (contentBlocks, stopReason) = try await callClaudeAPI(
                messages: conversationMessages,
                system: system,
                tools: [searchToolDefinition],
                model: model
            )

            print("ClaudeService: iteration=\(iteration) stopReason=\(stopReason) blocks=\(contentBlocks.count)")

            if stopReason == "tool_use" {
                var assistantContent: [[String: Any]] = []
                var toolResults: [[String: Any]] = []

                for block in contentBlocks {
                    if let type = block["type"] as? String {
                        if type == "text", let text = block["text"] as? String {
                            assistantContent.append(["type": "text", "text": text])
                        } else if type == "tool_use",
                                  let id = block["id"] as? String,
                                  let name = block["name"] as? String,
                                  let input = block["input"] as? [String: Any] {
                            assistantContent.append([
                                "type": "tool_use",
                                "id": id,
                                "name": name,
                                "input": input
                            ])
                            let result = executeToolCall(name: name, input: input)
                            toolResults.append([
                                "type": "tool_result",
                                "tool_use_id": id,
                                "content": result
                            ])
                        }
                    }
                }

                conversationMessages.append(["role": "assistant", "content": assistantContent])
                conversationMessages.append(["role": "user", "content": toolResults])
            } else {
                // end_turn or max_tokens — extract whatever text we have
                let textContent = contentBlocks
                    .compactMap { $0["text"] as? String }
                    .joined()

                if stopReason == "max_tokens" {
                    print("ClaudeService: WARNING max_tokens hit, text may be truncated (\(textContent.count) chars)")
                }

                if textContent.isEmpty {
                    print("ClaudeService: empty text content from API")
                    throw ClaudeError.apiError("Claude returned an empty response. Please try again.")
                }

                return try parseAgenticResponse(text: textContent)
            }
        }

        throw ClaudeError.apiError("Analysis took too many steps. Please try a simpler description.")
    }

    // MARK: - Tool execution

    private static func executeToolCall(name: String, input: [String: Any]) -> String {
        guard name == "search_food_database",
              let query = input["query"] as? String else {
            return "{\"error\": \"Unknown tool\"}"
        }

        let results = FNDDSDatabase.shared.searchTopN(query: query, limit: 5)

        if results.isEmpty {
            return "{\"results\": [], \"message\": \"No matches found for '\(query)'. Try different search terms.\"}"
        }

        let jsonResults = results.map { r -> [String: Any] in
            var entry: [String: Any] = [
                "food_code": r.foodCode,
                "description": r.description,
                "per_100g": [
                    "calories": r.caloriesPer100g,
                    "protein_g": r.proteinPer100g,
                    "fat_g": r.fatPer100g,
                    "carbs_g": r.carbsPer100g,
                    "fiber_g": r.fiberPer100g,
                    "sugar_g": r.sugarPer100g
                ] as [String: Any]
            ]
            if !r.portions.isEmpty {
                entry["portions"] = r.portions.map { p in
                    ["description": p.description, "grams": p.grams] as [String: Any]
                }
            }
            return entry
        }

        let responseDict: [String: Any] = ["results": jsonResults]
        if let data = try? JSONSerialization.data(withJSONObject: responseDict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"error\": \"Failed to serialize results\"}"
    }

    // MARK: - API call

    private static func callClaudeAPI(
        messages: [[String: Any]],
        system: String,
        tools: [[String: Any]],
        model: String
    ) async throws -> (contentBlocks: [[String: Any]], stopReason: String) {
        guard let apiKey = KeychainService.getAPIKey(), !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": messages
        ]
        if !tools.isEmpty {
            body["tools"] = tools
        }

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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let stopReason = json["stop_reason"] as? String else {
            throw ClaudeError.invalidResponse
        }

        return (content, stopReason)
    }

    // MARK: - Response parsing

    private static func parseAgenticResponse(text: String) throws -> AgenticMealAnalysis {
        // Strip markdown code fences if present
        var cleaned = text
        if let fenceRange = cleaned.range(of: "```(?:json)?\\s*", options: .regularExpression) {
            cleaned = String(cleaned[fenceRange.upperBound...])
            if let endFence = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<endFence.lowerBound])
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try balanced-brace extraction from the cleaned text
        if let objectRange = cleaned.range(of: "\\{\\s*\"foods\"\\s*:\\s*\\[", options: .regularExpression) {
            let substring = String(cleaned[objectRange.lowerBound...])
            if let extracted = extractJSON(from: substring),
               let data = extracted.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(AgenticMealAnalysis.self, from: data)
                } catch {
                    print("ClaudeService: JSON decode error: \(error)")
                    print("ClaudeService: Extracted JSON (\(extracted.count) chars): \(extracted.prefix(800))")
                }
            } else {
                // extractJSON failed — JSON may be truncated. Try to repair by closing brackets.
                print("ClaudeService: balanced extraction failed, attempting truncation repair")
                if let repaired = repairTruncatedJSON(substring),
                   let data = repaired.data(using: .utf8),
                   let analysis = try? JSONDecoder().decode(AgenticMealAnalysis.self, from: data) {
                    print("ClaudeService: truncation repair succeeded")
                    return analysis
                }
            }
        }

        // Fallback: try the entire cleaned text
        if let textData = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(AgenticMealAnalysis.self, from: textData)
            } catch {
                print("ClaudeService: Fallback decode error: \(error)")
            }
        }

        print("ClaudeService: Could not parse response text (\(text.count) chars): \(text.prefix(800))")
        throw ClaudeError.apiError("Could not parse the nutrition response. Please try again.")
    }

    /// Attempt to repair truncated JSON by finding the last complete food object
    private static func repairTruncatedJSON(_ text: String) -> String? {
        // Find the last complete "}" that could end a food object inside the foods array
        // Strategy: find "}," or "}" patterns that end a food object, then close the array and outer object
        guard let arrayStart = text.range(of: "[", options: .literal) else { return nil }

        let afterArray = String(text[arrayStart.lowerBound...])
        var lastGoodEnd: String.Index?
        var depth = 0
        var inString = false
        var escape = false
        var objectCount = 0

        for i in afterArray.indices {
            let c = afterArray[i]
            if escape { escape = false; continue }
            if c == "\\" && inString { escape = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if inString { continue }

            if c == "[" || c == "{" { depth += 1 }
            if c == "]" || c == "}" {
                depth -= 1
                if depth == 1 { // Just closed a food object (depth 1 = inside the array)
                    objectCount += 1
                    lastGoodEnd = afterArray.index(after: i)
                }
                if depth == 0 { return nil } // Fully balanced — shouldn't need repair
            }
        }

        guard objectCount > 0, let end = lastGoodEnd else { return nil }
        let partial = String(text[text.startIndex..<text.index(text.startIndex, offsetBy: afterArray.distance(from: afterArray.startIndex, to: end))])
        return partial + "]}"
    }

    /// Extract a balanced JSON object from a string starting with '{'
    private static func extractJSON(from text: String) -> String? {
        var depth = 0
        var inString = false
        var escape = false
        var endIndex: String.Index?

        for i in text.indices {
            let c = text[i]
            if escape {
                escape = false
                continue
            }
            if c == "\\" && inString {
                escape = true
                continue
            }
            if c == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            if c == "{" || c == "[" { depth += 1 }
            if c == "}" || c == "]" { depth -= 1 }
            if depth == 0 {
                endIndex = text.index(after: i)
                break
            }
        }

        guard let end = endIndex else { return nil }
        return String(text[text.startIndex..<end])
    }
}
