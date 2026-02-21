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
        VStack(spacing: 6) {
            // Row 1: Calories, Protein, Fiber
            HStack(spacing: 8) {
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

            // Row 2: Water, Coffee, Add
            HStack(spacing: 8) {
                Button(intent: LogWaterIntent()) {
                    MediumStat(
                        icon: "drop.fill",
                        value: "\(Int(entry.nutrients.waterOz))oz",
                        label: "Water",
                        color: .cyan
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogCoffeeIntent()) {
                    MediumStat(
                        icon: "cup.and.saucer.fill",
                        value: "\(entry.nutrients.coffees)",
                        label: "Coffee",
                        color: .brown
                    )
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "nutritiousai://add-food")!) {
                    VStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                        Text("Log")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            // Bottom bar: secondary macros
            HStack(spacing: 0) {
                BottomStat(value: "\(Int(entry.nutrients.carbs))g", label: "Carbs")
                Spacer(minLength: 0)
                BottomStat(value: "\(Int(entry.nutrients.fat))g", label: "Fat")
                Spacer(minLength: 0)
                BottomStat(value: "\(Int(entry.nutrients.sugar))g", label: "Sugar")
                Spacer(minLength: 0)
                BottomStat(value: "\(Int(entry.nutrients.sodium))mg", label: "Na")
                Spacer(minLength: 0)
                BottomStat(value: "\(Int(entry.nutrients.cholesterol))mg", label: "Chol")
                Spacer(minLength: 0)
                BottomStat(value: "\(Int(entry.nutrients.saturatedFat))g", label: "Sat Fat")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

private struct BottomStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
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
