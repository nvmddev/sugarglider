import SwiftUI
import AppKit

/// Hand-drawn because the stock `Slider` can't be recolored on macOS: `.tint`, `.accentColor` and
/// `NSSlider.trackFillColor` are all ignored (verified on macOS 26). Proportions match the stock slider.
struct TintedSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0
    var tint: Color
    var accessibilityValueText: String?

    @Environment(\.colorScheme) private var colorScheme

    static let knobWidth: CGFloat = 20
    private static let knobHeight: CGFloat = 16
    private static let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let knobOffset = max(proxy.size.width - Self.knobWidth, 1) * Self.fraction(of: value, in: range)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: knobOffset + Self.knobWidth / 2, height: Self.trackHeight)
                Capsule()
                    .fill(colorScheme == .dark ? Color(white: 0.87) : .white)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 0.5)
                    .frame(width: Self.knobWidth, height: Self.knobHeight)
                    .offset(x: knobOffset)
            }
            .frame(height: Self.knobHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    value = Self.value(atX: drag.location.x, trackWidth: proxy.size.width,
                                       range: range, step: step)
                }
            )
        }
        .frame(height: Self.knobHeight)
        .accessibilityElement()
        .accessibilityValue(accessibilityValueText ?? String(format: "%g", value))
        .accessibilityAdjustableAction { direction in
            let delta = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = Self.clamp(value + delta, to: range)
            case .decrement: value = Self.clamp(value - delta, to: range)
            @unknown default: break
            }
        }
    }

    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? clamp((value - range.lowerBound) / span, to: 0...1) : 0
    }

    /// The knob's center travels from `knobWidth / 2` to `trackWidth - knobWidth / 2`.
    static func value(atX x: CGFloat, trackWidth: CGFloat,
                      range: ClosedRange<Double>, step: Double) -> Double {
        let travel = max(trackWidth - knobWidth, 1)
        let fraction = clamp(Double((x - knobWidth / 2) / travel), to: 0...1)
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return clamp(step > 0 ? (raw / step).rounded() * step : raw, to: range)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
