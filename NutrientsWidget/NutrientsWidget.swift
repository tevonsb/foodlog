import WidgetKit
import SwiftUI
import AppIntents

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
        VStack(alignment: .leading, spacing: 0) {
            // Calories (hero stat)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(entry.nutrients.calories))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("calories")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            // Secondary stats
            HStack(spacing: 0) {
                SmallStat(value: "\(Int(entry.nutrients.protein))g", label: "Protein", color: .blue)
                Spacer(minLength: 0)
                SmallStat(value: "\(Int(entry.nutrients.fiber))g", label: "Fiber", color: .green)
                Spacer(minLength: 0)
                SmallStat(value: "\(Int(entry.nutrients.waterOz))oz", label: "Water", color: .cyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "nutritiousai://add-food"))
    }
}

private struct SmallStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: NutrientsEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left: Nutrient stats
            VStack(alignment: .leading, spacing: 8) {
                // Stats grid
                HStack(spacing: 10) {
                    MediumStat(
                        icon: "flame.fill",
                        value: "\(Int(entry.nutrients.calories))",
                        label: "Cal",
                        color: .orange
                    )
                    MediumStat(
                        icon: "p.circle.fill",
                        value: "\(Int(entry.nutrients.protein))g",
                        label: "Protein",
                        color: .blue
                    )
                    MediumStat(
                        icon: "leaf.fill",
                        value: "\(Int(entry.nutrients.fiber))g",
                        label: "Fiber",
                        color: .green
                    )
                }

                Spacer(minLength: 0)

                // Beverages
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                        Text("\(Int(entry.nutrients.waterOz))oz")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.brown)
                        Text("\(entry.nutrients.coffees)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
            }

            Spacer(minLength: 0)

            // Right: Action buttons
            VStack(spacing: 6) {
                Button(intent: LogWaterIntent()) {
                    ZStack {
                        Circle()
                            .fill(.cyan.opacity(0.15))
                        Image(systemName: "drop.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Button(intent: LogCoffeeIntent()) {
                    ZStack {
                        Circle()
                            .fill(.brown.opacity(0.15))
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.brown)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "nutritiousai://add-food")!) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 44, height: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct MediumStat: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
        .configurationDisplayName("Nutritious")
        .description("Track your daily nutrients at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
