import SwiftUI

enum LightingCategory: String, CaseIterable, Identifiable {
    case color = "Color"
    case spectrum = "Spectrum"
    case scenes = "Scenes"
    var id: Self { self }
}

enum LightMode: String, CaseIterable, Identifiable {
    case solid = "Steady"
    case breathe = "Breathe"
    case flash = "Flash"
    case ambient = "Ambient"
    case rainbow = "Rainbow"
    case scenes = "Scenes"

    var id: Self { self }

    /// Mode byte understood by the monitor. Scenes is driven by the app as a sequence of solid colors.
    var hardwareMode: UInt8 {
        switch self {
        case .solid, .scenes: 0x01
        case .breathe: 0x02
        case .flash: 0x05
        case .ambient: 0x21
        case .rainbow: 0x1A
        }
    }

    var usesColor: Bool { self == .solid || self == .breathe || self == .flash }
    var usesSpeed: Bool { self == .breathe || self == .flash || self == .ambient || self == .rainbow }
    var isAnimated: Bool { self != .solid && self != .scenes }
    var isSpectrum: Bool { self == .ambient || self == .rainbow }

    var category: LightingCategory {
        switch self {
        case .solid, .breathe, .flash: .color
        case .ambient, .rainbow: .spectrum
        case .scenes: .scenes
        }
    }

    init?(hardwareMode: UInt8) {
        switch hardwareMode {
        case 0x01: self = .solid
        case 0x02: self = .breathe
        case 0x05: self = .flash
        case 0x21: self = .ambient
        case 0x1A: self = .rainbow
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
        Swatch("Burgundy", 150, 0, 55),
        Swatch("Orange", 255, 110, 0),
        Swatch("Violet", 110, 0, 255),
        Swatch("Magenta", 255, 0, 150),
        Swatch("Teal", 0, 200, 170),
        Swatch("Ice", 170, 215, 255),
    ]
}

/// What the app knows about a monitor model beyond what the monitor reports itself.
/// Every field is optional polish: an unknown MSI monitor still works, it just gets
/// the generic preview, asks before its first write, and restores to its first-seen state.
struct MonitorModel {
    let name: String
    var productPage: URL? = nil
    /// Resources base name of a rear product photo plus "-leds" mask, if one exists.
    var rearPhoto: String? = nil
    /// Lighting packet as shipped, if captured from a new unit.
    var factory: [UInt8]? = nil
    /// Lighting writes have been confirmed on real hardware.
    var verified = false

    static func lookup(_ name: String) -> MonitorModel {
        switch name {
        case "MPG 274URDFW E16M":
            return MonitorModel(name: name,
                                productPage: URL(string: "https://www.msi.com/Monitor/MPG-274URDFW-E16M"),
                                rearPhoto: "mpg274urdfw-rear",
                                factory: mpg274urdfwFactory,
                                verified: true)
        default:
            return MonitorModel(name: name)
        }
    }

    /// Read from a new MPG 274URDFW E16M: MSI's ambient effect (0x21), red, brightness 80,
    /// one LED in group 0 and twenty-two in group 1.
    private static let mpg274urdfwFactory: [UInt8] = {
        var p = [UInt8](repeating: 0, count: 168)
        p[0] = 0x72
        let header: [UInt8] = [0x21, 0xFF, 0x00, 0x00, 0x00, 0x50, 0x00, 0xFF, 0x00, 0x80, 0x00]
        for group in 0..<2 {
            for (i, byte) in header.enumerated() { p[1 + 11 * group + i] = byte }
        }
        for offset in [23] + Array(stride(from: 95, through: 158, by: 3)) { p[offset] = 0xFF }
        p[167] = 0x82
        return p
    }()
}

/// The user's choices for one monitor, kept across launches.
struct Selection: Codable {
    var hue: Double
    var saturation: Double
    var value: Double?
    var level: Double?
    var sceneInterval: Double
    var colorMode: String
    var spectrumMode: String
    var inScenes: Bool

    private static func key(_ monitor: String) -> String { "selection.\(monitor)" }

    static func load(for monitor: String) -> Selection? {
        UserDefaults.standard.data(forKey: key(monitor)).flatMap { try? JSONDecoder().decode(Selection.self, from: $0) }
    }

    func save(for monitor: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(monitor)) }
    }
}

/// The first lighting packet seen from a monitor without known factory data, kept so
/// "Restore" always returns it to how it was before this app touched it.
enum OriginalLighting {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MSI Mystic", isDirectory: true)
    }

    private static func file(model: String, serial: String?) -> URL {
        let key = "\(model)-\(serial ?? "unknown")".replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(key + ".bin")
    }

    static func load(model: String, serial: String?) -> [UInt8]? {
        (try? Data(contentsOf: file(model: model, serial: serial))).map { [UInt8]($0) }
    }

    static func save(_ packet: [UInt8], model: String, serial: String?) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(packet).write(to: file(model: model, serial: serial))
    }
}

final class LightController: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var lightingSupported = true
    @Published private(set) var monitor = MonitorModel.lookup("")
    /// True while the app is waiting for permission to write to an untested model.
    @Published var askingToWrite = false
    private var writesAllowed = false

    var hasFactoryData: Bool { monitor.factory != nil }

    @Published var power = true { didSet { restartScenes(); apply() } }
    @Published var mode: LightMode = .solid {
        didSet {
            if mode.category == .color { lastColorMode = mode }
            if mode.category == .spectrum { lastSpectrumMode = mode }
            restartScenes()
            apply()
            saveSelection()
        }
    }

    private var lastColorMode: LightMode = .solid
    private var lastSpectrumMode: LightMode = .ambient

    var category: LightingCategory {
        get { mode.category }
        set {
            guard newValue != mode.category else { return }
            switch newValue {
            case .color: mode = lastColorMode
            case .spectrum: mode = lastSpectrumMode
            case .scenes: mode = .scenes
            }
        }
    }
    /// The chosen color as hue, saturation and value. Value is the color's own depth
    /// (Burgundy is a dark color); `level` is the brightness slider on top of it.
    @Published var hue: Double = 0.072 { didSet { apply(); saveSelection() } }
    @Published var saturation: Double = 1 { didSet { apply(); saveSelection() } }
    @Published var value: Double = 1 { didSet { apply(); saveSelection() } }
    @Published var level: Double = 1 { didSet { apply(); saveSelection() } }
    @Published var speed: Int = 1 { didSet { apply() } }
    @Published var sceneInterval: Double = 5 { didSet { restartScenes(); saveSelection() } }
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
        return HSV(h: hue, s: saturation, v: value).rgb
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

    var colorName: String { activeSwatch?.name ?? "Custom" }

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
        value = hsv.v
    }

    /// The color wheel picks hue and saturation at full depth.
    func beginCustomColor() {
        value = 1
    }

    func restore() {
        guard let reference = device.reference else { return }
        device.sendNow(reference)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.syncFromDevice() }
    }

    func allowWrites() {
        UserDefaults.standard.set(true, forKey: consentKey)
        writesAllowed = true
        askingToWrite = false
        apply()
    }

    func declineWrites() {
        askingToWrite = false
        syncFromDevice()
    }

    // MARK: Device

    private var consentKey: String { "allowWrites.\(monitor.name)" }

    private func connectionChanged(_ isConnected: Bool) {
        connected = isConnected
        guard isConnected else {
            sceneTimer?.invalidate()
            return
        }

        let name = (device.productName ?? "MSI Monitor").replacingOccurrences(of: "MSI Monitor ", with: "")
        monitor = MonitorModel.lookup(name)
        lightingSupported = device.layout != nil
        writesAllowed = monitor.verified || UserDefaults.standard.bool(forKey: consentKey)

        if let factory = monitor.factory, factory.count == device.readRaw()?.count {
            device.reference = factory
        } else if let saved = OriginalLighting.load(model: name, serial: device.serialNumber),
                  saved.count == device.readRaw()?.count {
            device.reference = saved
        } else if let current = device.readRaw() {
            OriginalLighting.save(current, model: name, serial: device.serialNumber)
            device.reference = current
        }
        syncFromDevice()
    }

    /// Pull the monitor's current lighting into the UI. The monitor only stores what it is
    /// showing right now, so choices it can't express (the Color pick while Spectrum or
    /// Scenes is running, the Scenes sequence itself) come from the saved selection.
    private func syncFromDevice() {
        guard let state = device.readState() else { return }
        let saved = Selection.load(for: monitor.name)
        isSyncing = true

        if let saved {
            lastColorMode = LightMode(rawValue: saved.colorMode) ?? .solid
            lastSpectrumMode = LightMode(rawValue: saved.spectrumMode) ?? .ambient
            sceneInterval = saved.sceneInterval
        }

        power = state.mode != 0
        if var m = LightMode(hardwareMode: state.mode) {
            if m == .solid, saved?.inScenes == true { m = .scenes }
            mode = m
        }

        let shownRGB = (Double(state.red) / 255, Double(state.green) / 255, Double(state.blue) / 255)
        let shown = HSV(r: shownRGB.0, g: shownRGB.1, b: shownRGB.2)

        // The saved selection is trusted unless the monitor is in a color mode showing
        // something else (changed from the OSD or another app).
        let savedStillShowing = saved.map { s -> Bool in
            let base = HSV(h: s.hue, s: s.saturation, v: s.value ?? 1).rgb
            let l = s.level ?? 1
            return abs(base.0 * l - shownRGB.0) < 0.02 && abs(base.1 * l - shownRGB.1) < 0.02
                && abs(base.2 * l - shownRGB.2) < 0.02
        } ?? false

        if let saved, mode.category != .color || savedStillShowing {
            hue = saved.hue
            saturation = saved.saturation
            value = saved.value ?? 1
            level = saved.level ?? 1
        } else if shown.v > 0 {
            hue = shown.h
            saturation = shown.s
            value = 1
            level = max(0.05, shown.v)
        }
        if mode.isSpectrum { level = max(0.05, Double(state.brightness) / 100) }
        speed = Int(min(state.speed, 2))

        isSyncing = false
        restartScenes()
    }

    private func saveSelection() {
        guard connected, !isSyncing else { return }
        Selection(hue: hue, saturation: saturation, value: value, level: level,
                  sceneInterval: sceneInterval,
                  colorMode: lastColorMode.rawValue, spectrumMode: lastSpectrumMode.rawValue,
                  inScenes: mode == .scenes)
            .save(for: monitor.name)
    }

    private func apply() {
        guard connected, lightingSupported, !isSyncing else { return }
        guard writesAllowed else {
            askingToWrite = true
            return
        }
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
