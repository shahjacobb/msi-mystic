import Foundation
import IOKit.hid

/// The two Mystic Light packet formats MSI monitors use, as documented by msigd.
struct LightingLayout: Equatable {
    let reportID: UInt8
    let size: Int
    let ledsPerGroup: Int

    /// MPG273CQR, MAG274 series, MPG 274URDFW and newer.
    static let extended = LightingLayout(reportID: 0x72, size: 168, ledsPerGroup: 24)
    /// MAG241C/271C/272C/321C series.
    static let compact = LightingLayout(reportID: 0x71, size: 78, ledsPerGroup: 9)

    static let all = [extended, compact]

    /// Byte offset of every LED's RGB triplet, both groups.
    var allLEDOffsets: [Int] { (0..<(2 * ledsPerGroup)).map { 23 + $0 * 3 } }
}

/// Talks to the Mystic Light controller in an MSI monitor over USB HID.
///
/// The only thing this type writes is the monitor's lighting feature report (0x72 or 0x71),
/// always built on top of a reference packet that came from the monitor itself.
/// Writes are coalesced so a fast drag produces at most ~8 packets per second.
final class MSIDevice {
    static let vendorID = 0x1462
    static let productID = 0x3FA4

    struct State {
        var mode: UInt8
        var red: UInt8, green: UInt8, blue: UInt8
        var speed: UInt8
        var brightness: UInt8
    }

    var onConnectionChange: ((Bool) -> Void)?
    private(set) var productName: String?
    private(set) var serialNumber: String?
    private(set) var layout: LightingLayout?

    /// Packet every write starts from. Bytes the app doesn't control are copied from it unchanged.
    var reference: [UInt8]? {
        didSet { ledOffsets = Self.populatedLEDs(in: reference, layout: layout) }
    }
    private var ledOffsets: [Int] = []

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var pending: [UInt8]?
    private var lastWritten: [UInt8]?
    private var flushTimer: Timer?

    var isConnected: Bool { device != nil }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<MSIDevice>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<MSIDevice>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    // MARK: Connection

    private func attach(_ candidate: IOHIDDevice) {
        guard device == nil else { return }
        guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        device = candidate
        productName = IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String
        serialNumber = IOHIDDeviceGetProperty(candidate, kIOHIDSerialNumberKey as CFString) as? String
        layout = LightingLayout.all.first { readRaw(using: $0) != nil }
        reference = nil
        lastWritten = nil
        onConnectionChange?(true)
    }

    private func detach(_ removed: IOHIDDevice) {
        guard let current = device, current === removed else { return }
        device = nil
        layout = nil
        reference = nil
        pending = nil
        onConnectionChange?(false)
    }

    // MARK: Reading

    func readRaw() -> [UInt8]? {
        layout.flatMap(readRaw(using:))
    }

    private func readRaw(using layout: LightingLayout) -> [UInt8]? {
        guard let device else { return nil }
        var buffer = [UInt8](repeating: 0, count: layout.size)
        buffer[0] = layout.reportID
        var length = CFIndex(layout.size)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(layout.reportID), &buffer, &length)
        guard result == kIOReturnSuccess, length == layout.size, buffer[0] == layout.reportID else { return nil }
        return buffer
    }

    func readState() -> State? {
        guard let p = readRaw() else { return nil }
        return State(mode: p[1], red: p[2], green: p[3], blue: p[4], speed: p[5], brightness: p[6])
    }

    // MARK: Writing

    /// Queue a state. Only the most recent one is sent on the next tick.
    func send(_ state: State) {
        pending = packet(for: state)
    }

    /// Send a complete packet immediately, bypassing the coalescing timer.
    func sendNow(_ packet: [UInt8]) {
        pending = nil
        write(packet)
    }

    private func flush() {
        guard let packet = pending else { return }
        pending = nil
        if packet != lastWritten { write(packet) }
    }

    private func write(_ packet: [UInt8]) {
        guard let device, let layout, packet.count == layout.size, packet[0] == layout.reportID else { return }
        let result = packet.withUnsafeBufferPointer { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(layout.reportID),
                                 bytes.baseAddress!, bytes.count)
        }
        if result == kIOReturnSuccess { lastWritten = packet }
    }

    func packet(for state: State) -> [UInt8]? {
        guard let reference else { return nil }
        return Self.packet(for: state, reference: reference, ledOffsets: ledOffsets)
    }

    static func packet(for state: State, reference: [UInt8], ledOffsets: [Int]) -> [UInt8] {
        var p = reference
        for group in 0..<2 {
            let h = 1 + 11 * group
            p[h] = state.mode
            p[h + 1] = state.red
            p[h + 2] = state.green
            p[h + 3] = state.blue
            p[h + 4] = state.speed
            p[h + 5] = state.brightness
        }
        for offset in ledOffsets {
            p[offset] = state.red
            p[offset + 1] = state.green
            p[offset + 2] = state.blue
        }
        return p
    }

    /// LED slots that hold a color in the reference packet. Monitors leave unused slots at zero,
    /// so this recovers the physical LED layout without a per-model table. If every slot is
    /// zero (lighting was off), fall back to all slots, as msigd does.
    static func populatedLEDs(in reference: [UInt8]?, layout: LightingLayout?) -> [Int] {
        guard let reference, let layout else { return [] }
        let all = layout.allLEDOffsets
        let lit = all.filter { reference[$0] != 0 || reference[$0 + 1] != 0 || reference[$0 + 2] != 0 }
        return lit.isEmpty ? all : lit
    }
}
