import SwiftUI

/// Usage-limit progress bar drawn in a single `Canvas` as a row of fine ticks.
///
/// Why a single Canvas: it paints track, fill, warning markers and the pace tip
/// in one pass with plain Core Graphics — no SwiftUI `.blendMode` /
/// `.compositingGroup` modifiers, which trigger the macOS 26 Metal shader crash
/// (CodexBar issue #805). All compositing stays inside the Canvas.
///
/// Filled ticks show progress; muted ticks show the remaining track. Keeping all
/// drawing in one Canvas avoids SwiftUI blend/compositing effects that can crash
/// on macOS 26. The optional pace marker remains layered over the tick rail.
struct UsageLimitBar: View, Animatable {
    /// Filled portion, 0...100, already adjusted for used/remaining mode.
    var percent: Double

    /// Interpolates `percent` so fill changes animate when the caller attaches
    /// `.animation(_:value:)` — Canvas alone doesn't tween its inputs.
    var animatableData: Double {
        get { percent }
        set { percent = newValue }
    }
    /// Fill color (the unified green→amber→red threshold color).
    let fillColor: Color
    /// Pace position, 0...100 in the same display space as `percent`; `nil` hides the tip.
    let pacePercent: Double?
    /// True when ahead of pace (deficit) → red stripe; false → green.
    let paceOver: Bool

    var height: CGFloat = 8
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let scale = max(displayScale, 1)
            let align: (CGFloat) -> CGFloat = { ($0 * scale).rounded() / scale }
            let rect = CGRect(origin: .zero, size: size)
            context.clip(to: Path(rect))

            // Draw a dense rail of rounded vertical ticks. Aligning their
            // origins to the display scale keeps the fine marks crisp.
            let clamped = min(100, max(0, percent))
            let fillWidth = size.width * clamped / 100
            let tickWidth = align(4.0)
            let tickStep = align(6.0)
            let tickCorner = CGSize(width: align(1.0), height: align(1.0))
            // Only draw complete ticks. A partial final tick gets clipped by
            // the Canvas bounds and looks like the bar is covering it.
            let tickCount = size.width >= tickWidth
                ? Int(floor((size.width - tickWidth) / tickStep)) + 1
                : 0
            let railWidth = tickCount > 0
                ? CGFloat(tickCount - 1) * tickStep + tickWidth
                : 0
            let leadingInset = max(0, (size.width - railWidth) / 2)
            var track = Path()
            var fill = Path()

            for index in 0..<tickCount {
                let x = align(leadingInset + CGFloat(index) * tickStep)
                let width = tickWidth
                guard width > 0 else { continue }
                let tick = CGRect(x: x, y: 0, width: width, height: size.height)
                track.addRoundedRect(in: tick, cornerSize: tickCorner)
                if x < fillWidth {
                    fill.addRoundedRect(in: tick, cornerSize: tickCorner)
                }
            }

            context.fill(track, with: .color(Color.limitTrack))
            context.fill(fill, with: .color(fillColor))

            // Pace tip: punch a small gap, then draw a colored center stripe in it.
            if let pacePercent {
                let x = align(size.width * min(100, max(0, pacePercent)) / 100)
                let punchWidth = align(6)
                let stripeWidth = align(2)
                let extend = size.height

                let gap = CGRect(x: x - punchWidth / 2, y: -extend, width: punchWidth, height: size.height + extend * 2)
                context.blendMode = .destinationOut
                context.fill(Path(gap), with: .color(.white))
                context.blendMode = .normal

                let stripe = CGRect(x: x - stripeWidth / 2, y: 0, width: stripeWidth, height: size.height)
                context.fill(Path(stripe), with: .color(paceOver ? Self.deficitColor : Self.onPaceColor))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private static let onPaceColor = Color(.sRGB, red: 0.20, green: 0.72, blue: 0.40, opacity: 1.0)
    private static let deficitColor = Color(.sRGB, red: 0.90, green: 0.30, blue: 0.30, opacity: 1.0)
}
