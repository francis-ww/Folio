import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 18)
            .foregroundStyle(Theme.paper).background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Theme.motion, value: configuration.isPressed)
    }
}

#Preview { Button("Reveal meaning") {}.buttonStyle(PrimaryButtonStyle()).padding().background(Theme.paper) }
