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
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: NutrientsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Calories (hero stat)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(entry.nutrients.calories))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(renderingMode == .fullColor ? .orange : .primary)
                    .widgetAccentable()
                Text("calories")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Spacer(minLength: 0)

            // Secondary stats
            HStack(spacing: 10) {
                SmallStat(value: "\(Int(entry.nutrients.protein))g", label: "Protein", color: .blue)
                Spacer(minLength: 0)
                SmallStat(value: "\(Int(entry.nutrients.fiber))g", label: "Fiber", color: .green)
                Spacer(minLength: 0)
                SmallStat(value: "\(Int(entry.nutrients.waterOz))oz", label: "Water", color: .cyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "nutritiousai://add-food"))
    }
}

private struct SmallStat: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(renderingMode == .fullColor ? color : .primary)
                .widgetAccentable()
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
            // Left side: stats
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Cal, Protein, Fiber
                HStack(spacing: 16) {
                    PrimaryStat(icon: "flame.fill", value: "\(Int(entry.nutrients.calories))", color: .orange)
                    PrimaryStat(icon: "p.circle.fill", value: "\(Int(entry.nutrients.protein))g", color: .blue)
                    PrimaryStat(icon: "leaf.fill", value: "\(Int(entry.nutrients.fiber))g", color: .green)
                }

                // Row 2: Water, Coffee
                HStack(spacing: 16) {
                    PrimaryStat(icon: "drop.fill", value: "\(Int(entry.nutrients.waterOz))oz", color: .cyan)
                    PrimaryStat(icon: "cup.and.saucer.fill", value: "\(entry.nutrients.coffees)", color: .brown)
                }

                Spacer(minLength: 0)

                // Row 3: Secondary macros (keep labels)
                HStack(spacing: 10) {
                    BottomMacro(value: "\(Int(entry.nutrients.sugar))g", label: "Sugar")
                    BottomMacro(value: "\(Int(entry.nutrients.fat))g", label: "Fat")
                    BottomMacro(value: "\(Int(entry.nutrients.carbs))g", label: "Carbs")
                    BottomMacro(value: "\(Int(entry.nutrients.cholesterol))mg", label: "Chol")
                }
            }

            Spacer(minLength: 0)

            // Right side: action buttons
            VStack(spacing: 8) {
                Button(intent: LogWaterIntent()) {
                    RoundBtn(icon: "drop.fill", color: .cyan)
                }
                .buttonStyle(.plain)

                Button(intent: LogCoffeeIntent()) {
                    RoundBtn(icon: "cup.and.saucer.fill", color: .brown)
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "nutritiousai://add-food")!) {
                    RoundBtn(icon: "plus", color: .green)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct PrimaryStat: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(renderingMode == .fullColor ? color : .primary)
                .widgetAccentable()
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .widgetAccentable()
        }
    }
}

private struct RoundBtn: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.85), in: Circle())
            .widgetAccentable()
    }
}

private struct BottomMacro: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
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
