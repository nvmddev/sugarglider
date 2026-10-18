import Testing
import SwiftUI
@testable import Sugarglider

extension SugargliderTests {
    @Test func fractionMapsValueAcrossTheRange() {
        #expect(TintedSlider.fraction(of: 2, in: 2...48) == 0)
        #expect(TintedSlider.fraction(of: 48, in: 2...48) == 1)
        #expect(TintedSlider.fraction(of: 25, in: 2...48) == 0.5)
    }

    @Test func fractionClampsOutOfRangeValues() {
        #expect(TintedSlider.fraction(of: -10, in: 2...48) == 0)
        #expect(TintedSlider.fraction(of: 100, in: 2...48) == 1)
        #expect(TintedSlider.fraction(of: 5, in: 5...5) == 0)
    }

    @Test func valueAtXHitsBothEndsExactly() {
        let knob = TintedSlider.knobWidth
        let width = 200 + knob
        #expect(TintedSlider.value(atX: knob / 2, trackWidth: width, range: 2...48, step: 2) == 2)
        #expect(TintedSlider.value(atX: width - knob / 2, trackWidth: width, range: 2...48, step: 2) == 48)
    }

    @Test func valueAtXClampsOutsideTheTrack() {
        #expect(TintedSlider.value(atX: -50, trackWidth: 220, range: 2...48, step: 2) == 2)
        #expect(TintedSlider.value(atX: 999, trackWidth: 220, range: 2...48, step: 2) == 48)
    }

    @Test func valueAtXSnapsToStep() {
        let knob = TintedSlider.knobWidth
        let width = 200 + knob
        // Halfway along is 25, off the 2-hour grid.
        let mid = TintedSlider.value(atX: knob / 2 + 100, trackWidth: width, range: 2...48, step: 2)
        #expect(mid == 26)

        let free = TintedSlider.value(atX: knob / 2 + 100, trackWidth: width, range: 2...48, step: 0)
        #expect(abs(free - 25) < 0.0001)
    }

    @Test func valueAtXSurvivesAZeroWidthTrack() {
        let value = TintedSlider.value(atX: 0, trackWidth: 0, range: 2...48, step: 2)
        #expect((2...48).contains(value))
    }
}
