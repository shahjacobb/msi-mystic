import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var light: LightController
    @State private var editingColor = false

    private var controlsEnabled: Bool { light.connected && light.lightingSupported && light.power }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandMark(resource: "msi-wordmark-2020").frame(height: 17)
                    Spacer()
                    Toggle("Lighting", isOn: $light.power)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!light.connected)
                }
                .padding(.top, 40)

                MonitorHero(model: light.monitor, mode: light.mode, color: light.color,
                            level: light.level, speed: light.speed,
                            lit: controlsEnabled, connected: light.connected)
                    .frame(maxWidth: .infinity)
                    .frame(height: 262)
                    .padding(.top, 10)

                deviceHeader.padding(.top, 18)

                TabStrip(selection: $light.category)
                    .animation(.smooth(duration: 0.25), value: light.category)
                    .padding(.top, 22)

                controls
                    .padding(.top, 24)
                    .disabled(!controlsEnabled)
                    .opacity(controlsEnabled ? 1 : 0.3)

                footer.padding(.top, 34)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
        }
        .background(Color.black)
        .animation(.smooth(duration: 0.3), value: light.power)
        .alert("Allow lighting changes on this monitor?", isPresented: $light.askingToWrite) {
            Button("Allow") { light.allowWrites() }
            Button("Cancel", role: .cancel) { light.declineWrites() }
        } message: {
            Text("\(light.monitor.name) hasn't been tested with MSI Mystic yet. Its current lighting is saved, so Restore Original Lighting can put it back.")
        }
    }

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(light.connected ? light.monitor.name : "No Monitor")
                .font(.system(size: 22, weight: .semibold).width(.expanded))
            if let note = statusNote {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var statusNote: String? {
        if !light.connected { return "Connect the monitor's USB-B upstream cable to this Mac." }
        if !light.lightingSupported { return "This monitor doesn't expose lighting control." }
        return nil
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 26) {
            switch light.category {
            case .color:
                Section("Color", value: light.colorName) {
                    swatches(allowsCustom: true)
                }
                Section("Effect") {
                    Picker("Effect", selection: $light.mode) {
                        Text("Steady").tag(LightMode.solid)
                        Text("Breathe").tag(LightMode.breathe)
                        Text("Flash").tag(LightMode.flash)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            case .spectrum:
                Section("Style") {
                    Picker("Style", selection: $light.mode) {
                        Text("Ambient").tag(LightMode.ambient)
                        Text("Rainbow").tag(LightMode.rainbow)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            case .scenes:
                Section("Sequence", value: light.colorName) {
                    swatches(allowsCustom: false)
                }
                Section("Hold each color", value: "\(Int(light.sceneInterval)) s") {
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
    }

    private func swatches(allowsCustom: Bool) -> some View {
        SwatchRow(swatches: light.swatches,
                  active: light.activeSwatch,
                  allowsCustom: allowsCustom,
                  editingCustom: $editingColor,
                  hue: $light.hue,
                  saturation: $light.saturation,
                  select: light.select,
                  onCustom: light.beginCustomColor)
    }

    private var footer: some View {
        HStack {
            if let page = light.monitor.productPage, light.connected {
                Link("Product Page", destination: page)
            }
            Spacer()
            Button(light.hasFactoryData ? "Restore Factory Lighting" : "Restore Original Lighting",
                   action: light.restore)
                .buttonStyle(.plain)
                .disabled(!light.connected || !light.lightingSupported)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.35))
        .tint(.white.opacity(0.35))
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
                        .contentTransition(.opacity)
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
        if let image = Bundle.main.url(forResource: resource, withExtension: "png").flatMap(NSImage.init(contentsOf:)) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Text("MSI").font(.system(size: 14, weight: .heavy))
        }
    }
}

// MARK: - Hero

struct MonitorHero: View {
    let model: MonitorModel
    let mode: LightMode
    let color: Color
    let level: Double
    let speed: Int
    let lit: Bool
    let connected: Bool

    private static let spectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 0.9, brightness: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !lit || !mode.isAnimated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let light = lightStyle(t)
            let intensity = lit ? (0.35 + 0.65 * level) * pulse(t) : 0

            Group {
                if let photo = model.rearPhoto, let rear = RearPhoto(resource: photo) {
                    rear.body(light: light, intensity: intensity)
                } else {
                    DrawnMonitor(light: light, intensity: intensity)
                }
            }
        }
        .opacity(connected ? 1 : 0.4)
    }

    private var rate: Double { [0.6, 1.0, 1.8][min(max(speed, 0), 2)] }

    /// What the LEDs are showing at time t.
    private func lightStyle(_ t: Double) -> AnyShapeStyle {
        switch mode {
        case .rainbow:
            AnyShapeStyle(AngularGradient(colors: Self.spectrum, center: UnitPoint(x: 0.5, y: 0.33),
                                          angle: .degrees(t * 50 * rate)))
        case .ambient:
            AnyShapeStyle(Color(hue: (t * 0.06 * rate).truncatingRemainder(dividingBy: 1),
                                saturation: 0.9, brightness: 1))
        default:
            AnyShapeStyle(color)
        }
    }

    private func pulse(_ t: Double) -> Double {
        switch mode {
        case .breathe: 0.12 + 0.88 * (0.5 + 0.5 * sin(t * 2 * rate))
        case .flash: sin(t * 6 * rate) > 0 ? 1 : 0
        default: 1
        }
    }
}

/// MSI's product photo of the monitor's rear, with the LED dots split into a separate mask
/// so they can be lit in the current color.
private struct RearPhoto {
    let base: NSImage
    let leds: NSImage

    init?(resource: String) {
        guard let baseURL = Bundle.main.url(forResource: resource, withExtension: "png"),
              let ledURL = Bundle.main.url(forResource: resource + "-leds", withExtension: "png"),
              let base = NSImage(contentsOf: baseURL),
              let leds = NSImage(contentsOf: ledURL) else { return nil }
        self.base = base
        self.leds = leds
    }

    func body(light: AnyShapeStyle, intensity: Double) -> some View {
        let aspect = base.size.width / base.size.height
        return ZStack {
            Image(nsImage: base).resizable().interpolation(.high)
            ledLayer(light).opacity(intensity)
            ledLayer(light).blur(radius: 6).blendMode(.plusLighter).opacity(0.8 * intensity)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .background {
            GeometryReader { geo in
                Ellipse()
                    .fill(light)
                    .frame(width: geo.size.width * 1.25, height: geo.size.height * 0.62)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.33)
                    .blur(radius: 44)
                    .opacity(0.55 * intensity)
            }
        }
    }

    private func ledLayer(_ light: AnyShapeStyle) -> some View {
        Rectangle()
            .fill(light)
            .mask(Image(nsImage: leds).resizable().interpolation(.high))
    }
}

/// Fallback for MSI monitors without a product photo.
private struct DrawnMonitor: View {
    let light: AnyShapeStyle
    let intensity: Double

    private let shell = LinearGradient(colors: [Color(white: 0.95), Color(white: 0.80)],
                                       startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(light)
                .frame(width: 320, height: 170)
                .blur(radius: 38)
                .offset(y: -14)
                .opacity(intensity)

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(shell)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color(white: 0.06))
                        .padding([.top, .horizontal], 3)
                        .padding(.bottom, 11)
                }
                .frame(width: 250, height: 150)
                Rectangle().fill(Color(white: 0.82)).frame(width: 26, height: 34)
                Capsule().fill(Color(white: 0.85)).frame(width: 118, height: 7)
            }
        }
    }
}

// MARK: - Tabs

struct TabStrip: View {
    @Binding var selection: LightingCategory
    @Namespace private var underline

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack(spacing: 0) {
                ForEach(LightingCategory.allCases) { item in
                    let selected = item == selection
                    Button { selection = item } label: {
                        VStack(spacing: 10) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
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
    let onCustom: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(swatches) { swatch in
                Button { select(swatch) } label: {
                    Dot(isActive: swatch == active) { Circle().fill(swatch.color) }
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
                .frame(maxWidth: .infinity)
            }
            if allowsCustom {
                Button { onCustom(); editingCustom = true } label: {
                    Dot(isActive: active == nil) {
                        Circle().fill(AngularGradient(colors: (0...12).map {
                            Color(hue: Double($0) / 12, saturation: 0.85, brightness: 1)
                        }, center: .center))
                    }
                }
                .buttonStyle(.plain)
                .help("Custom")
                .accessibilityLabel("Custom color")
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
