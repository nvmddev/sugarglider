import SwiftUI
import AppKit

extension View {
    /// Applies the theme override to the hosting `NSWindow.appearance`, nil
    /// meaning follow the system. This is the mechanism the
    /// `MenuBarExtra(.window)` dropdown needs, and only that one:
    ///
    /// - The borderless panel `MenuBarExtra(.window)` creates ignores
    ///   `preferredColorScheme` entirely.
    /// - The window appearance retints everything consistently, including the
    ///   AppKit dynamic colors (`.labelColor`, `.separatorColor`) the chart
    ///   draws with. An environment-only override leaves those resolving
    ///   against the system appearance.
    /// - `NSApp.appearance` is deliberately not set: it would also retint the
    ///   status-bar item, which has to follow the menu bar to stay legible.
    ///
    /// It does not work for the `Settings` window. SwiftUI manages that one's
    /// appearance itself and resets a manual override milliseconds after it's
    /// applied (verified via KVO on macOS 26), so Settings goes through
    /// `preferredColorScheme` and lets SwiftUI set the appearance.
    func windowTheme(_ theme: AppSettings.Theme) -> some View {
        // The zero frame matters: ImageRenderer rasterises an
        // NSViewRepresentable as a yellow "prohibited" placeholder rather than
        // as nothing, and a full-bleed one sat behind every off-screen render
        // (scripts/ReadmeArt.swift, the ChartCanvas smoke tests). The applier
        // only has to be in the tree to find its window.
        background(WindowThemeApplier(appearance: theme.nsAppearance).frame(width: 0, height: 0))
    }
}

/// Forwards the desired appearance to whatever window it ends up in. Re-applied
/// on window attach, since the dropdown's content view is recreated every time
/// it opens, and on every theme change.
private struct WindowThemeApplier: NSViewRepresentable {
    var appearance: NSAppearance?

    func makeNSView(context: Context) -> ApplierView { ApplierView() }

    func updateNSView(_ view: ApplierView, context: Context) {
        view.desired = appearance
    }

    final class ApplierView: NSView {
        var desired: NSAppearance? {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window, window.appearance?.name != desired?.name else { return }
            window.appearance = desired
        }
    }
}
