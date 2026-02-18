import SwiftUI

struct MacroRow: View {
    let label: String
    let value: Double?
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let value {
                Text(formatValue(value, unit: unit))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatValue(_ value: Double, unit: String) -> String {
        if unit == "kcal" || unit == "mL" {
            return "\(Int(value)) \(unit)"
        } else if value < 1 {
            return String(format: "%.2f \(unit)", value)
        } else if value < 10 {
            return String(format: "%.1f \(unit)", value)
        } else {
            return "\(Int(value)) \(unit)"
        }
    }
}
