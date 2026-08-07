import SwiftUI

/// Draws the dark halo that keeps light text readable over glass.
///
/// Applied to text-bearing views rather than the window, so it darkens the
/// area immediately around the letterforms and leaves the rest of the frosted
/// background alone.
private struct LegibilityShadow: ViewModifier {
    let tint: TintStyle

    func body(content: Content) -> some View {
        content
            .shadow(color: Theme.shadowColour(tint), radius: Theme.shadowTightRadius)
            .shadow(color: Theme.shadowColour(tint).opacity(0.75),
                    radius: Theme.shadowSoftRadius)
    }
}

extension View {
    func legibilityShadow(_ tint: TintStyle) -> some View {
        modifier(LegibilityShadow(tint: tint))
    }
}
