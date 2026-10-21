// Home's motion. Each animation says something: a magic packet going out, a PC answering,
// a launch being taken into account. They only run while Home is on screen (its window
// hides during a stream), none loops past the state it shows, and with Reduce Motion they
// fade instead of moving.

import SwiftUI

extension Animation {
    /// Routine state changes: banners, labels, colors.
    static let mvState = Animation.smooth(duration: 0.3)
    /// The selection ring moving between tiles, quick enough for key repeat.
    static let mvGlide = Animation.snappy(duration: 0.22)
}

/// Lit tiles come back from the left, one after the other, when their PC answers.
func mvWaveDelay(index: Int, reduceMotion: Bool) -> Double {
    reduceMotion ? 0 : Double(min(index, 12)) * 0.035
}

/// A PC's status dot. Each magic packet sends a ring out of it, and it pops when the PC
/// comes online.
struct MVStatusDot: View {
    let color: Color
    /// Magic packets sent so far: each new one sets off a ring.
    let packets: Int
    let online: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops = 0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .keyframeAnimator(initialValue: 1.0, trigger: pops) { dot, scale in
                dot.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.8, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
                }
            }
            .background {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .keyframeAnimator(initialValue: MVRipple(), trigger: packets) { [reduceMotion] ring, ripple in
                        ring.scaleEffect(ripple.scale).opacity(reduceMotion ? 0 : ripple.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(3.6, duration: 1.4)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0.8, duration: 0.06)
                            CubicKeyframe(0, duration: 1.34)
                        }
                    }
            }
            .animation(.mvState, value: color)
            .onChange(of: online) { _, isOnline in
                if isOnline, !reduceMotion { pops += 1 }
            }
            .accessibilityHidden(true)
    }
}

private struct MVRipple {
    var scale = 1.0
    var opacity = 0.0
}

/// The waking banner's icon: radio waves that sweep each time a magic packet goes out.
struct MVWakeWaves: View {
    /// Magic packets sent so far.
    let packets: Int
    @State private var sweeps = 0

    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 17))
            .foregroundStyle(.orange)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(3), value: sweeps)
            .frame(width: 22)
            // The first packet went out as the banner appeared
            .onAppear { sweeps += 1 }
            .onChange(of: packets) { sweeps += 1 }
            .accessibilityHidden(true)
    }
}

/// A launch starting: stars, moons and sparkles burst out of the tile, in its color and
/// moonlight yellow. The Canvas only exists for the burst's second, and Reduce Motion skips it.
struct MVLaunchBurst: View {
    /// Launches started so far: each new one sets off a burst.
    let trigger: Int
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: Date?
    @State private var sparks: [MVSpark] = []

    private static let duration = 0.95
    /// Points per second squared, pulling the sparks down as they fade.
    private static let gravity = 620.0
    private static let shapes = ["star.fill", "sparkle", "moon.fill", "circle.fill"]

    private var palette: [Color] {
        [color, mvAccentForeground, Color(hex: 0xFFCF5A)]
    }

    var body: some View {
        ZStack {
            if let burst {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(burst)
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for spark in sparks {
                            let t = elapsed - spark.delay
                            let life = t / Self.duration
                            guard t > 0, life < 1 else { continue }
                            guard let symbol = context.resolveSymbol(id: spark.symbol) else { continue }
                            var layer = context
                            // Full until 60 % of its life, then fading out
                            layer.opacity = life < 0.6 ? 1 : 1 - (life - 0.6) / 0.4
                            layer.translateBy(x: center.x + spark.offset.dx + spark.velocity.dx * t,
                                              y: center.y + spark.offset.dy + spark.velocity.dy * t + Self.gravity * t * t / 2)
                            layer.rotate(by: .radians(spark.spin * t))
                            let scale = spark.scale * min(1, t / 0.12)
                            layer.scaleBy(x: scale, y: scale)
                            layer.draw(symbol, at: .zero)
                        }
                    } symbols: {
                        ForEach(0..<Self.shapes.count * palette.count, id: \.self) { tag in
                            Image(systemName: Self.shapes[tag / palette.count])
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette[tag % palette.count])
                                .tag(tag)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            sparks = MVSpark.burst(symbols: Self.shapes.count * palette.count)
            burst = Date()
        }
        .task(id: burst) {
            guard burst != nil else { return }
            try? await Task.sleep(for: .seconds(Self.duration + 0.1))
            // A newer burst restarted this task: it owns the Canvas now
            guard !Task.isCancelled else { return }
            burst = nil
        }
    }
}

private struct MVSpark {
    let symbol: Int
    /// Where it starts, around the tile's center.
    let offset: CGVector
    /// Points per second.
    let velocity: CGVector
    /// Radians per second.
    let spin: Double
    let scale: Double
    let delay: Double

    static func burst(symbols: Int) -> [MVSpark] {
        (0..<28).map { _ in
            let angle = Double.random(in: 0..<(2 * .pi))
            let speed = Double.random(in: 150...330)
            return MVSpark(symbol: Int.random(in: 0..<symbols),
                           offset: CGVector(dx: .random(in: -18...18), dy: .random(in: -14...14)),
                           // Thrown upward a little more, so gravity arcs them
                           velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 140),
                           spin: .random(in: -6...6),
                           scale: .random(in: 0.6...1.3),
                           delay: .random(in: 0...0.06))
        }
    }
}

/// The sidebar's update badge: it slides in, and its arrow nods once.
struct MVUpdateBadge: View {
    let version: String
    let action: () -> Void
    @State private var nods = 0
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text("Moonvibe \(version) est disponible")
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .symbolEffect(.bounce.down, value: nods)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(mvAccentForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(mvAccent.opacity(hovering ? 0.2 : 0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Voir les nouveautés et installer")
        .task {
            // Once it has slid in
            try? await Task.sleep(for: .milliseconds(450))
            nods += 1
        }
    }
}
