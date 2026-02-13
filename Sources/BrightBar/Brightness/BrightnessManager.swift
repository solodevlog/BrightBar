import Foundation
import Combine
import CoreGraphics

/// Central brightness management logic.
/// Bridges between input (keys, slider) and output (DDC, OSD).
final class BrightnessManager: ObservableObject {

    // MARK: - Published State

    /// Current brightness of the active display as a percentage (0.0 ... 1.0).
    @Published private(set) var brightness: Double = 0.5

    /// Active display name for the UI.
    @Published private(set) var displayName: String = "No Display"

    /// Whether any DDC-capable display is connected.
    @Published private(set) var isDisplayConnected: Bool = false

    /// All available display names (for the picker).
    @Published private(set) var availableDisplays: [DisplayInfo] = []

    /// Index of the currently active display.
    @Published private(set) var activeDisplayIndex: Int = -1

    // MARK: - Types

    struct DisplayInfo: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
        let resolution: String   // e.g. "3840×2160"
        let refreshRate: String  // e.g. "60 Hz"
        let index: Int
    }

    // MARK: - Configuration

    /// Brightness step for each key press (6.25% = 1/16, matches macOS 16-segment OSD).
    let step: Double = 1.0 / 16.0

    // MARK: - Private

    let displayManager: DisplayManager
    private let osd = BrightnessOSD()
    private var debounceWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Per-display brightness cache: displayID -> (brightness percentage, raw value).
    private var brightnessCache: [CGDirectDisplayID: (percentage: Double, rawValue: Int)] = [:]

    init() {
        self.displayManager = DisplayManager()
        setupObservers()
        syncFromDisplay()
    }

    // MARK: - Public API

    /// Increase brightness by one step (called by key interceptor).
    func increaseBrightness() {
        let newValue = min(brightness + step, 1.0)
        setBrightness(newValue, showOSD: true)
    }

    /// Decrease brightness by one step (called by key interceptor).
    func decreaseBrightness() {
        let newValue = max(brightness - step, 0.0)
        setBrightness(newValue, showOSD: true)
    }

    /// Set brightness to an exact value (called by slider).
    /// - Parameters:
    ///   - value: Brightness percentage (0.0 ... 1.0)
    ///   - showOSD: Whether to show the on-screen display
    func setBrightness(_ value: Double, showOSD: Bool = false) {
        let clamped = max(0.0, min(value, 1.0))
        brightness = clamped

        // NOTE: Do NOT update brightnessCache here.
        // The cache is updated only after a successful DDC write in writeToDisplay().
        // Updating it prematurely would cause writeToDisplay() to skip the actual write.

        if showOSD {
            DispatchQueue.main.async { [weak self] in
                self?.osd.show(level: clamped)
            }
        }

        debouncedWriteToDisplay(clamped)
    }

    /// Switch the active display by index.
    func selectDisplay(at index: Int) {
        displayManager.setActiveDisplay(at: index)
        activeDisplayIndex = index

        guard let display = displayManager.activeDisplay else { return }

        displayName = display.name

        // Restore cached brightness or read from display
        if let cached = brightnessCache[display.displayID] {
            brightness = cached.percentage
        } else {
            syncFromDisplay()
        }
    }

    /// Force re-read brightness from the display.
    func syncFromDisplay() {
        updateDisplayList()

        guard let display = displayManager.activeDisplay else {
            isDisplayConnected = false
            displayName = "No Display"
            return
        }

        isDisplayConnected = true
        displayName = display.name
        activeDisplayIndex = displayManager.activeDisplayIndex

        // Read in background to avoid blocking main thread
        let displayID = display.displayID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if let currentValue = display.readBrightness() {
                let percentage = Double(currentValue) / Double(display.maxBrightness)
                DispatchQueue.main.async {
                    self.brightness = percentage
                    self.brightnessCache[displayID] = (percentage: percentage, rawValue: currentValue)
                    NSLog("[BrightnessManager] Synced brightness: \(currentValue)/\(display.maxBrightness) (\(Int(percentage * 100))%%)")
                }
            } else {
                NSLog("[BrightnessManager] Failed to read brightness from \(display.name)")
            }
        }
    }

    // MARK: - Private

    private func setupObservers() {
        NotificationCenter.default.publisher(for: DisplayManager.displaysDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncFromDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateDisplayList() {
        availableDisplays = displayManager.displays.enumerated().map { index, display in
            let (res, hz) = Self.displayModeInfo(for: display.displayID)
            return DisplayInfo(id: display.displayID, name: display.name, resolution: res, refreshRate: hz, index: index)
        }
    }

    /// Read resolution and refresh rate from CoreGraphics display mode.
    private static func displayModeInfo(for displayID: CGDirectDisplayID) -> (resolution: String, refreshRate: String) {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return ("—", "—")
        }

        let w = mode.pixelWidth
        let h = mode.pixelHeight
        let resolution = "\(w)\u{00D7}\(h)"  // e.g. "3840×2160"

        let hz = mode.refreshRate
        let refreshRate: String
        if hz > 0 {
            if hz == hz.rounded() {
                refreshRate = "\(Int(hz)) Hz"
            } else {
                refreshRate = String(format: "%.1f Hz", hz)
            }
        } else {
            refreshRate = "—"
        }

        return (resolution, refreshRate)
    }

    /// Debounced write to avoid flooding the DDC bus.
    private func debouncedWriteToDisplay(_ percentage: Double) {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.writeToDisplay(percentage)
        }
        debounceWorkItem = workItem

        // 50ms debounce
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func writeToDisplay(_ percentage: Double) {
        guard let display = displayManager.activeDisplay else {
            NSLog("[BrightnessManager] writeToDisplay: no active display")
            return
        }

        let rawValue = Int(round(percentage * Double(display.maxBrightness)))

        // Skip if value hasn't changed
        if let cached = brightnessCache[display.displayID], cached.rawValue == rawValue {
            NSLog("[BrightnessManager] writeToDisplay: skipped (cached rawValue=\(rawValue))")
            return
        }

        NSLog("[BrightnessManager] writeToDisplay: writing rawValue=\(rawValue) (percentage=\(Int(percentage * 100))%%) to \(display.name)")
        if display.writeBrightness(rawValue) {
            brightnessCache[display.displayID] = (percentage: percentage, rawValue: rawValue)
            NSLog("[BrightnessManager] writeToDisplay: success")
        } else {
            NSLog("[BrightnessManager] writeToDisplay: FAILED")
        }
    }
}
