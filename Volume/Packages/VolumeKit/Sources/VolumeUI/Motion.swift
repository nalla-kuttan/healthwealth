import SwiftUI

/// Motion at resting heart rate: timings come from a beat of about 60 bpm. Nothing bounces,
/// nothing throws confetti. With Reduce Motion on, every view here shows its final state at once.
public enum Motion {
    /// One beat at ~60 bpm.
    public static let beat: Double = 1.0
    /// The year inks in, column by column.
    public static let build: Double = 0.9
    /// Medal ring stamping in: slight overshoot, like a coin press.
    public static let stamp = Animation.timingCurve(0.2, 0.9, 0.3, 1.2, duration: 0.24)
    /// Cell tap: inspector content crossfade.
    public static let crossfade = Animation.easeInOut(duration: 0.18)
    /// Readiness bars fill from zero.
    public static let fill = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.6)
    /// Cards rising into place on first load.
    public static let rise = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.5)

    /// A single heartbeat waveform over t ∈ [0, 1): P wave, QRS complex, T wave.
    public static func ecg(_ t: Double) -> Double {
        let t = t - t.rounded(.down)
        func g(_ c: Double, _ w: Double, _ a: Double) -> Double { a * exp(-((t - c) * (t - c)) / (2 * w * w)) }
        return g(0.12, 0.025, 0.12) + g(0.2, 0.008, -0.15) + g(0.225, 0.011, 1) + g(0.252, 0.009, -0.25)
            + g(0.42, 0.045, 0.22)
    }
}

// MARK: - Stamp & rise

public extension AnyTransition {
    /// Medal ring arriving: scales down from 1.35× while fading in.
    static var stamp: AnyTransition {
        .scale(scale: 1.35).combined(with: .opacity)
    }
}

private struct RiseIn: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isShown || reduceMotion ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !reduceMotion, !isShown else { return }
                withAnimation(Motion.rise.delay(0.08 * Double(index))) { isShown = true }
            }
    }
}

public extension View {
    /// Rises 14 pt and fades in on first appearance, staggered by `index`.
    func riseIn(_ index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

// MARK: - Counting number

/// A number that counts up through its intermediate values when animated.
public struct CountingText: View, Animatable {
    var value: Double
    var format: @Sendable (Double) -> String

    public init(_ value: Double, format: @escaping @Sendable (Double) -> String = { "\(Int($0.rounded()))" }) {
        self.value = value
        self.format = format
    }

    public nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    public var body: some View {
        Text(format(value)).monospacedDigit()
    }
}

/// Counts from zero to `value` on first appearance, then rolls digits on later changes.
public struct CountUp: View {
    var value: Int
    var duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var didAppear = false

    public init(_ value: Int, duration: Double = Motion.build) {
        self.value = value
        self.duration = duration
    }

    public var body: some View {
        CountingText(shown)
            .accessibilityLabel("\(value)")
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                if reduceMotion { shown = Double(value); return }
                withAnimation(.timingCurve(0.2, 0.6, 0.2, 1, duration: duration)) { shown = Double(value) }
            }
            .onChange(of: value) { _, new in
                withAnimation(reduceMotion ? nil : Motion.fill) { shown = Double(new) }
            }
    }
}

// MARK: - Pulse rule

/// The pulse rule: a heart-rate trace used as a divider and loading line. While `isLive`, a rose
/// highlight sweeps along it; each change of `beat` sends one sweep (a new workout landed).
public struct PulseRule: View {
    var beat: Int
    var isLive: Bool
    var color: Color
    var highlight: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepStart: Date?

    public init(beat: Int = 0, isLive: Bool = false, color: Color = Theme.rule, highlight: Color = Theme.rose) {
        self.beat = beat
        self.isLive = isLive
        self.color = color
        self.highlight = highlight
    }

    private static let tile: CGFloat = 180
    private static let sweep: Double = 1.1

    public var body: some View {
        let animating = !reduceMotion && (isLive || sweepStart != nil)
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !animating)) { context in
            Canvas { gc, size in
                let path = Self.trace(width: size.width, height: size.height)
                gc.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                guard animating, let head = headX(at: context.date, width: size.width) else { return }
                let tail: CGFloat = 140
                var lit = gc
                lit.clip(to: Path(CGRect(x: head - tail, y: 0, width: tail, height: size.height)))
                lit.stroke(path,
                           with: .linearGradient(Gradient(colors: [highlight.opacity(0), highlight]),
                                                 startPoint: CGPoint(x: head - tail, y: 0),
                                                 endPoint: CGPoint(x: head, y: 0)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
        .onChange(of: beat) { _, _ in
            guard !reduceMotion else { return }
            sweepStart = .now
            Task {
                try? await Task.sleep(for: .seconds(Self.sweep + 0.05))
                sweepStart = nil
            }
        }
    }

    /// Head of the highlight in points, or nil when no sweep is running.
    private func headX(at date: Date, width: CGFloat) -> CGFloat? {
        let run = width + 140
        if let sweepStart {
            let p = date.timeIntervalSince(sweepStart) / Self.sweep
            guard p <= 1 else { return nil }
            return CGFloat(1 - pow(1 - p, 2)) * run
        }
        guard isLive else { return nil }
        // Loop at resting heart rate: one pass every 1.6 beats.
        let p = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Motion.beat * 1.6) / (Motion.beat * 1.6)
        return CGFloat(p) * run
    }

    /// Repeating 180 pt tile, the same trace as the design plan's pulse rule.
    static func trace(width: CGFloat, height: CGFloat) -> Path {
        let s = height / 28
        var path = Path()
        var x0: CGFloat = 0
        path.move(to: CGPoint(x: 0, y: 18 * s))
        while x0 < width {
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x, y: y * s) }
            path.addLine(to: p(50, 18))
            path.addQuadCurve(to: p(62, 18), control: p(56, 12))
            path.addLine(to: p(78, 18))
            path.addLine(to: p(82, 22))
            path.addLine(to: p(88, 2))
            path.addLine(to: p(94, 24))
            path.addLine(to: p(98, 18))
            path.addLine(to: p(120, 18))
            path.addQuadCurve(to: p(138, 18), control: p(129, 9))
            path.addLine(to: p(180, 18))
            x0 += tile
        }
        return path
    }
}

// MARK: - Guilloche rosette

/// Guilloche rosette whose rings are modulated by a heart-rate waveform, drifting slowly.
/// For first run, loading and other moments worth keeping; never behind data.
public struct GuillocheRosette: View {
    var rings: Int
    var fixedPhase: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter phase: draw one still frame at this phase (for images and share cards).
    public init(rings: Int = 36, phase: Double? = nil) {
        self.rings = rings
        self.fixedPhase = phase
    }

    public var body: some View {
        if let fixedPhase {
            Canvas { gc, size in draw(in: &gc, size: size, phase: fixedPhase) }
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            animated
        }
    }

    private var animated: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) * 0.36
            // Drawn off the main thread so a drifting rosette never delays a tap.
            Canvas(rendersAsynchronously: true) { gc, size in
                draw(in: &gc, size: size, phase: phase)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, phase: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r0 = Double(min(size.width, size.height)) * 0.36
        let steps = 240
        let highlighted = Int((Double(rings) * 0.62).rounded())

        for i in 0..<rings {
            var path = Path()
            for s in 0...steps {
                let th = Double(s) / Double(steps) * 2 * .pi
                let r = r0 * (0.6 + 0.5 * Double(i) / Double(rings))
                    + r0 * 0.055 * sin(18 * th + Double(i) * 0.36 + phase)
                    + r0 * 0.17 * Motion.ecg(th / (2 * .pi) * 6 + phase * 0.03 + Double(i) * 0.002)
                let pt = CGPoint(x: c.x + r * cos(th), y: c.y + r * sin(th))
                s == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            if i == highlighted {
                gc.stroke(path, with: .color(Theme.rose), lineWidth: 1.6)
            } else {
                gc.stroke(path, with: .color(Theme.ink.opacity(0.28)), lineWidth: 0.6)
            }
        }

        for k in 0..<12 {
            var path = Path()
            for s in 0...steps {
                let th = Double(s) / Double(steps) * 2 * .pi
                let r = r0 * 0.42 * (1 + 0.22 * sin(7 * th + Double(k) * 0.22 + phase * 0.5))
                let a = th + Double(k) * 0.045
                let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                s == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            gc.stroke(path, with: .color(Theme.intaglio.opacity(0.5)), lineWidth: 0.6)
        }
    }
}

// MARK: - Today's beat

/// A soft ripple that leaves today's cell twice per cycle (lub-dub), every four beats.
public struct TodayBeat: View {
    var size: CGFloat
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat, cornerRadius: CGFloat) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Motion.beat * 4)
                ZStack {
                    ripple(progress: t / 0.9)
                    ripple(progress: (t - 0.22) / 0.9)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func ripple(progress: Double) -> some View {
        if progress >= 0, progress <= 1 {
            let eased = 1 - pow(1 - progress, 3)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Theme.rose, lineWidth: 1.2)
                .frame(width: size, height: size)
                .scaleEffect(1 + 0.7 * eased)
                .opacity(0.55 * (1 - progress))
        }
    }
}

// MARK: - Stamp in on appear

private struct StampIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isShown || reduceMotion ? 1 : 1.35)
            .opacity(isShown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion, !isShown else { return }
                withAnimation(Motion.stamp.delay(delay)) { isShown = true }
            }
    }
}

public extension View {
    /// Stamps in like a struck medal (1.35× → 1×, 240 ms) on first appearance.
    func stampIn(delay: Double = 0) -> some View { modifier(StampIn(delay: delay)) }
}
