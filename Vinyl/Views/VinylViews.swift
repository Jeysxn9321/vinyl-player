import SwiftUI

struct VinylDisc: View {
    var color: Color = .black
    var label: UIImage?
    var title: String = ""
    var labelScale: CGFloat = 0.34
    var pattern: VinylPattern = .plain
    var dust = false
    var labelStyle: LabelStyle = .artwork
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(color)
                PatternLayer(pattern: pattern).clipShape(Circle())
                Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: max(1.5, s * 0.006))   // bright outer edge
                Circle().inset(by: s * 0.03).stroke(Color.black.opacity(0.35), lineWidth: s * 0.03)   // smooth lead-in band
                ForEach(0..<34, id: \.self) { i in
                    Circle().inset(by: s * (0.075 + CGFloat(i) * 0.0125))
                        .stroke(Color.white.opacity(i % 6 == 0 ? 0.30 : (i % 2 == 0 ? 0.11 : 0.05)), lineWidth: i % 6 == 0 ? 1.2 : 0.7)
                }
                ForEach(0..<3, id: \.self) { i in   // darker gaps between tracks
                    Circle().inset(by: s * (0.2 + CGFloat(i) * 0.09))
                        .stroke(Color.black.opacity(0.45), lineWidth: s * 0.012)
                }
                if dust { DustLayer().clipShape(Circle()) }
                Group {
                    if labelStyle == .artwork, let label { Image(uiImage: label).resizable().scaledToFill() }
                    else if labelStyle == .artwork { Color.gray }
                    else { Circle().fill(color).overlay(Circle().fill(Color.white.opacity(0.28))) }
                }
                .frame(width: s * labelScale, height: s * labelScale).clipShape(Circle())
                if labelStyle == .text {
                    Text(title).font(.system(size: s * labelScale * 0.12, weight: .bold)).multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.6)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(width: s * labelScale * 0.7).offset(y: s * labelScale * 0.2)
                } else {
                    Text(title).font(.system(size: s * labelScale * 0.082, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 1)
                        .frame(width: s * labelScale * 0.76).offset(y: s * labelScale * 0.25)
                }
                Circle().fill(.black).frame(width: s * 0.04)
            }
            .frame(width: s, height: s)
            .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ArmBase: View {
    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [Color(white: 0.92), Color(white: 0.35), Color(white: 0.85), Color(white: 0.3), Color(white: 0.92)], center: .center))
            Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5)
            Circle().stroke(Color.black.opacity(0.35), lineWidth: 2).padding(10)
            Circle().fill(RadialGradient(colors: [Color(white: 0.85), Color(white: 0.3)], center: .topLeading, startRadius: 0, endRadius: 40)).padding(18)
        }
    }
}

private struct Headshell: View {
    var w: CGFloat
    var glow: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 1)
            Circle().fill(glow.opacity(0.9)).frame(width: w * 0.2, height: w * 0.2).offset(y: -w * 0.15)
            Capsule().fill(Color.white).frame(width: w * 0.1, height: w * 0.2)
                .shadow(color: glow, radius: 5).shadow(color: glow, radius: 12)
                .offset(y: w * 0.55)
        }
    }
}

struct Tonearm: View {
    var playing: Bool
    var length: CGFloat = 200
    var playAngle: Double = 24
    var glow: Color = .white   // stylus glow
    /// Drag the arm onto the record to start, off it to stop. Called with the wanted playing state.
    var onSet: ((Bool) -> Void)? = nil
    @State private var drag: Double?   // live angle while the finger is down
    private let restAngle = 4.0
    var body: some View {
        let w = length * 0.16
        let W = w * 2.2, H = length + w * 2, cx = W / 2
        let by = w * 1.1   // base centre y
        let silver = LinearGradient(colors: [Color(white: 0.95), Color(white: 0.55), Color(white: 0.9)], startPoint: .leading, endPoint: .trailing)
        let arm = Path { p in
            p.move(to: CGPoint(x: cx, y: by))
            p.addLine(to: CGPoint(x: cx, y: w + length * 0.62))
            p.addCurve(to: CGPoint(x: cx - w * 0.62, y: w + length * 0.98),
                       control1: CGPoint(x: cx, y: w + length * 0.84),
                       control2: CGPoint(x: cx - w * 0.62, y: w + length * 0.8))
        }
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: W, height: H)
            // Chrome tube: leaves the base, runs down, bends in toward the record at the end.
            arm.stroke(Color(white: 0.12), style: StrokeStyle(lineWidth: max(5, w * 0.24), lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.6), radius: 5, x: 3, y: 4)
            arm.stroke(silver, style: StrokeStyle(lineWidth: max(4, w * 0.19), lineCap: .round, lineJoin: .round))
            arm.stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: max(1, w * 0.04), lineCap: .round, lineJoin: .round))
            // Small angled headshell with a glowing stylus tip.
            Headshell(w: w, glow: glow)
                .frame(width: w * 0.5, height: w * 1.0)
                .rotationEffect(.degrees(-24))
                .offset(x: cx - w * 0.62 - w * 0.25, y: w + length * 0.98 - w * 0.1)
            // Big round brushed-metal base.
            ArmBase()
                .frame(width: W, height: W)
                .shadow(color: .black.opacity(0.7), radius: 10, y: 5)
                .offset(x: 0, y: by - W / 2)
            Circle().fill(Color(white: 0.12)).frame(width: w * 0.35, height: w * 0.35)
                .offset(x: cx - w * 0.175, y: by - w * 0.175)
        }
        .frame(width: W, height: H, alignment: .top)
        .contentShape(Rectangle())
        .rotationEffect(.degrees(drag ?? (playing ? playAngle : restAngle)), anchor: .init(x: 0.5, y: w * 1.1 / (length + w * 2)))
        .animation(drag == nil ? .spring(response: 1.0, dampingFraction: 0.8) : nil, value: drag)
        .animation(.spring(response: 1.0, dampingFraction: 0.8), value: playing)
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { g in
                let base = playing ? playAngle : restAngle
                // Swinging the tip left (dragging left) lowers it onto the record.
                drag = min(max(base - Double(g.translation.width) / Double(length) * 57, restAngle), playAngle + 2)
            }
            .onEnded { _ in
                let want = (drag ?? restAngle) > (restAngle + playAngle) / 2
                drag = nil
                if want != playing { onSet?(want) }
            }, including: onSet == nil ? .none : .all)
    }
}

/// Rotation is derived from accumulated play time, so UI refreshes never reset it.
struct SpinningDisc: View {
    var playing: Bool
    var color: Color
    var label: UIImage?
    var title: String = ""
    var labelScale: CGFloat = 0.34
    @AppStorage(Pref.pattern) private var pattern = VinylPattern.plain.rawValue
    @AppStorage(Pref.fxSheen) private var sheen = true
    @AppStorage(Pref.fxGlow) private var glow = false
    @AppStorage(Pref.fxDust) private var dust = false
    @AppStorage(Pref.labelStyle) private var labelStyle = LabelStyle.artwork.rawValue
    @AppStorage(Pref.labelSize) private var labelSize = LabelSize.medium.rawValue
    /// Portrait passes the real title but only shows it on the label for the "Title" style.
    var inlineTitle = true
    private let period = 3.6   // seconds per revolution (slowed from 1.8, which looked too fast)
    @State private var accumulated = 0.0   // seconds of spin before current run
    @State private var runStart: Date?

    var body: some View {
        TimelineView(.animation(paused: !playing)) { tl in
            let run = runStart.map { tl.date.timeIntervalSince($0) } ?? 0
            VinylDisc(color: color, label: label,
                      title: (inlineTitle || labelStyle == LabelStyle.text.rawValue) ? title : "",
                      labelScale: (LabelSize(rawValue: labelSize) ?? .medium).scaled(labelScale),
                      pattern: VinylPattern(rawValue: pattern) ?? .plain, dust: dust,
                      labelStyle: LabelStyle(rawValue: labelStyle) ?? .artwork)
                .rotationEffect(.degrees(((accumulated + run) / period).truncatingRemainder(dividingBy: 1) * 360))
        }
        // Light reflections stay fixed while the record turns.
        .overlay {
            if sheen {
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.34), .clear, .clear, .white.opacity(0.26), .clear], center: .center))
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: glow ? color.opacity(0.9) : .clear, radius: glow ? 36 : 0)
        .onChange(of: playing) { _, p in
            if p { runStart = Date() }
            else if let s = runStart { accumulated += Date().timeIntervalSince(s); runStart = nil }
        }
        .onAppear { if playing { runStart = Date() } }
    }
}
