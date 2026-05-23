import SwiftUI

struct GalaxyWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        AnimationPhaseView(speed: 0.06) { phase in
            GalaxyScene(phase: phase)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        HeaderChip(title: "SECTOR 7-ALPHA", color: .cyan)
                        HeaderChip(title: "PARALLAX \(Int(phase * 360))", color: .violet)
                    }
                    .padding(12)
                }
        }
    }
}

struct GalaxyScene: View {
    @Environment(\.astraTheme) private var theme
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.52, y: size.height * 0.48)
            let depthOffset = CGFloat(sin(phase * .pi * 2)) * 16

            for index in 0..<220 {
                let t = Double(index) * 0.61803398875
                let arm = Double(index % 4) * .pi / 2
                let radius = sqrt(Double(index) / 220) * Double(min(size.width, size.height)) * 0.48
                let angle = t * 7 + arm + phase * 0.7
                let depth = sin(t * 11 + phase * .pi * 2)
                let x = center.x + CGFloat(cos(angle) * radius) + depthOffset * CGFloat(depth)
                let y = center.y + CGFloat(sin(angle) * radius * 0.48) + CGFloat(depth * 18)
                let starSize = CGFloat(1.2 + (depth + 1) * 1.2)
                let color = index.isMultiple(of: 9) ? theme.color(.rose) : index.isMultiple(of: 5) ? theme.color(.gold) : theme.palette.text
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: starSize, height: starSize)), with: .color(color.opacity(0.55 + depth * 0.22)))
            }

            let core = Path(ellipseIn: CGRect(x: center.x - 42, y: center.y - 26, width: 84, height: 52))
            context.fill(core, with: .radialGradient(
                Gradient(colors: [theme.color(.gold).opacity(0.82), theme.color(.rose).opacity(0.32), .clear]),
                center: center,
                startRadius: 2,
                endRadius: 70
            ))

            for orbit in 0..<4 {
                let rect = CGRect(
                    x: center.x - CGFloat(90 + orbit * 42),
                    y: center.y - CGFloat(38 + orbit * 18),
                    width: CGFloat(180 + orbit * 84),
                    height: CGFloat(76 + orbit * 36)
                )
                context.stroke(Path(ellipseIn: rect), with: .color(theme.color(.cyan).opacity(0.12)), lineWidth: 1)
            }
        }
    }
}

struct PlanetOrbitWidget: View {
    var body: some View {
        AnimationPhaseView(speed: 0.08) { phase in
            VStack(spacing: 10) {
                OrbitCanvas(phase: phase)
                HStack(spacing: 8) {
                    MicroStat(label: "ORBIT", value: "\(Int(phase * 360)) DEG", color: .cyan)
                    MicroStat(label: "BODY", value: "5 LOCKED", color: .gold)
                    MicroStat(label: "DRIFT", value: "0.04 AU", color: .violet)
                }
            }
        }
    }
}

struct OrbitCanvas: View {
    @Environment(\.astraTheme) private var theme
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)), with: .radialGradient(
                Gradient(colors: [theme.color(.gold), theme.color(.apricot), .clear]),
                center: center,
                startRadius: 3,
                endRadius: 38
            ))

            for index in 0..<5 {
                let w = CGFloat(92 + index * 54)
                let h = CGFloat(42 + index * 28)
                let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
                context.stroke(Path(ellipseIn: rect), with: .color(theme.palette.text.opacity(0.14)), lineWidth: 1)

                let angle = phase * .pi * 2 * (index.isMultiple(of: 2) ? 1 : -1) + Double(index) * 0.93
                let x = center.x + cos(angle) * w / 2
                let y = center.y + sin(angle) * h / 2
                let radius = CGFloat(5 + index * 2)
                let color: Color = [theme.color(.cyan), theme.color(.violet), theme.color(.rose), theme.color(.mint), theme.color(.apricot)][index]
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            }
        }
        .frame(minHeight: 190)
    }
}

struct StarMapWidget: View {
    var body: some View {
        AnimationPhaseView(speed: 0.12) { phase in
            VStack(spacing: 10) {
                StarMapCanvas(phase: phase)
                    .frame(minHeight: 190)
                MetricLine(label: "Route", value: "AR-42 / DELTA", progress: 0.72, color: .cyan)
            }
        }
    }
}

struct StarMapCanvas: View {
    @Environment(\.astraTheme) private var theme
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let stars = seededPoints(count: 58, in: size)
            for pair in stride(from: 0, to: stars.count - 1, by: 5) {
                var path = Path()
                path.move(to: stars[pair])
                path.addLine(to: stars[(pair + 3) % stars.count])
                context.stroke(path, with: .color(theme.color(.cyan).opacity(0.18)), lineWidth: 1)
            }

            var route = Path()
            let routePoints = [CGPoint(x: size.width * 0.12, y: size.height * 0.72),
                               CGPoint(x: size.width * 0.28, y: size.height * 0.48),
                               CGPoint(x: size.width * 0.50, y: size.height * 0.56),
                               CGPoint(x: size.width * 0.72, y: size.height * 0.32),
                               CGPoint(x: size.width * 0.88, y: size.height * 0.38)]
            for (index, point) in routePoints.enumerated() {
                if index == 0 { route.move(to: point) } else { route.addLine(to: point) }
            }
            context.stroke(route, with: .color(theme.color(.gold)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [9, 6], dashPhase: phase * 20))

            for (index, star) in stars.enumerated() {
                let radius = CGFloat(index.isMultiple(of: 11) ? 3.4 : 1.8)
                let color = index.isMultiple(of: 11) ? theme.color(.rose) : theme.palette.text
                context.fill(Path(ellipseIn: CGRect(x: star.x - radius, y: star.y - radius, width: radius * 2, height: radius * 2)), with: .color(color.opacity(0.86)))
            }
        }
    }

    private func seededPoints(count: Int, in size: CGSize) -> [CGPoint] {
        (0..<count).map { index in
            let a = sin(Double(index * 197 + 13)) * 43758.5453
            let b = sin(Double(index * 271 + 7)) * 24634.6345
            let x = CGFloat(a - floor(a)) * size.width
            let y = CGFloat(b - floor(b)) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

struct TacticalSweepWidget: View {
    var body: some View {
        AnimationPhaseView(speed: 0.16) { phase in
            VStack(spacing: 12) {
                TacticalSweepCanvas(phase: phase)
                    .frame(minHeight: 210)
                MetricLine(label: "Contacts", value: "\(12 + Int(phase * 5))", progress: 0.64, color: .mint)
            }
        }
    }
}

struct TacticalSweepCanvas: View {
    @Environment(\.astraTheme) private var theme
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.44

            for ring in 1...5 {
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - radius * CGFloat(ring) / 5, y: center.y - radius * CGFloat(ring) / 5, width: radius * 2 * CGFloat(ring) / 5, height: radius * 2 * CGFloat(ring) / 5)),
                    with: .color(theme.color(.cyan).opacity(0.14)),
                    lineWidth: 1
                )
            }

            for spoke in 0..<12 {
                let angle = Double(spoke) / 12 * .pi * 2
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                context.stroke(path, with: .color(theme.palette.text.opacity(0.07)), lineWidth: 1)
            }

            let sweepAngle = phase * .pi * 2 - .pi / 2
            var sweep = Path()
            sweep.move(to: center)
            sweep.addArc(center: center, radius: radius, startAngle: .radians(sweepAngle - 0.35), endAngle: .radians(sweepAngle), clockwise: false)
            sweep.closeSubpath()
            context.fill(sweep, with: .color(theme.color(.mint).opacity(0.22)))

            for contact in 0..<14 {
                let angle = Double(contact * 73) * .pi / 180
                let distance = radius * CGFloat(0.18 + Double((contact * 29) % 70) / 100)
                let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(contact.isMultiple(of: 4) ? theme.color(.rose) : theme.color(.gold)))
            }
        }
    }
}
