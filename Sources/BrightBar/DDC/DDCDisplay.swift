import Foundation
import IOKit
import CoreGraphics
import AppKit

// MARK: - DDC/CI Protocol Constants

/// VCP (Virtual Control Panel) feature codes per MCCS standard
enum VCPCode: UInt8 {
    case brightness = 0x10
    case contrast   = 0x12
    case volume     = 0x62
}

/// DDC/CI I2C 7-bit address (standard)
private let kDDCI2CAddress: UInt32 = 0x37

/// DDC data address / source address (host, per DDC/CI spec).
/// Passed as the sub-address parameter to IOAVServiceRead/WriteI2C.
private let kDDCDataAddress: UInt32 = 0x51

/// Slave write address for checksum calculation (0x37 << 1)
private let kSlaveWriteAddress: UInt8 = 0x6E

// MARK: - IOAVService bridging (Apple Silicon private API)

/// Resolved IOAVService symbols. Logged once at startup.
enum IOAVBridge {
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias ReadI2CFn  = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    typealias WriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn

    static let createWithService: CreateWithServiceFn? = resolve("IOAVServiceCreateWithService")
    static let readI2C:  ReadI2CFn?  = resolve("IOAVServiceReadI2C")
    static let writeI2C: WriteI2CFn? = resolve("IOAVServiceWriteI2C")

    /// Log which symbols were found.
    static func logAvailability() {
        NSLog("[IOAVBridge] CreateWithService: \(createWithService != nil ? "OK" : "MISSING")")
        NSLog("[IOAVBridge] ReadI2C: \(readI2C != nil ? "OK" : "MISSING")")
        NSLog("[IOAVBridge] WriteI2C: \(writeI2C != nil ? "OK" : "MISSING")")
    }

    private static func resolve<T>(_ name: String) -> T? {
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            NSLog("[IOAVBridge] dlopen failed")
            return nil
        }
        guard let sym = dlsym(handle, name) else {
            NSLog("[IOAVBridge] Symbol not found: \(name)")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }
}

// MARK: - DDCDisplay

/// Represents a single external display controllable via DDC/CI.
final class DDCDisplay {

    let displayID: CGDirectDisplayID
    let name: String
    private let service: io_service_t
    private let avService: CFTypeRef

    /// Maximum brightness reported by the monitor (typically 100).
    private(set) var maxBrightness: Int = 100

    /// Whether DDC communication has been verified.
    private(set) var ddcVerified: Bool = false

    // MARK: - Init

    private init(displayID: CGDirectDisplayID, service: io_service_t, avService: CFTypeRef, name: String, knownMax: Int? = nil) {
        self.displayID = displayID
        self.service = service
        self.avService = avService
        self.name = name

        // Try reading current brightness
        if let (cur, maxVal) = readVCP(.brightness) {
            self.maxBrightness = max(Int(maxVal), 1)
            self.ddcVerified = true
            NSLog("[DDC] Display ready (full DDC): \(name) — brightness \(cur)/\(maxVal)")
        } else if let max = knownMax {
            self.maxBrightness = max
            self.ddcVerified = true  // write-only mode
            NSLog("[DDC] Display ready (write-only): \(name) — max brightness assumed \(max)")
        } else {
            // Default: most monitors have max brightness 100
            self.maxBrightness = 100
            self.ddcVerified = true
            NSLog("[DDC] Display ready (default max=100): \(name)")
        }
    }

    deinit {
        IOObjectRelease(service)
    }

    // MARK: - Factory: discover all DDC-capable services

    /// Discover all external displays with DDC support.
    /// Returns one DDCDisplay per working IOAVService.
    static func discoverAll(externalDisplayIDs: [CGDirectDisplayID]) -> [DDCDisplay] {
        IOAVBridge.logAvailability()

        guard let createFn = IOAVBridge.createWithService else {
            NSLog("[DDC] IOAVServiceCreateWithService not available — DDC disabled")
            return []
        }

        // Collect all candidate AV services
        var avServices: [(service: io_service_t, avService: CFTypeRef)] = []

        for className in ["DCPAVServiceProxy", "AppleCLCD2"] {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(className) else { continue }
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
                NSLog("[DDC] No services for class \(className)")
                continue
            }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                NSLog("[DDC] Found service: \(className) (id=\(service))")
                if let ref = createFn(kCFAllocatorDefault, service) {
                    let avSvc = ref.takeRetainedValue()
                    avServices.append((service: service, avService: avSvc))
                } else {
                    NSLog("[DDC] IOAVServiceCreateWithService returned nil for service \(service)")
                    IOObjectRelease(service)
                }
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        NSLog("[DDC] Total AV services found: \(avServices.count), external displays: \(externalDisplayIDs.count)")

        if avServices.isEmpty {
            return []
        }

        // Strategy: try to pair each AV service with an external display ID.
        // For each AV service, test DDC write+read. If it works, pair it
        // with a display ID (by EDID match or positional fallback).
        var results: [DDCDisplay] = []
        var usedDisplayIDs = Set<CGDirectDisplayID>()

        for (service, avSvc) in avServices {
            // Test DDC: try a full read first, fall back to write-only test
            let readResult = testReadBrightness(avService: avSvc)
            let writeWorks = testDDCWrite(avService: avSvc)

            if readResult == nil && !writeWorks {
                NSLog("[DDC] DDC completely failed on service \(service) — skipping")
                IOObjectRelease(service)
                continue
            }

            if let (cur, max) = readResult {
                NSLog("[DDC] DDC read+write OK on service \(service): brightness \(cur)/\(max)")
            } else {
                NSLog("[DDC] DDC write OK but read failed on service \(service) — using write-only mode")
            }

            // Try to match by EDID
            var matchedID: CGDirectDisplayID?
            let edid = readEDID(from: service)
            if edid.count >= 18 {
                let edidVendor = UInt32(edid[8]) << 8 | UInt32(edid[9])
                let edidProduct = UInt32(edid[10]) | UInt32(edid[11]) << 8

                for id in externalDisplayIDs where !usedDisplayIDs.contains(id) {
                    if CGDisplayVendorNumber(id) == edidVendor && CGDisplayModelNumber(id) == edidProduct {
                        matchedID = id
                        break
                    }
                }
            }

            // Fallback: use first unused display ID
            if matchedID == nil {
                matchedID = externalDisplayIDs.first(where: { !usedDisplayIDs.contains($0) })
            }

            guard let displayID = matchedID else {
                NSLog("[DDC] No display ID left to pair with service \(service)")
                IOObjectRelease(service)
                continue
            }

            usedDisplayIDs.insert(displayID)

            let name = resolveDisplayName(for: service) ?? displayName(for: displayID)
            let display = DDCDisplay(displayID: displayID, service: service, avService: avSvc, name: name)
            results.append(display)
        }

        return results
    }

    // MARK: - Public API

    /// Read current brightness (0...maxBrightness).
    func readBrightness() -> Int? {
        guard let (current, _) = readVCP(.brightness) else { return nil }
        return Int(current)
    }

    /// Write brightness value (0...maxBrightness).
    @discardableResult
    func writeBrightness(_ value: Int) -> Bool {
        let clamped = max(0, min(value, maxBrightness))
        return writeVCP(.brightness, value: UInt16(clamped))
    }

    // MARK: - VCP Read / Write

    private func readVCP(_ code: VCPCode) -> (current: UInt16, maximum: UInt16)? {
        return DDCDisplay.vcpRead(avService: avService, code: code)
    }

    private func writeVCP(_ code: VCPCode, value: UInt16) -> Bool {
        return DDCDisplay.vcpWrite(avService: avService, code: code, value: value)
    }

    // MARK: - DDC Communication (following AppleSiliconDDC convention)
    //
    // Key insight: IOAVServiceWrite/ReadI2C on Apple Silicon expects
    // the DDC source address (0x51) as the I2C sub-address parameter,
    // NOT embedded in the packet data.
    //
    // Packet format:
    //   [length|0x80, opcode, data..., checksum]
    // where opcode = number of data bytes (coincidentally equals DDC opcodes:
    //   0x01 = VCP Get, 0x03 = VCP Set)

    /// Perform DDC I2C communication with retries (per AppleSiliconDDC pattern).
    /// - send: command bytes (e.g. [0x10] for Get brightness, [0x10, 0x00, val] for Set)
    /// - reply: pre-allocated buffer (empty for write-only)
    /// Returns true on success.
    private static func performDDC(avService: CFTypeRef,
                                   send: [UInt8],
                                   replySize: Int,
                                   numWriteCycles: Int = 2,
                                   numRetries: Int = 4,
                                   writeSleep: UInt32 = 10_000,
                                   readSleep: UInt32 = 50_000,
                                   retrySleep: UInt32 = 20_000) -> [UInt8]? {
        guard let writeFn = IOAVBridge.writeI2C else { return nil }

        // Build packet: [length|0x80, opcode(=send.count), data..., checksum]
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [UInt8(0)]

        // Checksum = slave_write_addr ^ dataAddress(for writes only) ^ packet_bytes
        // For reads (send.count==1): chk = 0x6E
        // For writes (send.count>1): chk = 0x6E ^ 0x51
        let chk: UInt8 = send.count == 1
            ? kSlaveWriteAddress
            : kSlaveWriteAddress ^ UInt8(kDDCDataAddress)

        var crc = chk
        for i in 0..<(packet.count - 1) { crc ^= packet[i] }
        packet[packet.count - 1] = crc

        let packetHex = packet.map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[DDC] Sending packet (sub=0x51): \(packetHex)")

        var success = false

        for attempt in 1...(numRetries + 1) {
            // Write phase: send packet multiple times (some monitors need repeated writes)
            for _ in 1...max(numWriteCycles, 1) {
                usleep(writeSleep)
                let wr = writeFn(avService, kDDCI2CAddress, kDDCDataAddress, &packet, UInt32(packet.count))
                success = (wr == kIOReturnSuccess)
            }

            // Read phase (if reply expected)
            if replySize > 0 {
                guard let readFn = IOAVBridge.readI2C else { return nil }
                usleep(readSleep)

                var reply = [UInt8](repeating: 0, count: replySize)
                let rr = readFn(avService, kDDCI2CAddress, kDDCDataAddress, &reply, UInt32(reply.count))
                if rr == kIOReturnSuccess {
                    // Validate checksum: chk=0x50 ^ all_bytes[0..n-2] should equal bytes[n-1]
                    var replyChk: UInt8 = 0x50
                    for i in 0..<(reply.count - 1) { replyChk ^= reply[i] }
                    if replyChk == reply[reply.count - 1] {
                        let hexStr = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
                        NSLog("[DDC] Valid reply (attempt \(attempt)): \(hexStr)")
                        return reply
                    } else {
                        let hexStr = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
                        NSLog("[DDC] Reply checksum mismatch (attempt \(attempt)): \(hexStr) (expected chk=\(String(format: "%02X", replyChk)), got=\(String(format: "%02X", reply[reply.count - 1])))")
                    }
                } else {
                    NSLog("[DDC] Read error (attempt \(attempt)): \(hex(rr))")
                }
            } else if success {
                NSLog("[DDC] Write OK (attempt \(attempt))")
                return []  // empty = write-only success
            }

            usleep(retrySleep)
        }

        NSLog("[DDC] Communication failed after retries")
        return nil
    }

    /// Static VCP read (used for testing before DDCDisplay is constructed).
    private static func vcpRead(avService: CFTypeRef, code: VCPCode) -> (current: UInt16, maximum: UInt16)? {
        // send = [vcp_code] → opcode = 0x01 = VCP Get
        guard let reply = performDDC(avService: avService, send: [code.rawValue], replySize: 11) else {
            return nil
        }

        // Standard DDC VCP Reply (11 bytes from sub-address 0x51):
        // [source(0x6E), len(0x88), 0x02, result, vcp, type, maxH, maxL, curH, curL, chk]
        guard reply.count >= 11, reply[2] == 0x02, reply[3] == 0x00 else {
            let hexStr = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
            NSLog("[DDC] Unexpected VCP reply format: \(hexStr)")
            return nil
        }

        let maxVal = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let curVal = UInt16(reply[8]) << 8 | UInt16(reply[9])

        NSLog("[DDC] VCP 0x\(String(format: "%02X", code.rawValue)): current=\(curVal) max=\(maxVal)")
        return (current: curVal, maximum: maxVal)
    }

    /// Static VCP write.
    private static func vcpWrite(avService: CFTypeRef, code: VCPCode, value: UInt16) -> Bool {
        // send = [vcp_code, val_hi, val_lo] → opcode = 0x03 = VCP Set
        let send: [UInt8] = [code.rawValue, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        return performDDC(avService: avService, send: send, replySize: 0) != nil
    }

    /// Test DDC by doing a full brightness read.
    private static func testReadBrightness(avService: CFTypeRef) -> (current: UInt16, maximum: UInt16)? {
        return vcpRead(avService: avService, code: .brightness)
    }

    /// Test DDC write: read current, write slightly different, restore.
    private static func testDDCWrite(avService: CFTypeRef) -> Bool {
        guard let result = vcpRead(avService: avService, code: .brightness) else {
            NSLog("[DDC] Test write: cannot read current brightness")
            return false
        }
        let original = result.current
        let testValue: UInt16 = (original > 5) ? original - 1 : original + 1
        guard vcpWrite(avService: avService, code: .brightness, value: testValue) else {
            NSLog("[DDC] Test write: write failed")
            return false
        }
        usleep(50_000)
        // Restore
        _ = vcpWrite(avService: avService, code: .brightness, value: original)
        NSLog("[DDC] Test write succeeded (original=\(original), tested=\(testValue), restored)")
        return true
    }

    private static func hex(_ r: IOReturn) -> String {
        String(format: "0x%08X", r)
    }

    // MARK: - EDID

    static func readEDID(from service: io_service_t) -> [UInt8] {
        var current = service
        IOObjectRetain(current)

        for _ in 0..<10 {
            if let data = IORegistryEntryCreateCFProperty(current, "EDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                IOObjectRelease(current)
                return [UInt8](data)
            }
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard kr == kIOReturnSuccess else { break }
            current = parent
        }
        IOObjectRelease(current)
        return []
    }

    // MARK: - Display Name Resolution

    static func resolveDisplayName(for service: io_service_t) -> String? {
        var current = service
        IOObjectRetain(current)
        for _ in 0..<10 {
            if let info = IORegistryEntryCreateCFProperty(current, "DisplayProductName" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: String] {
                IOObjectRelease(current)
                return info["en_US"] ?? info.values.first
            }
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard kr == kIOReturnSuccess else { break }
            current = parent
        }
        IOObjectRelease(current)
        return nil
    }

    static func displayName(for displayID: CGDirectDisplayID) -> String {
        if let name = screenName(for: displayID), !name.isEmpty { return name }
        if let name = ioRegistryName(for: displayID), !name.isEmpty { return name }
        return "External Display"
    }

    private static func screenName(for displayID: CGDirectDisplayID) -> String? {
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            if CGDirectDisplayID(num.uint32Value) == displayID {
                return screen.localizedName
            }
        }
        return nil
    }

    private static func ioRegistryName(for displayID: CGDirectDisplayID) -> String? {
        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)

        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IODisplayConnect") else { return nil }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else { continue }

            let v = (props["DisplayVendorID"] as? NSNumber)?.uint32Value ?? 0
            let p = (props["DisplayProductID"] as? NSNumber)?.uint32Value ?? 0

            if v == vendorID && p == productID {
                if let names = props["DisplayProductName"] as? [String: String] {
                    return names["en_US"] ?? names.values.first
                }
            }
        }
        return nil
    }
}
