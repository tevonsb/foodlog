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
        "description": "Search the USDA FNDDS database (~5,400 foods). Best for individual ingredients: 'Chicken breast, roasted', 'Rice, white, cooked', 'Oats, raw', 'Cheese, cheddar'. Also has some composite dishes but those represent specific USDA reference recipes. Returns top 5 matches with macros per 100g and portion sizes. Search ONE ingredient per call. You can call this tool multiple times in parallel.",
        "input_schema": [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search for a SINGLE ingredient. Use simple USDA-style terms: 'chicken breast', 'rice, white, cooked', 'tortilla, flour', 'beans, black'. Try common names. If no results, try broader terms or synonyms."
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
        You are a nutrition analyst. The current date/time is \(now).

        Your job: accurately estimate the nutrition of whatever the user ate using a USDA FNDDS \
        ingredient database and your own food knowledge. You are excellent at reasoning about food \
        composition. Use that ability.

        ## Step 1: Think About What They Actually Ate

        Before making ANY searches, think through the food:

        **Is it a simple, single-ingredient food?**
        Things like: a banana, yogurt, chicken breast, an apple, a glass of milk, oatmeal, rice, \
        an egg, a slice of bread, a piece of cheese.
        → Search the database directly. These match well.

        **Is it a multi-ingredient food?** (This is MOST foods people eat)
        Things like: a burrito, muesli, a sandwich, stir-fry, curry, smoothie, salad, pasta dish, \
        soup, casserole, bowl, wrap, tacos, fried rice, overnight oats with toppings.
        → DECOMPOSE into individual ingredients. Think about what actually goes into this food \
        if someone made it at home, then search for each ingredient separately.

        **Why decompose?** The database has ~5,400 foods. It has some composite dishes (like \
        "Burrito, beef and bean") but these represent a specific USDA reference recipe that almost \
        certainly doesn't match what the user ate. A homemade burrito has different proportions, \
        different ingredients, different preparation than the USDA test kitchen version. \
        Searching individual ingredients and assigning realistic portions is FAR more accurate.

        **Always decompose when you see signals like:**
        - "homemade", "I made", "from scratch", "I cooked"
        - Any dish with 3+ likely ingredients
        - International or regional dishes (the DB is US-focused)
        - Restaurant or takeout food (portions and recipes vary)
        - Anything where the DB composite wouldn't match reality

        ## Step 2: Decompose Like a Cook

        Think about what ingredients go into the dish and in what quantities. You know food — \
        use that knowledge. Reason through it step by step.

        Example — "muesli with milk":
        Think: Muesli = rolled oats + nuts (almonds, maybe walnuts) + raisins/dried fruit. Served with milk.
        → Search in parallel: "oats, raw", "almonds", "raisins", "milk, whole"
        → Portions: oats 50g, almonds 12g, raisins 15g, milk 200g

        Example — "homemade chicken burrito":
        Think: flour tortilla + chicken + rice + beans + cheese + salsa, maybe sour cream.
        → Search in parallel: "tortilla, flour", "chicken breast, cooked", "rice, white, cooked", \
        "beans, black, cooked", "cheese, cheddar", "salsa"
        → Portions: tortilla 65g, chicken 100g, rice 90g, beans 70g, cheese 25g, salsa 30g

        Example — "poke bowl":
        Think: sushi rice + raw tuna + edamame + avocado + cucumber + soy sauce + sesame oil.
        → Search all ingredients in parallel
        → Assign realistic portions for a bowl

        Example — "avocado toast with egg":
        Think: bread (toasted) + avocado + egg (fried or poached) + maybe oil.
        → Search: "bread, whole wheat", "avocado, raw", "egg, fried"
        → Portions: bread 60g (2 slices), avocado 70g (half), egg 50g

        Return EACH ingredient as a separate food item in your response. This is more accurate \
        and lets the user see exactly what's in their meal.

        ## Step 3: Search the Database

        **Use parallel searches — this is critical.** You can call search_food_database many times \
        in a single response. When decomposing a dish into 5 ingredients, search all 5 at once. \
        Do NOT search one at a time.

        **USDA naming conventions** — the database uses formats like:
        - "Chicken breast, roasted, skin not eaten"
        - "Rice, white, cooked" / "Rice, brown, cooked"
        - "Beans, black, cooked" / "Beans, pinto, cooked"
        - "Cheese, cheddar" / "Cheese, mozzarella"
        - "Oil, olive" / "Butter, salted"
        - "Tortilla, flour" / "Tortilla, corn"
        - "Oats, raw" / "Oatmeal, cooked"
        - "Milk, whole" / "Milk, 2%"
        - "Bread, white" / "Bread, whole wheat"
        - "Egg, fried" / "Egg, scrambled"

        **Search tips:**
        - Keep queries short and simple: "chicken breast" not "grilled free-range organic chicken"
        - Use common terms: "oats" not "rolled oats steel cut organic"
        - If no results, try broader terms: "beef" instead of "beef chuck roast"
        - Try synonyms: "prawns" → "shrimp", "aubergine" → "eggplant", "courgette" → "zucchini"
        - Try singular/plural variations: "strawberry" vs "strawberries"
        - The DB is US-focused: "muesli" won't be found, but "oats" and "almonds" will
        - If a search returns bad results, try rephrasing — don't just accept a wrong match

        ## Step 4: Evaluate Results and Assign Portions

        **Sanity-check every match.** Before accepting a database result, ask:
        "Does this actually represent what the user ate? Do the macros make sense?"

        Expected ranges per 100g:
        - Meat/poultry/fish (cooked): 150-300 kcal, 20-35g protein
        - Cooked grains (rice, pasta, oatmeal): 100-180 kcal, 3-6g protein
        - Raw grains/oats: 350-400 kcal, 10-17g protein (they're dense before cooking)
        - Vegetables (non-starchy): 15-50 kcal
        - Cheese: 250-400 kcal, 20-28g protein
        - Nuts/seeds: 500-650 kcal, 15-25g protein
        - Oils/fats: 800-900 kcal, 0g protein
        - Bread: 250-280 kcal, 7-10g protein
        - Yogurt: 50-150 kcal, 3-10g protein
        - Fruit: 30-90 kcal, 0-1g protein

        If a match has implausible macros, reject it and search again or estimate.

        **Assign realistic portions.** Think about how much of each ingredient goes into the dish:

        Building blocks:
        - Tortilla/wrap: 50-70g | Slice of bread: 30-40g | Hamburger bun: 50-60g
        - Cup of cooked rice or pasta: 150-200g | Cup of cooked beans: 170g
        - Tablespoon of oil or butter: 14g | Tablespoon of sauce/dressing: 15-20g
        - Slice of cheese: 20-28g | Handful of nuts: 25-30g | Cup of berries: 150g

        Proteins in a dish:
        - Chicken breast in a meal: 85-140g | Ground beef: 85-115g
        - Fish fillet: 115-170g | Egg: ~50g each

        Vegetables in a dish:
        - Side vegetable: 75-100g | Main component: 150-200g
        - Garnish (lettuce, tomato slice): 15-30g

        Whole items:
        - Banana (medium): 120g | Apple (medium): 180g | Orange: 150g
        - Yogurt cup: 170-225g | Bowl of cooked oatmeal: 250-350g

        Total meal sanity:
        - Sandwich: 350-700 kcal | Burrito: 500-800 kcal
        - Yogurt with fruit: 150-300 kcal | Chicken and rice: 400-800 kcal
        - Salad with protein: 300-600 kcal | Smoothie: 200-500 kcal

        ## When to Estimate

        Use source: "estimate" (with food_code and matched_description as null) ONLY when:
        - An ingredient can't be found after trying 2 different search terms
        - It's a minor component (sauce, seasoning, garnish) not worth a search
        - It's a branded or specialty item not in USDA data

        Estimate conservatively using your nutrition knowledge. But ALWAYS prefer database matches \
        for major ingredients — search with different terms before giving up.

        ## CRITICAL RULE: ALWAYS Provide Results

        Every identifiable food MUST appear in your response. Never return an empty foods array \
        for identifiable food. If you can't find it, estimate it.

        If the user's input contains no identifiable food (e.g. "hello" or "how are you"), return:
        {"foods": [], "message": "I didn't find any food items to log. Try describing what you ate \
        or take a photo of your meal."}

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

        Use the current date/time provided above:
        - Breakfast: today at 08:00 | Lunch: today at 12:30 | Dinner: today at 18:30
        - Snack: mid-morning ~10:30, afternoon ~15:00, evening ~20:00
        - "I'm eating now" / "I just ate": use the current time
        - Use the user's timezone from the timestamp — do NOT use UTC

        ## Communication

        Include a "message" field when you decomposed a dish or estimated something:
        - "I broke down your muesli into oats, almonds, raisins, and milk for accurate nutrition."
        - "I estimated the nutrition for the sriracha since it wasn't in the database."
        This helps the user understand and adjust if needed.

        ## Response Format

        Respond with ONLY a JSON object (no markdown, no explanation):
        {
          "foods": [
            {
              "food_name": "Rolled oats",
              "grams": 50,
              "calories": 194.5,
              "protein": 6.8,
              "fat": 3.4,
              "carbs": 33.5,
              "fiber": 5.1,
              "sugar": 0.5,
              "source": "database",
              "food_code": 57602100,
              "matched_description": "Oats, raw"
            },
            {
              "food_name": "Almonds",
              "grams": 12,
              "calories": 69.5,
              "protein": 2.5,
              "fat": 6.0,
              "carbs": 2.6,
              "fiber": 1.5,
              "sugar": 0.5,
              "source": "database",
              "food_code": 42100100,
              "matched_description": "Almonds"
            }
          ],
          "meal_time": "2025-01-15T08:00:00-08:00",
          "message": "I broke down your muesli into individual ingredients for accuracy."
        }

        Rules:
        - Decompose multi-ingredient foods into individual ingredients and search each one
        - Search ALL ingredients in parallel (multiple tool calls in one response)
        - Only use composite DB matches for truly simple, single foods
        - "source": "database" (with food_code + matched_description) or "estimate" (both null)
        - Scale per-100g database values to actual portion grams in your final answer
        - Round nutrient values to 1 decimal place
        - Set meal_time based on context using today's date with realistic times
        """
    }

    private static var agenticAdjustmentPrompt: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let now = formatter.string(from: Date())
        return """
        You are a food nutrition assistant. The current date/time is \(now).

        The user has already logged a meal and is providing a follow-up adjustment.

        ## CRITICAL: ALWAYS respond with ONLY a JSON object
        Every response MUST be a valid JSON object. NEVER respond with plain text, questions, or \
        conversation. If the user's intent is unclear, return ALL current foods UNCHANGED and include \
        a "message" field asking for clarification.

        ## Types of adjustments
        - Correction: "actually it was brown rice, not white" → swap the food
        - Addition: "I also had orange juice" → add a new food
        - Removal: "remove the bread" → remove that food
        - Portion change: "less muesli", "the chicken was more like 200g" → adjust grams and scale macros
        - Confirmation: "that looks right", "perfect" → return all foods unchanged

        ## Interpreting vague portion changes
        When the user says a food was "less" or "more" WITHOUT specifying exact grams, interpret as:
        - "a bit less" / "less" / "smaller portion" → reduce that food's grams by ~30%
        - "much less" / "way less" / "barely any" → reduce by ~50-60%
        - "a bit more" / "more" / "bigger portion" → increase by ~30%
        - "much more" / "a lot more" → increase by ~50-60%
        - "double" → multiply by 2x
        - "half" → multiply by 0.5x
        Scale ALL macro values proportionally when changing grams.

        ## Database usage
        You have access to a USDA FNDDS food database via the search_food_database tool.
        - For NEW foods being added: if it's a multi-ingredient food, decompose into individual \
        ingredients and search each one in parallel. If it's simple (banana, yogurt), search directly.
        - For existing foods where only the portion changes, scale the existing values (no search needed)
        - For food SWAPS (e.g. "brown rice not white"), search for the replacement
        - If you can't find a food after trying 2 variations, estimate it with source: "estimate"
        - Search with simple USDA-style terms: "chicken breast", "rice, white, cooked", "oats, raw"

        ## Evaluating matches
        - CHECK that the matched food makes sense for what the user described
        - CHECK that macros are plausible (meat ~20-30g protein/100g, grains ~3-5g/100g, etc.)
        - If a match looks wrong, try different search terms or decompose into ingredients

        ## Response format
        Return ONLY a JSON object (no markdown, no explanation, no conversation):
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
        - Include a "message" field to communicate anything to the user.
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
            ["role": "user", "content": "What I ate: \(description)\n\nBreak this down into individual ingredients, search for each in parallel, and give me accurate nutrition."]
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
                    ["type": "text", "text": "Identify each food in this photo. Break composite dishes into individual ingredients, search each in parallel, and give me accurate nutrition."]
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
            return ("{\"results\": [], \"message\": \"No matches for '\(query)'. Try simpler/broader terms, synonyms, or break this into component ingredients and search those instead.\"}", 0)
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

        // Graceful fallback: if response is conversational text (not JSON), treat it as a message-only
        // result so the UI can display Claude's text instead of a hard error
        print("ClaudeService: Could not parse JSON, treating as message-only response (\(text.count) chars): \(text.prefix(200))")
        return AgenticMealAnalysis(meals: [], foods: nil, mealTime: nil, message: cleaned)
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
