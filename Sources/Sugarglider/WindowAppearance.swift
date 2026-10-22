import SwiftUI
import AppKit

extension View {
    /// Glass, or the window color over the glass. The glass clips its content to its own shape, so the solid
    /// color keeps the round corners. `containerBackground(_:for: .window)` has no effect on this panel.
    func dropdownBackground(_ background: AppSettings.DropdownBackground) -> some View {
        self.background {
            if background == .solid { Color(nsColor: .windowBackgroundColor) }
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
