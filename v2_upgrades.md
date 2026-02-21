# Nutritious v2 — Upgrade Roadmap

## 1. Full iOS 26 + Liquid Glass Redesign

**Current state:** Targets iOS 17, uses standard SwiftUI components with custom styling.
**Target:** iOS 26.0 minimum deployment. Drop all backward compatibility.

### 1a. Automatic Glass Adoption

Building with the Xcode 26 SDK automatically upgrades:
- `NavigationStack` toolbars → liquid glass chrome
- `TabView` → floating glass tab bar pill
- Sheets → inset with glass backgrounds
- `.bordered` buttons → capsule-shaped glass
- System typography → slightly bolder weights

**What to remove:**
- Any custom toolbar/navigation bar backgrounds
- Custom `presentationBackground` modifiers on sheets
- Hardcoded dividers between nav bars and content
- Baked-in shadows or borders on bar items

### 1b. Custom Glass UI Elements

Replace the current floating action buttons (coffee, water, add food) with glass-styled controls:

```swift
// Current: Custom overlay circles with fills
// v2: Glass effect containers with morphing
GlassEffectContainer {
    HStack(spacing: 12) {
        Button(action: logCoffee) {
            Image(systemName: "cup.and.saucer.fill")
        }
        .glassEffect(.regular.tint(.brown).interactive(), in: .circle)

        Button(action: logWater) {
            Image(systemName: "drop.fill")
        }
        .glassEffect(.regular.tint(.cyan).interactive(), in: .circle)

        Button(action: addFood) {
            Image(systemName: "plus")
        }
        .glassEffect(.prominent.interactive(), in: .circle)
    }
}
```

### 1c. Tab-Based Navigation

Replace the current single-view-with-settings-gear pattern with a proper `TabView`:

```swift
TabView {
    Tab("Log", systemImage: "fork.knife") {
        FoodLogView()
    }
    Tab("Trends", systemImage: "chart.line.uptrend.xyaxis") {
        TrendsView()  // New — see upgrade #5
    }
    Tab("Search", systemImage: "magnifyingglass", role: .search) {
        FoodSearchView()  // New — see upgrade #6
    }
    Tab("Settings", systemImage: "gear") {
        SettingsView()
    }
}
.tabBarMinimizeBehavior(.onScrollDown)
```

The `.search` tab role morphs the tab into a search field — perfect for quick food lookups.

### 1d. Scroll Edge Effects

Replace any hard dividers with the new scroll edge system:

```swift
List { ... }
    .scrollEdgeEffectStyle(.soft)  // Gradual fade at edges
```

### 1e. Sheet Morphing Transitions

Use `navigationTransition(.zoom)` for meal detail presentation — tapping a meal card morphs into the detail view instead of a plain push:

```swift
NavigationLink(value: entry) {
    MealRow(entry: entry)
}
.navigationTransition(.zoom(sourceID: entry.id, in: namespace))
```

### 1f. New App Icon

Redesign the app icon using Icon Composer with layered glass material:
- Gyro-responsive highlights on icon edges
- Support for monochrome glass and tinted glass (light/dark) appearances
- Flat/frontal design, bold line weights, 1024px canvas

### 1g. New APIs to Adopt
- `@Animatable` macro (replace manual `AnimatableData` conformance)
- `ToolbarSpacer` for organizing toolbar item groups
- `tabViewBottomAccessory { }` — potential spot for a persistent "today's totals" strip
- `backgroundExtensionEffect()` — extend meal photos behind navigation chrome

**Effort:** Medium-large (touches every view, but most changes are deletions/simplifications)
**Impact:** The app feels native to iOS 26 instead of a ported iOS 17 app

---

## 2. Streaming API Responses

**Current state:** `URLSession.shared.data(for:)` — waits for the entire response before showing anything. On cellular, the agentic loop (up to 4 iterations) can feel very slow.

**Upgrade:** Switch to the Anthropic streaming Messages API (`"stream": true`). Parse Server-Sent Events incrementally.

**User-facing change:**
- Show Claude's thinking/progress in real-time as it searches the database
- Display intermediate states: "Searching for 'grilled chicken'...", "Found match, checking portions...", "Estimating side salad..."
- Each food appears in the result card as it's identified, rather than all at once

**Implementation approach:**
- Use `URLSession.bytes(for:)` (async sequence) to read SSE chunks
- Parse `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop` events
- On `tool_use` content blocks, execute the tool and continue the loop
- On `text` content blocks, parse partial JSON for progressive display

**Effort:** Medium (refactor `ClaudeService.analyzeFood` to use async streaming)
**Impact:** High — perceived latency drops dramatically even though actual API time is similar

---

## 3. Prompt Caching

**Current state:** Every API call sends the full system prompt (~1500+ tokens) and tool definition fresh.

**Upgrade:** Add `cache_control` to the system prompt and tool definitions. Within a 5-minute window, subsequent requests read from cache at 90% discount on input tokens.

```json
{
    "system": [{
        "type": "text",
        "text": "...system prompt...",
        "cache_control": {"type": "ephemeral"}
    }],
    "tools": [{
        ...tool definition...,
        "cache_control": {"type": "ephemeral"}
    }]
}
```

**Critical Swift caveat:** `JSONSerialization` randomizes dictionary key order, which breaks caches. Fix by using ordered serialization — either `JSONEncoder` with `Codable` structs (which preserve declaration order) or manually building JSON strings for the cached portions.

**Effort:** Small (add cache_control fields + fix serialization ordering)
**Impact:** High — each iteration of the agentic loop after the first is ~90% cheaper on cached input tokens. Users who log multiple meals in a session save significantly.

---

## 4. Adaptive Thinking + Interleaved Reasoning

**Current state:** Claude makes tool-use decisions purely from the conversation, with no explicit reasoning step.

**Upgrade:** Enable adaptive thinking for the agentic loop:

```json
{
    "thinking": {"type": "adaptive"},
    "output_config": {"effort": "low"}
}
```

- `"low"` effort for text descriptions (fast, minimal thinking)
- `"medium"` effort for photo analysis (more careful identification)

**What this enables:**
- Claude reasons *between* tool calls: "The result 'Soup, meatball' doesn't match — let me try 'meatball, beef' instead"
- Better search query refinement without explicit prompt instructions
- Reduced hallucination — Claude thinks before committing to estimates

**Implementation note:** When thinking is enabled, you must preserve and re-send `thinking` blocks in subsequent conversation turns. Update the agentic loop to capture these blocks.

**Effort:** Small-medium (add thinking config, update loop to preserve thinking blocks)
**Impact:** Medium — better food identification accuracy, especially for ambiguous items

---

## 5. Nutrition Trends & Charts (New Tab)

**Current state:** Only shows today's totals. No historical view, no trends, no goal tracking.

**Upgrade:** Add a "Trends" tab using Swift Charts:

### Daily Summary Bar Chart
- Stacked bars: protein (indigo), carbs (orange), fat (yellow)
- `RuleMark` overlay for daily calorie target
- Scrollable 7-day / 30-day view with `chartScrollableAxes(.horizontal)`
- Tap a day to drill down into meals

### Weekly/Monthly Averages
- `LineMark` for calorie trends over time
- `AreaMark` for macro ratio trends
- Annotations highlighting streaks (e.g., "5 days hitting protein goal")

### Daily Goals
- Let users set macro targets (calories, protein, fiber, water)
- Store in UserDefaults or SwiftData
- Show progress rings or bars on the main log view
- `RuleMark` reference lines on charts

### Micronutrient Coverage
- Weekly heatmap showing which vitamins/minerals are consistently logged
- Highlights gaps (e.g., "Low vitamin D this week")

```swift
Chart(weeklyData) { day in
    BarMark(
        x: .value("Day", day.date, unit: .day),
        y: .value("Calories", day.calories)
    )
    .foregroundStyle(by: .value("Macro", day.macro))
}
.chartYScale(domain: 0...calorieGoal * 1.2)
.chartOverlay { proxy in
    // Interactive selection
}
```

**Effort:** Medium-large (new view, data aggregation queries, goal storage)
**Impact:** High — transforms the app from a logging tool into a nutrition tracking system

---

## 6. Standalone Food Search (New Tab)

**Current state:** Can only search the FNDDS database through Claude (costs API tokens).

**Upgrade:** Add a direct database search tab that lets users browse/search FNDDS without an API call:

- Search bar → FTS5 query → show results with full nutrient profiles
- Tap a result to see the complete 32-column nutrient breakdown
- "Quick log" button to add a food directly without Claude
- Portion size picker using database `portions` table
- Favorites/recent foods list for quick re-logging

This gives users a free, offline, instant way to log known foods they eat regularly.

**Effort:** Medium (new views, reuses existing `FNDDSDatabase` methods)
**Impact:** High — reduces API costs, works offline, faster for repeat meals

---

## 7. Meal Templates & Favorites

**Current state:** Every meal requires a fresh Claude API call, even if it's the same breakfast the user eats daily.

**Upgrade:**
- **Favorites:** Long-press a logged meal → "Save as favorite". Stores the complete food breakdown locally.
- **Quick re-log:** Tap a favorite to instantly log it (no API call needed). Optionally adjust portions.
- **Templates:** "Morning coffee + oatmeal" as a one-tap template.
- Store as SwiftData entities referencing the original `LoggedFood` arrays.

**Effort:** Small-medium (new SwiftData model, UI for favorites list)
**Impact:** High — eliminates API calls for repeat meals, huge UX improvement for daily users

---

## 8. On-Device AI with Foundation Models

**Current state:** All food identification requires Claude API (network + cost).

**Upgrade:** iOS 26 introduces the Foundation Models framework — a 3B parameter on-device LLM with structured generation:

```swift
import FoundationModels

@Generable
struct QuickFoodEstimate {
    @Guide(description: "Food item name")
    var name: String
    @Guide(description: "Estimated calories")
    var calories: Int
    @Guide(description: "Estimated protein in grams")
    var protein: Double
    @Guide(description: "Estimated carbs in grams")
    var carbs: Double
    @Guide(description: "Estimated fat in grams")
    var fat: Double
}

let session = LanguageModelSession()
let result = try await session.respond(
    to: "Estimate nutrition for: \(userInput)",
    generating: QuickFoodEstimate.self
)
```

**Use cases:**
- **Offline fallback:** When there's no network, use on-device model for rough estimates
- **Pre-classification:** Quickly categorize food type on-device, then use that to refine the FNDDS search query before hitting Claude
- **Smart suggestions:** As user types, on-device model suggests completions ("chick..." → "chicken breast, grilled")

**Limitations:** The on-device model is optimized for classification/extraction, not world knowledge. It won't match Claude's accuracy for complex meals. Best used as a complement, not a replacement.

**Effort:** Medium (new service layer, fallback logic)
**Impact:** Medium — enables offline use and reduces API dependency for simple foods

---

## 9. Barcode / Label Scanning

**Current state:** Text input or camera photo only.

**Upgrade:** Add barcode scanning using the device camera + a nutrition API:

- Use `AVCaptureSession` with `AVMetadataObjectTypeEAN13Code` / `AVMetadataObjectTypeUPCECode`
- Look up barcodes against OpenFoodFacts API (free, open-source, 3M+ products)
- Display product name, brand, nutrition facts
- One-tap to log with pre-filled nutrients
- Fall back to Claude photo analysis if barcode not found

Alternative: Use Vision framework's `VNRecognizeTextRequest` to OCR a nutrition facts label directly, then parse the structured text.

**Effort:** Medium (camera integration, API client, OCR parsing)
**Impact:** High — packaged foods are a huge portion of what people eat

---

## 10. Improved Error Handling & Retry Logic

**Current state:** API errors show a red message. User must manually retry. No timeout handling. Truncated JSON repair is heuristic.

**Upgrade:**
- **Automatic retry:** Retry on 429 (rate limit) and 529 (overloaded) with exponential backoff
- **Timeout handling:** Set a 30-second timeout per API call, show a "Taking longer than usual..." message at 10s
- **Graceful degradation:** On persistent failure, offer to log with manual nutrition entry
- **Better JSON repair:** Use `strict: true` on tool definitions to guarantee schema conformance from Claude's tool calls. For final response parsing, add a secondary validation pass.

**Effort:** Small (retry logic, timeout config, UI states)
**Impact:** Medium — reduces user frustration on flaky connections

---

## 11. Enhanced Photo Analysis

**Current state:** Single photo, resized to 1024px, JPEG 0.8.

**Upgrade:**
- **Optimal sizing:** Resize to 1568px max (Anthropic's recommended sweet spot — larger than current 1024px, better accuracy)
- **Multi-photo support:** Allow 2-3 photos per meal (different angles, close-ups of individual items)
- **Photo review:** Show the captured photo with an option to retake before sending
- **Files API:** Upload the photo once via Anthropic's Files API, then reference by `file_id` for meal adjustments (avoids re-uploading the same image)

**Effort:** Small-medium
**Impact:** Medium — better food identification from photos

---

## 12. Widget Upgrades

**Current state:** Small widget (5-row stats), medium widget (pills + quick actions). Data via shared UserDefaults.

**Upgrade:**
- **Glass-styled widgets:** Adopt iOS 26 widget glass material
- **Interactive widgets (iOS 17+):** Already have water/coffee quick-actions; add a "quick-log favorite" button
- **Live Activities:** Show a persistent lock screen tracker during meal logging (progress bar as Claude analyzes)
- **StandBy mode:** Large format widget for StandBy/Always-On display showing daily progress rings
- **Goal progress:** Show progress toward daily targets (calories ring, protein bar, etc.)

**Effort:** Medium
**Impact:** Medium — widgets are the most-used surface for daily trackers

---

## 13. Data Export & Sharing

**Current state:** Data lives only in SwiftData on-device. No export.

**Upgrade:**
- **CSV export:** Export meal history with full nutrient data
- **PDF daily/weekly reports:** Generate formatted nutrition summaries
- **Share sheet integration:** Share a meal's nutrition breakdown
- **iCloud sync:** Use SwiftData + CloudKit for cross-device sync (if user has multiple devices)

**Effort:** Small (CSV), Medium (PDF/CloudKit)
**Impact:** Medium — important for users who track with coaches or dietitians

---

## 14. Manual Entry & Editing

**Current state:** Can only "adjust" a meal by re-running Claude. No manual nutrient entry.

**Upgrade:**
- **Manual food entry:** Form to enter food name + macros directly (no API call)
- **Edit logged foods:** Tap a food in meal detail to adjust grams, calories, macros
- **Delete individual foods:** Swipe-to-delete a single food from a meal (not the whole meal)
- **Add foods to existing meal:** "Add another item" button in meal detail

**Effort:** Small-medium
**Impact:** Medium — essential for power users and corrections

---

## Priority Matrix

| Upgrade | Effort | Impact | Priority |
|---------|--------|--------|----------|
| 1. iOS 26 + Liquid Glass | Medium-large | High | **P0** |
| 2. Streaming responses | Medium | High | **P0** |
| 3. Prompt caching | Small | High | **P0** |
| 7. Meal favorites/templates | Small-medium | High | **P1** |
| 6. Standalone food search | Medium | High | **P1** |
| 5. Trends & Charts | Medium-large | High | **P1** |
| 9. Barcode scanning | Medium | High | **P1** |
| 4. Adaptive thinking | Small-medium | Medium | **P2** |
| 10. Error handling & retry | Small | Medium | **P2** |
| 14. Manual entry & editing | Small-medium | Medium | **P2** |
| 11. Better photo analysis | Small-medium | Medium | **P2** |
| 12. Widget upgrades | Medium | Medium | **P2** |
| 8. On-device AI | Medium | Medium | **P3** |
| 13. Data export | Small-medium | Medium | **P3** |

---

## Suggested Implementation Order

**Phase 1 — Foundation:** #1 (iOS 26), #3 (prompt caching), #2 (streaming)
These are infrastructure changes that everything else builds on.

**Phase 2 — Core Features:** #7 (favorites), #6 (food search tab), #14 (manual entry)
Reduce API dependency and add offline capability.

**Phase 3 — Analytics:** #5 (trends/charts), #12 (widget upgrades)
Turn logging data into actionable insights.

**Phase 4 — Advanced:** #9 (barcode scanning), #4 (adaptive thinking), #8 (on-device AI)
Expand input methods and intelligence.

**Phase 5 — Polish:** #10 (error handling), #11 (photo improvements), #13 (export)
Production hardening and power-user features.
