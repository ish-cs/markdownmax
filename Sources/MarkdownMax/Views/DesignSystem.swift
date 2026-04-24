import SwiftUI

// MARK: - Brand colors

extension Color {
    static let mmGreen  = Color(red: 0.145, green: 0.831, blue: 0.404)
    static let mmRed    = Color(red: 0.98,  green: 0.24,  blue: 0.25)
    static let mmDark   = Color(white: 0.09)
}

// MARK: - Timer pill

struct TimerPill: View {
    let text: String
    var dotColor: Color = .mmRed

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(.callout, design: .rounded).bold().monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Color.mmDark)
        .clipShape(Capsule())
    }
}

// MARK: - Button styles

struct PebblePillStyle: ButtonStyle {
    var fill: Color = .mmGreen
    var fg: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.bold())
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(fg)
            .background(configuration.isPressed ? fill.opacity(0.8) : fill)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PebbleCircleStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(configuration.isPressed ? fill.opacity(0.8) : fill)
            .clipShape(Circle())
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}
