import SwiftUI

enum LightMode: String, CaseIterable, Identifiable {
    case solid = "Solid"
    case breathe = "Breathe"
    case flash = "Flash"
    case rainbow = "Rainbow"
    case spectrum = "Spectrum"
    case scenes = "Scenes"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .solid: "circle.fill"
        case .breathe: "wind"
        case .flash: "bolt.fill"
        case .rainbow: "rainbow"
        case .spectrum: "sparkles"
        case .scenes: "square.stack.3d.up.fill"
        }
    }

    /// Mode byte understood by the monitor. Scenes is driven by the app as a sequence of solid colors.
    var hardwareMode: UInt8 {
        switch self {
        case .solid, .scenes: 0x01
        case .breathe: 0x02
        case .flash: 0x05
        case .rainbow: 0x1A
        case .spectrum: 0x21
        }
    }

    var usesColor: Bool { self == .solid || self == .breathe || self == .flash }
    var usesSpeed: Bool { self == .breathe || self == .flash || self == .rainbow || self == .spectrum }
    var isAnimated: Bool { self != .solid && self != .scenes }

    init?(hardwareMode: UInt8) {
        switch hardwareMode {
        case 0x01: self = .solid
        case 0x02: self = .breathe
        case 0x05: self = .flash
        case 0x1A: self = .rainbow
        case 0x21: self = .spectrum
        default: return nil
        }
    }
}

struct Swatch: Identifiable, Hashable {
    let name: String
    let red: Double, green: Double, blue: Double
    var id: String { name }
    var color: Color { Color(red: red, green: green, blue: blue) }

    init(_ name: String, _ r: Int, _ g: Int, _ b: Int) {
        self.name = name
        red = Double(r) / 255; green = Double(g) / 255; blue = Double(b) / 255
    }

    static let all: [Swatch] = [
        Swatch("Qatar Burgundy", 150, 0, 55),
        Swatch("Singapore Orange", 255, 110, 0),
        Swatch("Royal Purple", 110, 0, 255),
        Swatch("Magenta", 255, 0, 150),
        Swatch("Lagoon", 0, 200, 170),
        Swatch("Glacier", 170, 215, 255),
    ]
}

final class LightController: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var monitorName = "MSI Monitor"

    @Published var power = true { didSet { restartScenes(); apply() } }
    @Published var mode: LightMode = .solid { didSet { restartScenes(); apply() } }
    @Published var hue: Double = 0.072 { didSet { apply() } }
    @Published var saturation: Double = 1 { didSet { apply() } }
    @Published var level: Double = 1 { didSet { apply() } }
    @Published var speed: Int = 1 { didSet { apply() } }
    @Published var sceneInterval: Double = 5 { didSet { restartScenes() } }
    @Published private(set) var sceneIndex = 0

    let swatches = Swatch.all
    private let device = MSIDevice()
    private var sceneTimer: Timer?
    private var isSyncing = false

    init() {
        device.onConnectionChange = { [weak self] connected in
            self?.connectionChanged(connected)
        }
    }

    // MARK: Derived values

    /// Full-intensity color of the current selection, before brightness.
    var baseRGB: (Double, Double, Double) {
        if mode == .scenes {
            let s = swatches[sceneIndex % swatches.count]
            return (s.red, s.green, s.blue)
        }
        return HSV(h: hue, s: saturation, v: 1).rgb
    }

    var color: Color {
        let (r, g, b) = baseRGB
        return Color(red: r, green: g, blue: b)
    }

    var activeSwatch: Swatch? {
        if mode == .scenes { return swatches[sceneIndex % swatches.count] }
        let (r, g, b) = baseRGB
        return swatches.first { abs($0.red - r) < 0.02 && abs($0.green - g) < 0.02 && abs($0.blue - b) < 0.02 }
    }

    var title: String {
        guard power else { return "Off" }
        switch mode {
        case .rainbow: return "Rainbow"
        case .spectrum: return "Spectrum"
        default: return activeSwatch?.name ?? hex
        }
    }

    var hex: String {
        let (r, g, b) = baseRGB
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    // MARK: Actions

    func select(_ swatch: Swatch) {
        if mode == .scenes {
            sceneIndex = swatches.firstIndex(of: swatch) ?? 0
            restartScenes()
            apply()
            return
        }
        if !mode.usesColor { mode = .solid }
        let hsv = HSV(r: swatch.red, g: swatch.green, b: swatch.blue)
        hue = hsv.h
        saturation = hsv.s
    }

    func restoreFactory() {
        device.sendNow(MSIDevice.factory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.syncFromDevice() }
    }

    // MARK: Device

    private func connectionChanged(_ isConnected: Bool) {
        connected = isConnected
        if isConnected {
            monitorName = (device.productName ?? "MSI Monitor").replacingOccurrences(of: "MSI Monitor ", with: "")
            syncFromDevice()
        } else {
            sceneTimer?.invalidate()
        }
    }

    private func syncFromDevice() {
        guard let state = device.readState() else { return }
        isSyncing = true
        defer { isSyncing = false }

        power = state.mode != 0
        if let m = LightMode(hardwareMode: state.mode) { mode = m }

        let hsv = HSV(r: Double(state.red) / 255, g: Double(state.green) / 255, b: Double(state.blue) / 255)
        if hsv.v > 0 {
            hue = hsv.h
            saturation = hsv.s
        }
        level = mode == .solid ? max(0.05, hsv.v) : max(0.05, Double(state.brightness) / 100)
        speed = Int(min(state.speed, 2))
    }

    private func apply() {
        guard connected, !isSyncing else { return }
        guard power else {
            device.send(.init(mode: 0, red: 0, green: 0, blue: 0, speed: 0, brightness: 0))
            return
        }
        var (r, g, b) = baseRGB
        var brightness: UInt8 = 100
        if mode == .solid || mode == .scenes {
            r *= level; g *= level; b *= level
        } else {
            brightness = UInt8((level * 100).rounded())
        }
        device.send(.init(mode: mode.hardwareMode, red: byte(r), green: byte(g), blue: byte(b),
                          speed: UInt8(speed), brightness: brightness))
    }

    private func restartScenes() {
        sceneTimer?.invalidate()
        sceneTimer = nil
        guard mode == .scenes, power, !isSyncing else { return }
        sceneTimer = Timer.scheduledTimer(withTimeInterval: sceneInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            sceneIndex = (sceneIndex + 1) % swatches.count
            apply()
        }
    }

    private func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
}

struct HSV {
    var h: Double, s: Double, v: Double

    init(h: Double, s: Double, v: Double) { self.h = h; self.s = s; self.v = v }

    init(r: Double, g: Double, b: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        v = maxC
        s = maxC == 0 ? 0 : delta / maxC
        guard delta > 0 else { h = 0; return }
        var hue: Double
        if maxC == r { hue = (g - b) / delta }
        else if maxC == g { hue = (b - r) / delta + 2 }
        else { hue = (r - g) / delta + 4 }
        hue /= 6
        h = hue < 0 ? hue + 1 : hue
    }

    var rgb: (Double, Double, Double) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
