import SwiftUI

enum VinylPattern: String, CaseIterable {
    case plain, splatter, marble, swirl
    var title: String { rawValue.capitalized }
}

enum AppTheme: String, CaseIterable {
    case auto, midnight, ember, ocean, forest, mono
    var title: String { self == .auto ? "From artwork" : rawValue.capitalized }
    var colors: [Color]? {
        switch self {
        case .auto: return nil
        case .midnight: return [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.10, green: 0.08, blue: 0.28)]
        case .ember: return [Color(red: 0.16, green: 0.03, blue: 0.02), Color(red: 0.42, green: 0.14, blue: 0.04)]
        case .ocean: return [Color(red: 0.01, green: 0.10, blue: 0.14), Color(red: 0.03, green: 0.30, blue: 0.34)]
        case .forest: return [Color(red: 0.02, green: 0.09, blue: 0.05), Color(red: 0.10, green: 0.26, blue: 0.13)]
        case .mono: return [Color(white: 0.03), Color(white: 0.16)]
        }
    }
}

/// Deterministic generator so patterns look the same every frame and every launch.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Pattern drawn on the record body, under the grooves. Clipped to the disc by the caller.
struct PatternLayer: View {
    var pattern: VinylPattern
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            switch pattern {
            case .plain:
                Color.clear
            case .splatter:
                Canvas { ctx, size in
                    var rng = SeededRNG(state: 42)
                    let palette: [Color] = [Color.white.opacity(0.55), Color.white.opacity(0.3), Color(white: 0.9).opacity(0.45)]
                    for _ in 0..<46 {
                        let r = CGFloat.random(in: 0.006...0.05, using: &rng) * size.width
                        let x = CGFloat.random(in: 0.04...0.96, using: &rng) * size.width
                        let y = CGFloat.random(in: 0.04...0.96, using: &rng) * size.height
                        let c = palette[Int.random(in: 0..<palette.count, using: &rng)]
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c))
                    }
                }
            case .marble:
                Canvas { ctx, size in
                    var rng = SeededRNG(state: 7)
                    for i in 0..<9 {
                        let w = CGFloat.random(in: 0.5...1.0, using: &rng) * size.width
                        let h = CGFloat.random(in: 0.05...0.16, using: &rng) * size.height
                        let x = CGFloat.random(in: -0.1...0.5, using: &rng) * size.width
                        let y = CGFloat.random(in: 0.0...1.0, using: &rng) * size.height
                        let base = Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
                        let t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                            .rotated(by: CGFloat(i) * 0.6)
                            .translatedBy(x: -size.width / 2, y: -size.height / 2)
                        ctx.fill(base.applying(t), with: .color(Color.white.opacity(i % 2 == 0 ? 0.28 : 0.14)))
                    }
                }.blur(radius: s * 0.03)
            case .swirl:
                AngularGradient(colors: [.clear, Color.white.opacity(0.35), .clear, Color.white.opacity(0.22),
                                         .clear, Color.white.opacity(0.35), .clear, Color.white.opacity(0.18)],
                                center: .center)
                    .blur(radius: s * 0.02)
            }
        }
    }
}

/// Sparse seeded scratches, drawn over the record body.
struct DustLayer: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(state: 99)
            for _ in 0..<26 {
                let r = CGFloat.random(in: 0.22...0.48, using: &rng) * size.width
                let a = CGFloat.random(in: 0...(2 * CGFloat.pi), using: &rng)
                let len = CGFloat.random(in: 0.04...0.18, using: &rng)
                var p = Path()
                p.addArc(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: r,
                         startAngle: .radians(Double(a)), endAngle: .radians(Double(a + len)), clockwise: false)
                ctx.stroke(p, with: .color(Color.white.opacity(0.18)), lineWidth: 0.6)
            }
        }
    }
}
