import Foundation
import CoreGraphics

/// Discovers and manages external displays.
final class DisplayManager {

    /// The currently active external display.
    private(set) var activeDisplay: DDCDisplay?

    /// Index of the active display in the `displays` array (-1 if none).
    private(set) var activeDisplayIndex: Int = -1

    /// All discovered DDC-capable external displays.
    private(set) var displays: [DDCDisplay] = []

    /// Notification posted when the display list changes.
    static let displaysDidChangeNotification = Notification.Name("DisplayManager.displaysDidChange")

    init() {
        refresh()
        registerForDisplayChanges()
    }

    // MARK: - Public

    /// Re-scan for external displays supporting DDC/CI.
    func refresh() {
        let previousActiveID = activeDisplay?.displayID
        displays.removeAll()

        // 1. Get all online displays from CoreGraphics
        let maxDisplays: UInt32 = 16
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let result = CGGetOnlineDisplayList(maxDisplays, &onlineDisplays, &displayCount)
        guard result == .success else {
            NSLog("[DisplayManager] CGGetOnlineDisplayList failed: \(result)")
            finalize(previousActiveID: previousActiveID)
            return
        }

        // 2. Filter to external displays only
        var externalIDs: [CGDirectDisplayID] = []
        for i in 0..<Int(displayCount) {
            let id = onlineDisplays[i]
            if CGDisplayIsBuiltin(id) == 0 {
                externalIDs.append(id)
                NSLog("[DisplayManager] External display: \(id) (vendor=\(CGDisplayVendorNumber(id)), model=\(CGDisplayModelNumber(id)))")
            }
        }

        NSLog("[DisplayManager] \(externalIDs.count) external display(s), \(displayCount) total")

        if externalIDs.isEmpty {
            finalize(previousActiveID: previousActiveID)
            return
        }

        // 3. Discover DDC-capable displays via IOAVService
        displays = DDCDisplay.discoverAll(externalDisplayIDs: externalIDs)

        NSLog("[DisplayManager] \(displays.count) DDC-capable display(s) found")

        finalize(previousActiveID: previousActiveID)
    }

    /// Switch the active display by index.
    func setActiveDisplay(at index: Int) {
        guard index >= 0, index < displays.count else { return }
        activeDisplayIndex = index
        activeDisplay = displays[index]
        NSLog("[DisplayManager] Active display changed to: \(displays[index].name)")
        NotificationCenter.default.post(name: Self.displaysDidChangeNotification, object: self)
    }

    // MARK: - Private

    private func finalize(previousActiveID: CGDirectDisplayID?) {
        if let prevID = previousActiveID,
           let idx = displays.firstIndex(where: { $0.displayID == prevID }) {
            activeDisplayIndex = idx
            activeDisplay = displays[idx]
        } else if !displays.isEmpty {
            activeDisplayIndex = 0
            activeDisplay = displays[0]
        } else {
            activeDisplayIndex = -1
            activeDisplay = nil
        }

        NotificationCenter.default.post(name: Self.displaysDidChangeNotification, object: self)
    }

    // MARK: - Display Change Monitoring

    private func registerForDisplayChanges() {
        let callback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
            guard flags.contains(.addFlag) || flags.contains(.removeFlag) else { return }
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                manager.refresh()
            }
        }
        CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())
    }
}
