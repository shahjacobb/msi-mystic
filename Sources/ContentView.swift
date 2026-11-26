import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var light: LightController
    @State private var editingColor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrandMark(resource: "msi-logo").frame(height: 15)
                Spacer()
                Toggle("Power", isOn: $light.power)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!light.connected)
            }
            .padding(.top, 40)

            MonitorView(mode: light.mode, color: light.color, level: light.level, speed: light.speed,
                        lit: light.connected && light.power, connected: light.connected)
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .padding(.top, 12)

            Text(light.title)
                .font(.system(size: 30, weight: .semibold).width(.expanded))
                .contentTransition(.opacity)
                .padding(.top, 14)

            if !light.connected {
                Text("Connect the monitor's USB-B cable to this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 6)
            }

            ModeTabs(selection: $light.mode)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 26) {
                if light.mode.usesColor || light.mode == .scenes {
                    Section(light.mode == .scenes ? "Sequence" : "Color") {
                        SwatchRow(swatches: light.swatches,
                                  active: light.activeSwatch,
                                  allowsCustom: light.mode != .scenes,
                                  editingCustom: $editingColor,
                                  hue: $light.hue,
                                  saturation: $light.saturation,
                                  select: light.select)
                    }
                }

                if light.mode == .scenes {
                    Section("Interval", value: "\(Int(light.sceneInterval)) s") {
                        LineSlider(value: $light.sceneInterval, range: 1...10, step: 1, tint: .white)
                    }
                }

                Section("Brightness", value: "\(Int((light.level * 100).rounded()))%") {
                    LineSlider(value: $light.level, range: 0.05...1, step: 0,
                               tint: light.mode.isSpectrum ? .white : light.color)
                }

                if light.mode.usesSpeed {
                    Section("Speed") {
                        Picker("Speed", selection: $light.speed) {
                            Text("Slow").tag(0)
                            Text("Medium").tag(1)
                            Text("Fast").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
            .padding(.top, 24)
            .disabled(!light.connected || !light.power)
            .opacity(light.connected && light.power ? 1 : 0.3)

            Spacer(minLength: 20)

            HStack {
                Text(light.connected ? light.monitorName : "")
                Spacer()
                Button("Restore Factory Lighting", action: light.restoreFactory)
                    .buttonStyle(.plain)
                    .disabled(!light.connected)
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.32))
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .animation(.smooth(duration: 0.3), value: light.mode)
        .animation(.smooth(duration: 0.3), value: light.power)
        .animation(.smooth(duration: 0.5), value: light.sceneIndex)
    }
}

// MARK: - Sections

private struct Section<Content: View>: View {
    let label: String
    let value: String?
    let content: Content

    init(_ label: String, value: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let value {
                    Text(value)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .font(.system(size: 12, weight: .medium))
            content
        }
    }
}

// MARK: - Brand

struct BrandMark: View {
    let resource: String

    var body: some View {
        if let url = Bundle.main.url(forResource: resource, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Text("msi").font(.system(size: 16, weight: .heavy)).italic()
        }
    }
}

// MARK: - Monitor

struct MonitorView: View {
    let mode: LightMode
    let color: Color
    let level: Double
    let speed: Int
    let lit: Bool
    let connected: Bool

    private static let spectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 0.95, brightness: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !lit || !mode.isAnimated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse()
                    .fill(glow(t))
                    .frame(width: 320, height: 170)
                    .blur(radius: 38)
                    .offset(y: -14)
                    .opacity(lit ? (0.3 + 0.7 * level) * pulse(t) : 0)

                Monitor()
                    .opacity(connected ? 1 : 0.45)
            }
        }
    }

    private var rate: Double { [0.6, 1.0, 1.8][min(max(speed, 0), 2)] }

    private func glow(_ t: Double) -> AnyShapeStyle {
        if mode.isSpectrum {
            return AnyShapeStyle(AngularGradient(colors: Self.spectrum, center: .center,
                                                 angle: .degrees(t * 36 * rate)))
        }
        return AnyShapeStyle(color)
    }

    private func pulse(_ t: Double) -> Double {
        switch mode {
        case .breathe: 0.15 + 0.85 * (0.5 + 0.5 * sin(t * 2 * rate))
        case .flash: sin(t * 6 * rate) > 0 ? 1 : 0
        default: 1
        }
    }
}

/// Front view of a 27" white MSI MPG monitor.
private struct Monitor: View {
    private let shell = LinearGradient(colors: [Color(white: 0.95), Color(white: 0.80)],
                                       startPoint: .top, endPoint: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(shell)
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.11), Color(white: 0.03)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(
                            LinearGradient(stops: [.init(color: .white.opacity(0.07), location: 0),
                                                   .init(color: .clear, location: 0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                        )
                        .padding([.top, .horizontal], 3)
                    BrandMark(resource: "msi-wordmark-2020")
                        .foregroundStyle(Color(white: 0.45))
                        .frame(height: 4)
                        .frame(height: 11)
                }
            }
            .frame(width: 250, height: 150)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 6)

            Trapezoid(inset: 3)
                .fill(LinearGradient(colors: [Color(white: 0.72), Color(white: 0.88)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 28, height: 34)

            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.74)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 118, height: 7)
        }
    }
}

private struct Trapezoid: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Modes

struct ModeTabs: View {
    @Binding var selection: LightMode
    @Namespace private var underline

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack(spacing: 0) {
                ForEach(LightMode.allCases) { mode in
                    let selected = mode == selection
                    Button { selection = mode } label: {
                        VStack(spacing: 10) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(selected ? 1 : 0.42))
                            ZStack {
                                Rectangle().fill(.clear).frame(height: 2)
                                if selected {
                                    Rectangle().fill(.white).frame(height: 2)
                                        .matchedGeometryEffect(id: "underline", in: underline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Color

struct SwatchRow: View {
    let swatches: [Swatch]
    let active: Swatch?
    let allowsCustom: Bool
    @Binding var editingCustom: Bool
    @Binding var hue: Double
    @Binding var saturation: Double
    let select: (Swatch) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(swatches) { swatch in
                Dot(isActive: swatch == active) { Circle().fill(swatch.color) }
                    .onTapGesture { select(swatch) }
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(.isButton)
                    .frame(maxWidth: .infinity)
            }
            if allowsCustom {
                Dot(isActive: active == nil) {
                    Circle().fill(AngularGradient(colors: (0...12).map {
                        Color(hue: Double($0) / 12, saturation: 0.85, brightness: 1)
                    }, center: .center))
                }
                .onTapGesture { editingCustom = true }
                .help("Custom")
                .accessibilityLabel("Custom color")
                .accessibilityAddTraits(.isButton)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $editingCustom, arrowEdge: .bottom) {
                    ColorWheel(hue: $hue, saturation: $saturation)
                        .frame(width: 220, height: 220)
                        .padding(18)
                }
            }
        }
    }
}

private struct Dot<Fill: View>: View {
    let isActive: Bool
    @ViewBuilder var fill: Fill

    var body: some View {
        fill
            .frame(width: 28, height: 28)
            .padding(4)
            .overlay(Circle().strokeBorder(.white.opacity(isActive ? 1 : 0), lineWidth: 1.5))
            .contentShape(Circle())
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
            let reach = radius - 12
            let angle = hue * 2 * .pi

            ZStack {
                Circle().fill(AngularGradient(colors: Self.hues, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: 1))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .position(x: radius + cos(angle) * saturation * reach,
                              y: radius + sin(angle) * saturation * reach)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let dx = drag.location.x - radius, dy = drag.location.y - radius
                    var a = atan2(dy, dx)
                    if a < 0 { a += 2 * .pi }
                    hue = a / (2 * .pi)
                    saturation = min(1, hypot(dx, dy) / reach)
                }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Slider

struct LineSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 16
            let track = geo.size.width - knob
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = knob / 2 + track * fraction

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(tint).frame(width: x, height: 3)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: x - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = min(max((drag.location.x - knob / 2) / track, 0), 1)
                    var v = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    if step > 0 { v = (v / step).rounded() * step }
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
            )
        }
        .frame(height: 20)
    }
}
