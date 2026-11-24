import SwiftUI

struct VinylDisc: View {
    var color: Color = .black
    var label: UIImage?
    var title: String = ""
    var labelScale: CGFloat = 0.34
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(color)
                ForEach(0..<28, id: \.self) { i in
                    Circle().inset(by: s * (0.2 + CGFloat(i) * 0.0165))
                        .stroke(Color.white.opacity(i % 3 == 0 ? 0.07 : 0.03), lineWidth: 0.6)
                }
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.12), .clear], center: .center))
                Group {
                    if let label { Image(uiImage: label).resizable().scaledToFill() } else { Color.gray }
                }
                .frame(width: s * labelScale, height: s * labelScale).clipShape(Circle())
                Text(title).font(.system(size: s * 0.028, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 1)
                    .frame(width: s * 0.26).offset(y: s * 0.085)
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
        .rotationEffect(.degrees(playing ? playAngle : 4), anchor: .init(x: 0.5, y: w / (length + w * 2)))
        .animation(.spring(response: 1.0, dampingFraction: 0.8), value: playing)
    }
}

/// Rotation is derived from accumulated play time, so UI refreshes never reset it.
struct SpinningDisc: View {
    var playing: Bool
    var color: Color
    var label: UIImage?
    var title: String = ""
    var labelScale: CGFloat = 0.34
    private let period = 1.8   // seconds per revolution
    @State private var accumulated = 0.0   // seconds of spin before current run
    @State private var runStart: Date?

    var body: some View {
        TimelineView(.animation(paused: !playing)) { tl in
            let run = runStart.map { tl.date.timeIntervalSince($0) } ?? 0
            VinylDisc(color: color, label: label, title: title, labelScale: labelScale)
                .rotationEffect(.degrees(((accumulated + run) / period).truncatingRemainder(dividingBy: 1) * 360))
        }
        .onChange(of: playing) { _, p in
            if p { runStart = Date() }
            else if let s = runStart { accumulated += Date().timeIntervalSince(s); runStart = nil }
        }
        .onAppear { if playing { runStart = Date() } }
    }
}
