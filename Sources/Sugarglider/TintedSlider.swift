import SwiftUI
import AppKit

/// A horizontal slider whose filled track honors an arbitrary color.
///
/// The stock `Slider` is AppKit-backed on macOS and simply cannot be recolored:
/// `.tint(_:)`, `.accentColor(_:)` and `NSSlider.trackFillColor` are all
/// ignored, and the fill stays a fixed neutral grey (verified by off-screen
/// renders on macOS 26). So `AppSettings.sliderColor` means drawing the control
/// by hand. This is the only hand-drawn control in the app; don't "simplify" it
/// back to a stock `Slider`.
///
/// Behavior matches `NSSlider`: a click on the track jumps the knob there,
/// dragging tracks continuously, values snap to `step`. Keyboard adjustment is
/// the one thing missing, which the VoiceOver actions below stand in for.
struct TintedSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0
    var tint: Color
    /// Spoken by VoiceOver in place of the raw number, e.g. "6 hours".
    var accessibilityValueText: String?

    static let knobDiameter: CGFloat = 16
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // The knob's center travels between the two inset ends, so the fill
            // stops at the knob's center rather than at the edge.
            let usable = max(width - Self.knobDiameter, 1)
            let f = Self.fraction(of: value, in: range)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: Self.knobDiameter / 2 + usable * f, height: trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .offset(x: usable * f)
            }
            .frame(height: Self.knobDiameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    value = Self.value(atX: g.location.x, trackWidth: width, range: range, step: step)
                }
            )
        }
        .frame(height: Self.knobDiameter)
        .accessibilityElement()
        .accessibilityValue(accessibilityValueText ?? String(format: "%g", value))
        .accessibilityAdjustableAction { direction in
            let delta = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(max(value + delta, range.lowerBound), range.upperBound)
            case .decrement: value = min(max(value - delta, range.lowerBound), range.upperBound)
            @unknown default: break
            }
        }
    }

    /// Where `value` sits in `range`, as a clamped 0…1.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The value a click or drag at `x` selects. The knob's travel is inset by
    /// half a knob at each end; the result snaps to `step` when that is > 0.
    static func value(atX x: CGFloat, trackWidth: CGFloat,
                      range: ClosedRange<Double>, step: Double) -> Double {
        let usable = max(trackWidth - knobDiameter, 1)
        let f = min(max((x - knobDiameter / 2) / usable, 0), 1)
        let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
        let snapped = step > 0 ? (raw / step).rounded() * step : raw
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
