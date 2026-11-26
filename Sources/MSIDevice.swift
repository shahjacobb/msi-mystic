import Foundation
import IOKit.hid

/// Talks to the Mystic Light controller in an MSI monitor over USB HID.
///
/// The only thing this type can send is feature report 0x72: a 168-byte packet
/// built from the monitor's factory template. Writes are coalesced so a fast
/// drag on the color wheel produces at most ~8 packets per second.
final class MSIDevice {
    static let vendorID = 0x1462
    static let productID = 0x3FA4

    static let reportID: UInt8 = 0x72
    static let reportSize = 168

    /// Byte offsets of the RGB triplet for every physical LED.
    /// One LED in group 0, twenty-two in group 1.
    static let ledOffsets: [Int] = [23] + Array(stride(from: 95, through: 158, by: 3))

    /// The packet this monitor shipped with: MSI's ambient effect (0x21), red, brightness 80.
    static let factory: [UInt8] = {
        var p = [UInt8](repeating: 0, count: reportSize)
        p[0] = reportID
        let header: [UInt8] = [0x21, 0xFF, 0x00, 0x00, 0x00, 0x50, 0x00, 0xFF, 0x00, 0x80, 0x00]
        for group in 0..<2 {
            for (i, byte) in header.enumerated() { p[1 + 11 * group + i] = byte }
        }
        for offset in ledOffsets { p[offset] = 0xFF }
        p[167] = 0x82
        return p
    }()

    struct State {
        var mode: UInt8
        var red: UInt8, green: UInt8, blue: UInt8
        var speed: UInt8
        var brightness: UInt8
    }

    var onConnectionChange: ((Bool) -> Void)?
    private(set) var productName: String?

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
        lastWritten = nil
        onConnectionChange?(true)
    }

    private func detach(_ removed: IOHIDDevice) {
        guard let current = device, current === removed else { return }
        device = nil
        pending = nil
        onConnectionChange?(false)
    }

    // MARK: Reading

    func readState() -> State? {
        guard let device else { return nil }
        var buffer = [UInt8](repeating: 0, count: Self.reportSize)
        buffer[0] = Self.reportID
        var length = CFIndex(Self.reportSize)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(Self.reportID), &buffer, &length)
        guard result == kIOReturnSuccess, length == Self.reportSize, buffer[0] == Self.reportID else { return nil }
        return State(mode: buffer[1], red: buffer[2], green: buffer[3], blue: buffer[4],
                     speed: buffer[5], brightness: buffer[6])
    }

    // MARK: Writing

    /// Queue a state. Only the most recent one is sent on the next tick.
    func send(_ state: State) {
        pending = Self.packet(for: state)
    }

    /// Send immediately, bypassing the coalescing timer.
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
        guard let device, packet.count == Self.reportSize, packet[0] == Self.reportID else { return }
        let result = packet.withUnsafeBufferPointer { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(Self.reportID),
                                 bytes.baseAddress!, bytes.count)
        }
        if result == kIOReturnSuccess { lastWritten = packet }
    }

    static func packet(for state: State) -> [UInt8] {
        var p = factory
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
}
