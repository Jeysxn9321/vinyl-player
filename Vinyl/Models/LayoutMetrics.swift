import CoreGraphics

/// Breakpoints taken from the Atrium web app's iPhone Duo handling (width/height based, not device-model based).
/// The Duo's real point sizes are NOT confirmed; these thresholds only decide the layout shape.
struct LayoutMetrics: Equatable {
    enum Shape { case portrait, wide, outerSideways }
    var shape: Shape
    var recordSide: CGFloat
    var showsProgress: Bool

    init(size: CGSize) {
        let w = size.width, h = size.height
        if w <= h {
            shape = .portrait
            recordSide = min(w * 0.9 / 2.0, h * 0.4)
            showsProgress = true
        } else if h <= 420 {
            // Outer screen held sideways (Atrium: max-height 420/560): shrink and drop the progress row.
            shape = .outerSideways
            recordSide = min(w * 0.92 / 1.82, h * 0.86)
            showsProgress = false
        } else {
            shape = .wide
            recordSide = min(w * 0.92 / 1.82, h * 0.86)
            showsProgress = true
        }
    }
}
