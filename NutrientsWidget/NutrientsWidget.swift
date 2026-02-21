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
            // Left side: stats
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Cal, Protein, Fiber
                HStack(spacing: 14) {
                    InlineStat(icon: "flame.fill", value: "\(Int(entry.nutrients.calories))", label: "Cal", color: .orange)
                    InlineStat(icon: "p.circle.fill", value: "\(Int(entry.nutrients.protein))g", label: "Protein", color: .blue)
                    InlineStat(icon: "leaf.fill", value: "\(Int(entry.nutrients.fiber))g", label: "Fiber", color: .green)
                }

                // Row 2: Water, Coffee
                HStack(spacing: 14) {
                    InlineStat(icon: "drop.fill", value: "\(Int(entry.nutrients.waterOz))oz", label: "Water", color: .cyan)
                    InlineStat(icon: "cup.and.saucer.fill", value: "\(entry.nutrients.coffees)", label: "Coffee", color: .brown)
                }

                // Row 3: Secondary macros
                HStack(spacing: 12) {
                    BottomMacro(value: "\(Int(entry.nutrients.sugar))g", label: "Sugar")
                    BottomMacro(value: "\(Int(entry.nutrients.fat))g", label: "Fat")
                    BottomMacro(value: "\(Int(entry.nutrients.carbs))g", label: "Carbs")
                    BottomMacro(value: "\(Int(entry.nutrients.cholesterol))mg", label: "Chol")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right side: round action buttons
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
                    RoundBtn(icon: "plus", color: .accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct InlineStat: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RoundBtn: View {
    let icon: String
    let color: Color

    var body: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(color), in: .circle)
        } else {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: Circle())
        }
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
