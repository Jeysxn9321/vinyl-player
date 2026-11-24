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
                ForEach(0..<28, id: \.self) { i in
                    Circle().inset(by: s * (0.2 + CGFloat(i) * 0.0165))
                        .stroke(Color.white.opacity(i % 3 == 0 ? 0.07 : 0.03), lineWidth: 0.6)
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

struct Tonearm: View {
    var playing: Bool
    var length: CGFloat = 200
    var playAngle: Double = 24
    /// Drag the arm onto the record to start, off it to stop. Called with the wanted playing state.
    var onSet: ((Bool) -> Void)? = nil
    @State private var drag: Double?   // live angle while the finger is down
    private let restAngle = 4.0
    var body: some View {
        let w = length * 0.16
        ZStack(alignment: .top) {
            Circle().fill(Color.white.opacity(0.08)).frame(width: w * 2.2)      // pivot base
            Capsule()                                                         // arm tube
                .fill(LinearGradient(colors: [.gray, .white.opacity(0.85), .gray], startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 0.22, height: length).offset(y: w)
            RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.15))        // headshell
                .frame(width: w * 0.6, height: w * 1.3).offset(y: length + w * 0.4)
            Circle().fill(Color(white: 0.2)).frame(width: w * 0.9)            // pivot cap
        }
        .frame(width: w * 2.2, height: length + w * 2, alignment: .top)
        .contentShape(Rectangle())
        .rotationEffect(.degrees(drag ?? (playing ? playAngle : restAngle)), anchor: .init(x: 0.5, y: w / (length + w * 2)))
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
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.12), .clear], center: .center))
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
