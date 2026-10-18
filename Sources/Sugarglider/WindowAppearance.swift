import SwiftUI
import AppKit

extension View {
    /// Applies the theme to the hosting `NSWindow`, which retints AppKit dynamic colors too. Only for
    /// the dropdown: its panel ignores `preferredColorScheme`, while SwiftUI resets a manual appearance
    /// on the Settings window. `NSApp.appearance` would also retint the status item, which has to
    /// follow the menu bar.
    func windowTheme(_ theme: AppSettings.Theme) -> some View {
        // Zero-sized because ImageRenderer draws an NSViewRepresentable as a yellow placeholder.
        background(WindowThemeApplier(appearance: theme.nsAppearance).frame(width: 0, height: 0))
    }
}

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
