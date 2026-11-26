// Packet regression tests. Run: ./scripts/test.sh
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    print(ok ? "pass  \(name)" : "FAIL  \(name)")
    if !ok { failures += 1 }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fixture = [UInt8](try! Data(contentsOf: root.appendingPathComponent("Tests/fixtures/mpg274urdfw-factory.bin")))
let model = MonitorModel.lookup("MPG 274URDFW E16M")
let factory = model.factory!

check(factory == fixture, "built-in factory packet matches bytes read from a new monitor")

// The packet builder this app shipped with before layouts were generalized.
let legacyOffsets = [23] + Array(stride(from: 95, through: 158, by: 3))
func legacyPacket(_ s: MSIDevice.State) -> [UInt8] {
    var p = fixture
    for g in 0..<2 {
        let h = 1 + 11 * g
        p[h] = s.mode; p[h + 1] = s.red; p[h + 2] = s.green; p[h + 3] = s.blue
        p[h + 4] = s.speed; p[h + 5] = s.brightness
    }
    for o in legacyOffsets { p[o] = s.red; p[o + 1] = s.green; p[o + 2] = s.blue }
    return p
}

let learned = MSIDevice.populatedLEDs(in: factory, layout: .extended)
check(learned == legacyOffsets, "LED slots learned from the factory packet match the known layout")

let states: [MSIDevice.State] = [
    .init(mode: 0x01, red: 0xFF, green: 0x6E, blue: 0x00, speed: 0, brightness: 100),
    .init(mode: 0x01, red: 0x6E, green: 0x00, blue: 0xFF, speed: 1, brightness: 100),
    .init(mode: 0x02, red: 0x96, green: 0x00, blue: 0x37, speed: 2, brightness: 64),
    .init(mode: 0x21, red: 0xFF, green: 0x00, blue: 0x00, speed: 0, brightness: 80),
    .init(mode: 0x1A, red: 0x00, green: 0xC8, blue: 0xAA, speed: 1, brightness: 100),
    .init(mode: 0x00, red: 0, green: 0, blue: 0, speed: 0, brightness: 0),
]
let identical = states.allSatisfy { MSIDevice.packet(for: $0, reference: factory, ledOffsets: learned) == legacyPacket($0) }
check(identical, "generalized packets are byte-identical to the shipped builder")

let every = states.map { MSIDevice.packet(for: $0, reference: factory, ledOffsets: learned) }
check(every.allSatisfy { $0.count == 168 && $0[0] == 0x72 && $0[167] == 0x82 }, "report ID, size and trailer preserved")

let blank = [UInt8](repeating: 0, count: 168)
check(MSIDevice.populatedLEDs(in: blank, layout: .extended).count == 48, "all-dark reference falls back to every slot")
check(LightingLayout.compact.allLEDOffsets.last! + 2 < LightingLayout.compact.size, "compact layout fits its 78-byte report")
check(LightingLayout.extended.allLEDOffsets.last! + 2 < LightingLayout.extended.size, "extended layout fits its 168-byte report")

// Swatches must survive the hue/saturation/value round trip, or a dark swatch like
// Burgundy gets sent at full intensity and never shows as selected.
let roundTrips = Swatch.all.allSatisfy { s in
    let hsv = HSV(r: s.red, g: s.green, b: s.blue)
    let rgb = HSV(h: hsv.h, s: hsv.s, v: hsv.v).rgb
    return abs(rgb.0 - s.red) < 0.005 && abs(rgb.1 - s.green) < 0.005 && abs(rgb.2 - s.blue) < 0.005
}
check(roundTrips, "every swatch round-trips through HSV exactly")

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) failed.")
exit(failures == 0 ? 0 : 1)
