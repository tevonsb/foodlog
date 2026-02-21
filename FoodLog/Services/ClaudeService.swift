import Foundation

// MARK: - Agent Events

enum AgentEvent: Sendable {
    case searching(query: String)
    case searchResult(query: String, matchCount: Int)
    case estimating(foodName: String)
    case thinking(text: String)
    case completed([AgenticMealResult])
    case failed(Error)
}

// MARK: - Service

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
        "description": "Search the USDA FNDDS food database. Returns top 5 matches with macros per 100g and available portion sizes. Use this to find nutrition data for specific foods.",
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

        ## CRITICAL RULE: ALWAYS provide results
        You must ALWAYS provide nutrition data for every food item the user mentions. If the database \
        has no good match after 2+ searches, you MUST estimate using your nutrition knowledge. Set \
        source to "estimate" with food_code and matched_description as null. Every identifiable food \
        MUST appear in your response. Never refuse or return an empty foods array for identifiable food.

        If the user's input contains no identifiable food (e.g. "hello" or "how are you"), return:
        {"foods": [], "message": "I didn't find any food items to log. Try describing what you ate or take a photo of your meal."}

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
        - If no good match exists, ESTIMATE using your own knowledge (set source to "estimate")

        ## When to override with estimates
        - Database returned obviously wrong food (e.g. "Soup, meatball" for plain meatballs)
        - No results found after trying 2+ queries
        - Complex/mixed dishes where individual ingredients are hard to isolate
        - Restaurant or branded foods not in USDA database
        When estimating, use your nutrition knowledge to provide realistic values.

        ## Multi-meal support
        If the user describes multiple DISTINCT meals or eating occasions (e.g. "I had oatmeal for \
        breakfast and a burger for lunch"), return them as separate meals:
        {
          "meals": [
            {
              "meal_label": "Breakfast",
              "meal_time": "2025-01-15T08:00:00Z",
              "foods": [...]
            },
            {
              "meal_label": "Lunch",
              "meal_time": "2025-01-15T12:30:00Z",
              "foods": [...]
            }
          ]
        }

        For a single meal or when the user doesn't indicate separate eating occasions, use the flat format:
        {
          "foods": [...],
          "meal_time": "2025-01-15T08:00:00Z"
        }

        ## Communication
        If you need to tell the user something (e.g. you estimated a food, or something was ambiguous), \
        include a "message" field in your response:
        {"foods": [...], "message": "I estimated the nutrition for your homemade sauce since it wasn't in the database."}

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

        The user has already logged a meal and is providing follow-up information. This could be:
        - A correction ("actually it was brown rice, not white")
        - An addition ("I also had a glass of orange juice")
        - A removal ("remove the bread")
        - A portion adjustment ("the chicken was more like 200g")
        - General feedback ("that looks about right" — return the meal unchanged)

        You will receive the current foods and the user's message. Apply their changes and return the \
        COMPLETE updated meal.

        You have access to a USDA FNDDS food database via the search_food_database tool.

        For any NEW foods added, search the database to get accurate nutrition data. For existing foods \
        where only the portion changes, scale the existing values. If you can't find a new food in the \
        database after trying, estimate it.

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
        - If you want to communicate something to the user, include a "message" field.
        """
    }

    // MARK: - Barcode system prompt

    private static var barcodeSystemPrompt: String {
        """
        You are a food nutrition assistant. A user scanned a barcode on a packaged food product. \
        Your job is to determine the appropriate portion to log.

        ## Portion rules
        - **Single-serve products** (individual bar, single can/bottle, small bag, single packet, \
        cup of yogurt, individual frozen meal): log the ENTIRE package as one serving.
        - **Multi-serve products** (large bag, family-size box, 2-liter bottle, multi-pack, \
        large container): log ONE standard serving as listed on the label.
        - Use the household_serving, product name, and serving size to make this determination.
        - If the household_serving says something like "1 bar", "1 packet", "1 can", "1 bottle", \
        "1 container" — it's single-serve, log the whole thing.
        - If the household_serving says "about 15 chips", "1/2 cup", "2 tbsp", "1 cup" — it's \
        multi-serve, log one serving.

        ## Response format
        Return ONLY a JSON object (no markdown, no explanation):
        {
          "foods": [
            {
              "food_name": "<brand> <product name>",
              "grams": <serving grams>,
              "calories": <number>,
              "protein": <number>,
              "fat": <number>,
              "carbs": <number>,
              "fiber": <number>,
              "sugar": <number>,
              "source": "barcode",
              "food_code": null,
              "matched_description": "<brand> <product name>"
            }
          ]
        }

        Rules:
        - Round nutrient values to 1 decimal place
        - Use the nutrition values provided (they are per serving from the label)
        - For grams: use the serving_size if available, otherwise estimate from household_serving
        """
    }

    // MARK: - Model selection

    private static let haikuModel = "claude-haiku-4-5-20251001"
    private static let sonnetModel = "claude-sonnet-4-6"

    // MARK: - Public API (AsyncStream)

    static func identifyFoods(description: String) -> AsyncStream<AgentEvent> {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "Identify the foods and their nutrition in this meal: \(description)"]
        ]
        return makeStream(messages: messages, system: agenticSystemPrompt, model: haikuModel)
    }

    static func identifyFoods(imageData: Data) -> AsyncStream<AgentEvent> {
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
        return makeStream(messages: messages, system: agenticSystemPrompt, model: sonnetModel)
    }

    static func analyzeBarcodeProduct(_ product: BarcodeSearchResult) async throws -> AgenticMealAnalysis {
        let servingSizeStr = product.servingSize.map { "\($0)" } ?? "unknown"
        let messages: [[String: Any]] = [
            ["role": "user", "content": """
            Product: \(product.description)
            Brand: \(product.brand ?? "Unknown")
            Barcode: \(product.barcode)
            Label serving size: \(servingSizeStr) \(product.servingUnit ?? "g")
            Household serving: \(product.householdServing ?? "not specified")
            Nutrition per serving: \(product.calories) kcal, \(product.protein)g protein, \(product.fat)g fat, \(product.carbs)g carbs, \(product.fiber)g fiber, \(product.sugar)g sugar

            Determine the appropriate portion and return the nutrition data.
            """]
        ]
        // No tools needed — single call, no agentic loop
        return try await runSingleCall(messages: messages, system: barcodeSystemPrompt, model: haikuModel)
    }

    static func adjustMeal(currentFoods: [LoggedFood], adjustment: String) -> AsyncStream<AgentEvent> {
        let foodDescriptions = currentFoods.map { food in
            "\(food.name): \(Int(food.grams))g (\(Int(food.calories)) kcal, \(Int(food.protein))g protein, \(Int(food.carbs))g carbs, \(Int(food.fat))g fat) [source: \(food.source ?? "unknown")]"
        }.joined(separator: "\n")

        let messages: [[String: Any]] = [
            ["role": "user", "content": """
            Current meal contents:
            \(foodDescriptions)

            User says: \(adjustment)
            """]
        ]
        return makeStream(messages: messages, system: agenticAdjustmentPrompt, model: haikuModel)
    }

    // MARK: - Stream builder

    private static func makeStream(messages: [[String: Any]], system: String, model: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task {
                await runAgenticLoop(messages: messages, system: system, model: model, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Single call (no tool use)

    private static func runSingleCall(messages: [[String: Any]], system: String, model: String) async throws -> AgenticMealAnalysis {
        let (contentBlocks, _) = try await callClaudeAPIWithRetry(
            messages: messages,
            system: system,
            tools: [],
            model: model
        )

        let textContent = contentBlocks
            .compactMap { $0["text"] as? String }
            .joined()

        guard !textContent.isEmpty else {
            throw ClaudeError.apiError("Claude returned an empty response. Please try again.")
        }

        return try parseAgenticResponse(text: textContent)
    }

    // MARK: - Agentic loop

    private static func runAgenticLoop(
        messages: [[String: Any]],
        system: String,
        model: String,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        var conversationMessages = messages
        let maxIterations = 4

        for iteration in 0..<maxIterations {
            let result: (contentBlocks: [[String: Any]], stopReason: String)
            do {
                result = try await callClaudeAPIWithRetry(
                    messages: conversationMessages,
                    system: system,
                    tools: [searchToolDefinition],
                    model: model
                )
            } catch {
                continuation.yield(.failed(error))
                return
            }

            let (contentBlocks, stopReason) = result
            print("ClaudeService: iteration=\(iteration) stopReason=\(stopReason) blocks=\(contentBlocks.count)")

            if stopReason == "tool_use" {
                var assistantContent: [[String: Any]] = []
                var toolResults: [[String: Any]] = []

                for block in contentBlocks {
                    guard let type = block["type"] as? String else { continue }

                    if type == "text", let text = block["text"] as? String {
                        assistantContent.append(["type": "text", "text": text])
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            continuation.yield(.thinking(text: text))
                        }
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

                        let query = input["query"] as? String ?? ""
                        continuation.yield(.searching(query: query))

                        let (resultString, matchCount) = executeToolCall(name: name, input: input)
                        continuation.yield(.searchResult(query: query, matchCount: matchCount))

                        toolResults.append([
                            "type": "tool_result",
                            "tool_use_id": id,
                            "content": resultString
                        ])
                    }
                }

                conversationMessages.append(["role": "assistant", "content": assistantContent])
                conversationMessages.append(["role": "user", "content": toolResults])
            } else {
                // end_turn or max_tokens — extract text
                let textContent = contentBlocks
                    .compactMap { $0["text"] as? String }
                    .joined()

                if stopReason == "max_tokens" {
                    print("ClaudeService: WARNING max_tokens hit, text may be truncated (\(textContent.count) chars)")
                }

                if textContent.isEmpty {
                    print("ClaudeService: empty text content from API")
                    continuation.yield(.failed(ClaudeError.apiError("Claude returned an empty response. Please try again.")))
                    return
                }

                do {
                    let analysis = try parseAgenticResponse(text: textContent)
                    let meals = analysis.resolvedMeals

                    // Emit estimating events for foods that ended up as estimates
                    for meal in meals {
                        for food in meal.foods where food.source == "estimate" {
                            continuation.yield(.estimating(foodName: food.foodName))
                        }
                    }

                    continuation.yield(.completed(meals))
                } catch {
                    continuation.yield(.failed(error))
                }
                return
            }
        }

        // Max iterations reached — try to extract partial result from last response
        continuation.yield(.failed(ClaudeError.apiError("Analysis took too many steps. Please try a simpler description.")))
    }

    // MARK: - Tool execution

    private static func executeToolCall(name: String, input: [String: Any]) -> (result: String, matchCount: Int) {
        guard name == "search_food_database",
              let query = input["query"] as? String else {
            return ("{\"error\": \"Unknown tool\"}", 0)
        }

        let results = FNDDSDatabase.shared.searchTopN(query: query, limit: 5)

        if results.isEmpty {
            return ("{\"results\": [], \"message\": \"No matches found for '\(query)'. Try different search terms or use your knowledge to estimate.\"}", 0)
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
            return (str, results.count)
        }
        return ("{\"error\": \"Failed to serialize results\"}", 0)
    }

    // MARK: - API call with retry

    private static func callClaudeAPIWithRetry(
        messages: [[String: Any]],
        system: String,
        tools: [[String: Any]],
        model: String,
        maxRetries: Int = 1
    ) async throws -> (contentBlocks: [[String: Any]], stopReason: String) {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await callClaudeAPI(messages: messages, system: system, tools: tools, model: model)
            } catch let error as ClaudeError {
                lastError = error
                switch error {
                case .noAPIKey:
                    throw error // Don't retry missing API key
                case .apiError(let msg) where msg.contains("429") || msg.contains("529") || msg.contains("500") || msg.contains("502") || msg.contains("503"):
                    if attempt < maxRetries {
                        print("ClaudeService: retrying after transient error (attempt \(attempt + 1))")
                        try await Task.sleep(for: .seconds(attempt == 0 ? 2 : 3))
                        continue
                    }
                default:
                    if attempt < maxRetries {
                        print("ClaudeService: retrying after error (attempt \(attempt + 1))")
                        try await Task.sleep(for: .seconds(2))
                        continue
                    }
                }
            } catch {
                lastError = error
                if attempt < maxRetries {
                    print("ClaudeService: retrying after network error (attempt \(attempt + 1))")
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
            }
        }

        throw lastError ?? ClaudeError.invalidResponse
    }

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
        request.timeoutInterval = 30

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

        // Try balanced-brace extraction — look for either "meals" or "foods" key
        if let objectRange = cleaned.range(of: "\\{\\s*\"(?:meals|foods)\"\\s*:\\s*\\[", options: .regularExpression) {
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

        // Also try matching a message-only response (no foods/meals key)
        if let objectRange = cleaned.range(of: "\\{\\s*\"message\"\\s*:", options: .regularExpression) {
            let substring = String(cleaned[objectRange.lowerBound...])
            if let extracted = extractJSON(from: substring),
               let data = extracted.data(using: .utf8),
               let analysis = try? JSONDecoder().decode(AgenticMealAnalysis.self, from: data) {
                return analysis
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
                if depth == 1 {
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
