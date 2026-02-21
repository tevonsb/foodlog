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
        "description": "Search the USDA FNDDS food database. The database contains both individual ingredients (e.g. 'Chicken breast, grilled', 'Rice, white, cooked') AND composite/prepared foods (e.g. 'Roast beef sandwich on white', 'Pizza, cheese'). Returns top 5 matches with macros per 100g and available portion sizes. Search ONE food concept at a time — never combine unrelated foods in a single query (search 'yogurt' and 'berries' separately, not 'yogurt berries').",
        "input_schema": [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query for a SINGLE food item. Use USDA naming style: 'Food, preparation method' (e.g. 'Chicken breast, roasted' or 'Rice, white, cooked'). For composite items, search the whole thing first (e.g. 'roast beef sandwich'). Try simple, common terms."
                ]
            ],
            "required": ["query"]
        ] as [String: Any]
    ]

    // MARK: - System prompts

    private static var agenticSystemPrompt: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let now = formatter.string(from: Date())
        return """
        You are a food nutrition assistant. The current date/time is \(now).

        ## CRITICAL RULE: ALWAYS provide results
        You must ALWAYS provide nutrition data for every food item the user mentions. If the database \
        has no good match after 2 searches, you MUST estimate using your nutrition knowledge. Set \
        source to "estimate" with food_code and matched_description as null. Every identifiable food \
        MUST appear in your response. Never refuse or return an empty foods array for identifiable food.

        If the user's input contains no identifiable food (e.g. "hello" or "how are you"), return:
        {"foods": [], "message": "I didn't find any food items to log. Try describing what you ate or take a photo of your meal."}

        ## Database and Search Strategy

        You have access to a USDA FNDDS food database via the search_food_database tool. This database contains:
        - **Individual ingredients** (e.g. "Chicken breast, grilled", "Rice, white, cooked", "Beef, roast")
        - **Composite/prepared foods** (e.g. "Roast beef sandwich on white", "Pizza, cheese", "Burrito, beef and bean")

        ### How to search efficiently:
        1. **Search for ONE food concept per query** — never combine unrelated foods in a single search
           - GOOD: search("yogurt"), then search("blueberries")
           - BAD: search("yogurt berries") or search("chicken and rice")

        2. **Try composite items FIRST** when appropriate:
           - For sandwiches, burgers, pizza, burritos → search the whole item first
           - Example: "roast beef sandwich" → search("roast beef sandwich") before decomposing
           - If the composite search returns good matches, use it. If not, decompose into ingredients.

        3. **Call multiple tools in parallel** — you can issue multiple search_food_database calls in ONE response
           - This is CRITICAL for efficiency within your iteration budget
           - Example: search("chicken breast"), search("white rice"), search("broccoli") all in the same turn

        4. **Search terms should be simple and specific**:
           - Use USDA naming style: "Food, preparation method"
           - Try variations if first search fails: "strawberry" vs "strawberries", "beef roast" vs "roast beef"

        ## Portion Size Guidance

        Use realistic portion estimates (in grams):
        - Sandwich: 200-300g total
        - Burger with bun: 250-350g
        - Pizza slice: 100-150g
        - Yogurt cup/serving: 170-225g
        - Banana (medium): 120g
        - Apple (medium): 180g
        - Chicken breast: 150-200g
        - Cup of cooked rice/pasta: 150-200g
        - Tablespoon of oil/butter: 15g
        - Handful of nuts: 30g
        - Cup of berries: 150g

        ## Evaluating Matches — SENSE CHECK REQUIRED

        **Before accepting any database match, verify it makes sense:**

        ### Macro ranges per 100g (reject matches outside these ranges):
        - Meat/poultry/fish (cooked): 150-300 kcal, 20-35g protein, 3-20g fat
        - Cooked grains/pasta: 100-150 kcal, 3-5g protein, 0-3g fat
        - Vegetables (non-starchy): 15-50 kcal, 1-3g protein, 0-1g fat
        - Cheese: 250-400 kcal, 20-28g protein, 20-35g fat
        - Bread: 250-280 kcal, 7-10g protein, 2-5g fat
        - Sandwich (composite): 180-250 kcal, 10-18g protein, 5-12g fat
        - Yogurt: 50-150 kcal, 3-10g protein, 0-8g fat

        ### Total meal sanity (after calculating final portions):
        - A sandwich meal: 350-700 kcal
        - A yogurt with fruit: 150-300 kcal
        - A chicken and rice meal: 400-800 kcal
        - A banana: 100-120 kcal

        **If a match looks wrong** (e.g. "Soup, beef" returned for "roast beef"), search with different terms.
        **If macros are implausible** (e.g. roast beef showing 50 kcal/100g), reject it and search again or estimate.

        ## When to Override with Estimates

        Use source: "estimate" when:
        - Database returned obviously wrong food (wrong type entirely)
        - No results found after trying 2 different search queries
        - Complex homemade or restaurant dishes not in USDA database
        - Branded foods not in database

        When estimating, use your nutrition knowledge to provide realistic values based on the sense-check ranges above.

        ## Multi-meal Support

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

        ## Setting Meal Times

        When determining meal_time, use the current date/time provided above and apply these rules:

        1. **If the user describes PAST meals** (e.g., "I had breakfast", "I ate lunch"):
           - Breakfast: Set to today at 08:00 in the user's timezone
           - Lunch: Set to today at 12:30 in the user's timezone
           - Dinner: Set to today at 18:30 in the user's timezone
           - Snack: Set to a reasonable time based on context (mid-morning ~10:30, afternoon ~15:00, evening ~20:00)

        2. **If the user describes a meal they're eating NOW** (e.g., "I'm eating", "I just ate"):
           - Use the current time from the timestamp above

        3. **Use the user's timezone from the provided timestamp** - do NOT use UTC for meal times

        4. **Examples with proper times**:
           - Current time: 2025-01-15T14:23:00-08:00 (2:23 PM PST)
           - User says "I had a bagel for breakfast and chicken for lunch"
           - Breakfast meal_time: 2025-01-15T08:00:00-08:00
           - Lunch meal_time: 2025-01-15T12:30:00-08:00

        ## Communication

        If you need to tell the user something (e.g. you estimated a food, or something was ambiguous), \
        include a "message" field in your response:
        {"foods": [...], "message": "I estimated the nutrition for your homemade sauce since it wasn't in the database."}

        ## Final Response Format

        After you have gathered all nutrition data, respond with ONLY a JSON object (no markdown, no explanation):
        {
          "foods": [
            {
              "food_name": "Roast beef sandwich",
              "grams": 250,
              "calories": 485,
              "protein": 32.5,
              "fat": 18.8,
              "carbs": 45.0,
              "fiber": 2.1,
              "sugar": 5.2,
              "source": "database",
              "food_code": 27513010,
              "matched_description": "Roast beef sandwich on white"
            }
          ],
          "meal_time": "2025-01-15T12:30:00Z"
        }

        Rules:
        - Search for ONE food concept per query (never combine unrelated foods)
        - Call multiple search tools in parallel when analyzing a meal with multiple foods
        - Try composite items first, decompose only if no good match
        - Estimate realistic portion sizes in grams using the guidance above
        - Sense-check all matches against the macro ranges provided
        - "source" must be "database" (with food_code and matched_description) or "estimate" (both null)
        - Scale the per-100g values to the actual portion grams in your final answer
        - Set meal_time based on meal context (breakfast, lunch, dinner) using today's date with realistic times
        - Round nutrient values to 1 decimal place
        """
    }

    private static var agenticAdjustmentPrompt: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let now = formatter.string(from: Date())
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
            ["role": "user", "content": "Identify the foods and their nutrition in this meal: \(description). You can call the search tool multiple times in a single response for efficiency."]
        ]
        return makeStream(messages: messages, system: agenticSystemPrompt, model: sonnetModel)
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
        return makeStream(messages: messages, system: agenticAdjustmentPrompt, model: sonnetModel)
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
        let maxIterations = 8

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
                    var meals = analysis.resolvedMeals

                    // Post-processing sanity check
                    meals = meals.map { meal in
                        var warnings: [String] = []
                        for food in meal.foods {
                            if let warning = sanityCheckFood(food) {
                                warnings.append(warning)
                            }
                        }
                        if !warnings.isEmpty {
                            let warningMsg = warnings.joined(separator: " ")
                            let existingMsg = meal.message ?? ""
                            let newMessage = existingMsg.isEmpty ? warningMsg : "\(existingMsg) \(warningMsg)"
                            return AgenticMealResult(mealLabel: meal.mealLabel, mealTime: meal.mealTime, foods: meal.foods, message: newMessage)
                        }
                        return meal
                    }

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

        // Max iterations reached — force final resolution
        print("ClaudeService: Max iterations reached, forcing final resolution")
        conversationMessages.append([
            "role": "user",
            "content": "You must now respond with your final JSON. For any foods you haven't found in the database, estimate using your nutrition knowledge with source: 'estimate'. Provide a complete response now."
        ])

        do {
            let (contentBlocks, _) = try await callClaudeAPIWithRetry(
                messages: conversationMessages,
                system: system,
                tools: [], // No tools — force end_turn
                model: model
            )

            let textContent = contentBlocks
                .compactMap { $0["text"] as? String }
                .joined()

            if !textContent.isEmpty {
                let analysis = try parseAgenticResponse(text: textContent)
                let meals = analysis.resolvedMeals

                for meal in meals {
                    for food in meal.foods where food.source == "estimate" {
                        continuation.yield(.estimating(foodName: food.foodName))
                    }
                }

                continuation.yield(.completed(meals))
                return
            }
        } catch {
            print("ClaudeService: Forced resolution failed: \(error)")
        }

        // Last resort fallback
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

    private static func sanityCheckFood(_ food: AgenticFoodResult) -> String? {
        guard food.grams > 0 else { return nil }

        let caloriesPer100g = (food.calories / food.grams) * 100
        let proteinPer100g = (food.protein / food.grams) * 100

        // Flag suspiciously low calories
        if caloriesPer100g < 30 && food.grams > 100 {
            return "⚠️ \(food.foodName) seems low in calories."
        }

        // Flag suspiciously high protein (likely wrong match)
        if proteinPer100g > 50 {
            return "⚠️ \(food.foodName) protein level seems unusually high."
        }

        return nil
    }

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
