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
        // Zero-sized because ImageRenderer draws an NSViewRepresentable as a yellow placeholder.
        background(ToolTipsWhenInactive().frame(width: 0, height: 0))
    }
}

private struct ToolTipsWhenInactive: NSViewRepresentable {
    func makeNSView(context: Context) -> OptInView { OptInView() }

    func updateNSView(_ view: OptInView, context: Context) {}

    final class OptInView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.allowsToolTipsWhenApplicationIsInactive = true
        }
    }
}
