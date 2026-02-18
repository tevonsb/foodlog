import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct NutrientsProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutrientsEntry {
        NutrientsEntry(date: .now, nutrients: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NutrientsEntry) -> Void) {
        completion(NutrientsEntry(date: .now, nutrients: TodayNutrients.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutrientsEntry>) -> Void) {
        let nutrients = TodayNutrients.load()
        let entry = NutrientsEntry(date: .now, nutrients: nutrients)
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
        let refreshDate = min(midnight, Date().addingTimeInterval(1800))
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct NutrientsEntry: TimelineEntry {
    let date: Date
    let nutrients: TodayNutrients
}

// MARK: - Widget Entry View

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NutrientsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: NutrientsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
                Text("Today")
                    .font(.headline)
            }

            Spacer(minLength: 2)

            VStack(spacing: 4) {
                WidgetNutrientRow(label: "Calories", value: entry.nutrients.calories, unit: "", color: .orange)
                WidgetNutrientRow(label: "Protein", value: entry.nutrients.protein, unit: "g", color: .red)
                WidgetNutrientRow(label: "Carbs", value: entry.nutrients.carbs, unit: "g", color: .blue)
                WidgetNutrientRow(label: "Fat", value: entry.nutrients.fat, unit: "g", color: .yellow)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "nutritiousai://add-food"))
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: NutrientsEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(.green)
                    Text("Today")
                        .font(.headline)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 6) {
                    NutrientPill(label: "Cal", value: entry.nutrients.calories, unit: "", color: .orange)
                    NutrientPill(label: "Protein", value: entry.nutrients.protein, unit: "g", color: .red)
                    NutrientPill(label: "Carbs", value: entry.nutrients.carbs, unit: "g", color: .blue)
                    NutrientPill(label: "Fat", value: entry.nutrients.fat, unit: "g", color: .yellow)
                    NutrientPill(label: "Fiber", value: entry.nutrients.fiber, unit: "g", color: .green)
                    NutrientPill(label: "Sugar", value: entry.nutrients.sugar, unit: "g", color: .pink)
                }
            }

            Link(destination: URL(string: "nutritiousai://add-food")!) {
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                    Text("Log")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Helper Views

struct WidgetNutrientRow: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 12)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value))\(unit)")
                .font(.caption.bold())
        }
    }
}

struct NutrientPill: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text("\(Int(value))\(unit)")
                .font(.caption.bold())
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Widget

@main
struct NutrientsWidgetMain: Widget {
    let kind = "NutrientsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutrientsProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nutritious AI")
        .description("Track your daily nutrients at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
