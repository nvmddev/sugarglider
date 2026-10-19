import SwiftUI
import AppKit

extension View {
    /// Applies the theme to the hosting `NSWindow`, which retints AppKit dynamic colors too. Only for
    /// the dropdown: its panel ignores `preferredColorScheme`, while SwiftUI resets a manual appearance
    /// on the Settings window. `NSApp.appearance` would also retint the status item, which has to
    /// follow the menu bar.
    func windowTheme(_ theme: AppSettings.Theme) -> some View {
        let appearance = theme.nsAppearance
        return hostingWindow { window in
            if window.appearance?.name != appearance?.name { window.appearance = appearance }
        }
    }

    /// AppKit shows a window's tooltips only while its app is active, unless the window opts in, and the
    /// dropdown opens over whichever app is in front.
    func windowShowsToolTipsWhenInactive() -> some View {
        hostingWindow { $0.allowsToolTipsWhenApplicationIsInactive = true }
    }

    // Zero-sized because ImageRenderer draws an NSViewRepresentable as a yellow placeholder.
    private func hostingWindow(_ configure: @escaping (NSWindow) -> Void) -> some View {
        background(WindowConfigurator(configure: configure).frame(width: 0, height: 0))
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }

    func updateNSView(_ view: ConfiguratorView, context: Context) {
        view.configure = configure
    }

    final class ConfiguratorView: NSView {
        var configure: ((NSWindow) -> Void)? {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            if let window { configure?(window) }
        }
    }
}
