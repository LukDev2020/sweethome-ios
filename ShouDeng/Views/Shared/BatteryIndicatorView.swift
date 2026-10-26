import SwiftUI

struct BatteryIndicatorView: View {
    let level: Double // 0.0 to 1.0
    let isCharging: Bool

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    private var color: Color {
        if level > 0.5 { return safe }
        if level > 0.2 { return lamp }
        return alert
    }

    private var percentage: Int { Int(level * 100) }

    var body: some View {
        HStack(spacing: 3) {
            // Battery icon
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(color, lineWidth: 1)
                    .frame(width: 16, height: 8)

                RoundedRectangle(cornerRadius: 0.5)
                    .fill(color)
                    .frame(width: max(1, 13 * level), height: 5)
                    .padding(.leading, 1.5)

                // Battery tip
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(color)
                    .frame(width: 2, height: 4)
                    .offset(x: 16.5)
            }

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(color)
            }

            Text("\(percentage)%")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
        .opacity(level <= 0.2 ? pulsingOpacity : 1.0)
        .accessibilityLabel("Battery \(percentage) percent\(isCharging ? ", charging" : "")")
    }

    @State private var pulsingOpacity: Double = 1.0

    init(level: Double, isCharging: Bool = false) {
        self.level = level
        self.isCharging = isCharging
    }
}
