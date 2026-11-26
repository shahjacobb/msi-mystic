import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var light: LightController

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                header
                LightOrb(mode: light.mode, color: light.color, lit: light.power, speed: light.speed)
                    .padding(.top, 4)
                caption
                controls
                    .disabled(!light.connected || !light.power)
                    .opacity(light.connected && light.power ? 1 : 0.35)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 44)
            .padding(.bottom, 24)
        }
        .background {
            Backdrop(color: light.color, lit: light.power && light.connected)
        }
        .animation(.smooth(duration: 0.35), value: light.mode)
        .animation(.smooth(duration: 0.35), value: light.power)
        .animation(.smooth(duration: 0.6), value: light.sceneIndex)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            MSILogo().frame(height: 20)
            Spacer()
            PowerButton(isOn: $light.power)
                .disabled(!light.connected)
        }
    }

    private var caption: some View {
        VStack(spacing: 6) {
            Text(light.connected ? light.title : "Not Connected")
                .font(.system(size: 26, weight: .semibold))
                .contentTransition(.opacity)
            HStack(spacing: 6) {
                Circle()
                    .fill(light.connected ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(light.connected ? light.monitorName : "Plug in the monitor's USB-B cable")
                if light.connected && light.power && !light.mode.isAnimated {
                    Text("·")
                    Text(light.hex).monospaced()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            ModeGrid(selection: $light.mode)

            if light.mode.usesColor {
                Card {
                    VStack(spacing: 22) {
                        ColorWheel(hue: $light.hue, saturation: $light.saturation)
                            .frame(width: 236, height: 236)
                        SwatchRow(swatches: light.swatches, active: light.activeSwatch, select: light.select)
                    }
                    .padding(.vertical, 6)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if light.mode == .scenes {
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        SwatchRow(swatches: light.swatches, active: light.activeSwatch, select: light.select)
                        CapsuleSlider(value: $light.sceneInterval, range: 1...10, step: 1,
                                      symbol: "timer", tint: light.color) {
                            "\(Int($0)) s"
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            Card {
                CapsuleSlider(value: $light.level, range: 0.05...1, step: 0,
                              symbol: "sun.max.fill", tint: light.color) {
                    "\(Int(($0 * 100).rounded()))%"
                }
            }

            if light.mode.usesSpeed {
                Card {
                    Picker("Speed", selection: $light.speed) {
                        Text("Slow").tag(0)
                        Text("Medium").tag(1)
                        Text("Fast").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        Button("Restore Factory Lighting", action: light.restoreFactory)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.tertiary)
            .disabled(!light.connected)
            .padding(.top, 4)
    }
}

// MARK: - Components

struct Backdrop: View {
    let color: Color
    let lit: Bool

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.042)
            Circle()
                .fill(color)
                .frame(width: 560, height: 560)
                .blur(radius: 150)
                .offset(y: -300)
                .opacity(lit ? 0.42 : 0)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.8), value: color)
    }
}

struct MSILogo: View {
    private static let image: NSImage? = Bundle.main.url(forResource: "msi-logo", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        } else {
            Text("MSI")
                .font(.system(size: 20, weight: .black))
                .italic()
        }
    }
}

struct PowerButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isOn ? .black : .white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Circle().fill(isOn ? Color.white : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Turn lighting off" : "Turn lighting on")
    }
}

struct LightOrb: View {
    let mode: LightMode
    let color: Color
    let lit: Bool
    let speed: Int

    private static let spectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 0.9, brightness: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !lit || !mode.isAnimated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let intensity = lit ? pulse(t) : 0
            ZStack {
                Circle()
                    .fill(fill(t))
                    .frame(width: 190, height: 190)
                    .blur(radius: 48)
                    .opacity(0.8 * intensity)
                Circle()
                    .fill(Color(white: 0.09))
                    .frame(width: 156, height: 156)
                Circle()
                    .fill(fill(t))
                    .frame(width: 156, height: 156)
                    .opacity(intensity)
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                         startPoint: .top, endPoint: .center))
                    .frame(width: 156, height: 156)
                    .blendMode(.plusLighter)
                    .opacity(lit ? 0.6 : 0.25)
                Circle()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 156, height: 156)
            }
        }
        .frame(height: 210)
    }

    private var rate: Double { [0.6, 1.0, 1.8][min(max(speed, 0), 2)] }

    private func fill(_ t: Double) -> AnyShapeStyle {
        if mode == .rainbow || mode == .spectrum {
            return AnyShapeStyle(AngularGradient(colors: Self.spectrum, center: .center,
                                                 angle: .degrees(t * 40 * rate)))
        }
        return AnyShapeStyle(RadialGradient(colors: [color.mix(with: .white, by: 0.25), color],
                                            center: UnitPoint(x: 0.4, y: 0.3),
                                            startRadius: 0, endRadius: 110))
    }

    private func pulse(_ t: Double) -> Double {
        switch mode {
        case .breathe: 0.2 + 0.8 * (0.5 + 0.5 * sin(t * 2.2 * rate))
        case .flash: sin(t * 6 * rate) > 0 ? 1 : 0.06
        default: 1
        }
    }
}

struct ModeGrid: View {
    @Binding var selection: LightMode
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(LightMode.allCases) { mode in
                let selected = mode == selection
                Button { selection = mode } label: {
                    VStack(spacing: 7) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected ? Color.white : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(selected ? 0 : 0.06), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double

    private static let hues: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 24).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let angle = hue * 2 * .pi
            let distance = saturation * (radius - 14)

            ZStack {
                Circle().fill(AngularGradient(colors: Self.hues, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: radius))
                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1)

                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: 1))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .position(x: radius + cos(angle) * distance, y: radius + sin(angle) * distance)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let dx = drag.location.x - radius, dy = drag.location.y - radius
                    var a = atan2(dy, dx)
                    if a < 0 { a += 2 * .pi }
                    hue = a / (2 * .pi)
                    saturation = min(1, hypot(dx, dy) / (radius - 14))
                }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SwatchRow: View {
    let swatches: [Swatch]
    let active: Swatch?
    let select: (Swatch) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(swatches) { swatch in
                let isActive = swatch == active
                Button { select(swatch) } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 30, height: 30)
                        .padding(4)
                        .overlay(Circle().strokeBorder(.white.opacity(isActive ? 0.9 : 0), lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct CapsuleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let symbol: String
    let tint: Color
    let label: (Double) -> String

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let fillWidth = max(44, geo.size.width * fraction)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth)
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    Spacer()
                    Text(label(value))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 16)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = min(max(drag.location.x / geo.size.width, 0), 1)
                    var v = range.lowerBound + f * span
                    if step > 0 { v = (v / step).rounded() * step }
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
            )
        }
        .frame(height: 44)
    }
}
