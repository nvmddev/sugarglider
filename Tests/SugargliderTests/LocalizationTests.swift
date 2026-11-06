import Testing
import Foundation
@testable import Sugarglider

extension SugargliderTests {
    /// The expectations are English. The scheme runs the test host in English, so they hold on a
    /// Mac set to German too.
    @Test func testsRunInEnglish() {
        #expect(Bundle.main.preferredLocalizations.first == "en")
    }

    /// The German table is compiled into the app, and strings with values put them in place.
    @Test func germanIsBundled() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        #expect(String(localized: "LOW", bundle: german) == "TIEF")
        #expect(String(localized: "Reading from \("vor 3 Minuten")", bundle: german) == "Messwert: vor 3 Minuten")
        #expect(String(localized: "\("1,20") U/h", bundle: german) == "1,20 IE/h")
        #expect(String(localized: "Version \("1.2.0") (\("7"))", bundle: german) == "Version 1.2.0 (7)")
        #expect(String(localized: "\(3) to \(300) \("Sekunden")", bundle: german) == "3 bis 300 Sekunden")
    }

    @Test func germanNamesTheTimeInRange() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        #expect(String(localized: "Time in range (\("6h"))", bundle: german) == "Zielbereich (6h)")
        #expect(String(localized: "Low \("4 %")", bundle: german) == "Tief 4 %")
        #expect(String(localized: "In range \("78 %")", bundle: german) == "Im Ziel 78 %")
        #expect(String(localized: "Time in range over the last \("6 Stunden")", bundle: german)
                == "Zeit im Zielbereich in den letzten 6 Stunden")
    }

    /// German abbreviates the label; VoiceOver must still hear the words.
    @Test func germanSpellsOutTheAverageForVoiceOver() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        #expect(String(localized: "Average glucose", bundle: german) == "Ø Glukosewert")
        #expect(String(localized: "Average glucose (spoken)", defaultValue: "Average glucose", bundle: german)
                == "Durchschnittlicher Glukosewert")
    }
}
