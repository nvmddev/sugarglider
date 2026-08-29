import SwiftUI

/// The status-bar item's title: the value, an enlarged trend arrow, the
/// bracketed delta if it's enabled for the bar, and once a reading goes stale
/// a warning glyph with its age.
struct MenuBarLabel: View {
    var settings: AppSettings
    var store: ReadingStore

    var body: some View {
        Group {
            if !settings.isConfigured {
                Text("CGM ⚙")
            } else if let r = store.lastReading {
                barText(r)
            } else if store.lastError != nil {
                Text("CGM ⚠")
            } else {
                Text("CGM …")
            }
        }
        .font(.system(size: 13, design: .monospaced))
    }

    private func barText(_ r: Reading) -> Text {
        var t = Text(r.text(in: settings.units)).font(.system(size: 13, design: .monospaced))
        if !r.trendArrow.isEmpty {
            t = t + Text(" \(r.trendArrow)").font(.system(size: 15, weight: .medium))
        }
        if settings.deltaDisplay == .menuAndStatusBar, let delta = store.deltaText() {
            t = t + Text("  (\(delta))").font(.system(size: 13, design: .monospaced))
        }
        // The age, not just a glyph: it's what distinguishes a blip from a feed
        // that stopped. This is the only escalation there is. The app never
        // notifies, because short gaps are normal and it only sees the
        // Nightscout site, so it can't tell a sensor gap from a network one.
        if store.isStale {
            t = t + Text(" ⚠ \(ReadingStore.compactAge(r.date))").font(.system(size: 13, design: .monospaced))
        }
        return t
    }
}
