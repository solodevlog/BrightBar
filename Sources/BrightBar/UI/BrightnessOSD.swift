import AppKit

/// Custom on-screen display that mimics the macOS system brightness indicator.
/// Shows a dark rounded rectangle with a sun icon and an interactive segmented progress bar.
/// The user can click/drag on the bar to set brightness directly.
final class BrightnessOSD {

    private var window: NSPanel?
    private var hideTimer: Timer?

    private var iconView: NSImageView?
    private var segments: [NSView] = []
    private var barContainer: NSView?

    /// Number of segments in the brightness bar (matches macOS).
    private let segmentCount = 16

    /// Duration to show the OSD before fading out.
    private let displayDuration: TimeInterval = 2.0

    /// Fade-out animation duration.
    private let fadeOutDuration: TimeInterval = 0.3

    /// Callback when user drags the slider. Parameter is 0.0...1.0.
    var onBrightnessChanged: ((Double) -> Void)?

    /// Track whether user is dragging to prevent auto-hide during drag
    private var isDragging = false

    // MARK: - Public

    /// Show the OSD with a given brightness level (0.0 ... 1.0).
    func show(level: Double) {
        let osdWindow = getOrCreateWindow()
        updateContent(level: level)
        positionWindow(osdWindow)

        osdWindow.alphaValue = 1.0
        osdWindow.orderFrontRegardless()

        scheduleHide()
    }

    // MARK: - Window Management

    private func getOrCreateWindow() -> NSPanel {
        if let existing = window {
            return existing
        }

        let osdWidth: CGFloat = 220
        let osdHeight: CGFloat = 70
        let frame = NSRect(x: 0, y: 0, width: osdWidth, height: osdHeight)

        let win = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        // Allow mouse interaction for the slider
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.animationBehavior = .utilityWindow
        win.isReleasedWhenClosed = false

        // Prevent the panel from stealing focus
        win.hidesOnDeactivate = false
        win.becomesKeyOnlyIfNeeded = true

        // Transparent container as contentView — no background at all
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = nil
        win.contentView = container

        // Rounded visual effect as a subview (NOT as contentView)
        let blur = NSVisualEffectView(frame: frame)
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        // Build the content hierarchy on top of the blur
        buildOSDContent(in: blur, frame: frame)

        self.window = win
        return win
    }

    private func buildOSDContent(in container: NSView, frame: NSRect) {
        // Sun icon
        let iconSize: CGFloat = 26
        let icon = NSImageView(frame: NSRect(
            x: (frame.width - iconSize) / 2,
            y: frame.height - iconSize - 10,
            width: iconSize,
            height: iconSize
        ))

        if let sunImage = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            icon.image = sunImage.withSymbolConfiguration(config)
        }
        icon.contentTintColor = .white
        container.addSubview(icon)
        self.iconView = icon

        // Interactive segmented progress bar
        let barHeight: CGFloat = 8
        let barInset: CGFloat = 20
        let barWidth = frame.width - barInset * 2
        let barY: CGFloat = 14

        let bar = NSView(frame: NSRect(x: barInset, y: barY, width: barWidth, height: barHeight))
        bar.wantsLayer = true
        bar.layer?.cornerRadius = barHeight / 2
        bar.layer?.masksToBounds = true
        bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Expand the click/drag area beyond the tiny 8px bar
        let hitArea = OSDHitAreaView(frame: NSRect(x: barInset - 8, y: barY - 12, width: barWidth + 16, height: barHeight + 24))
        hitArea.barView = bar
        hitArea.osd = self
        container.addSubview(hitArea)
        container.addSubview(bar)

        // Individual segments
        let segmentSpacing: CGFloat = 2
        let totalSpacing = segmentSpacing * CGFloat(segmentCount - 1)
        let segmentWidth = (barWidth - totalSpacing) / CGFloat(segmentCount)

        segments.removeAll()
        for i in 0..<segmentCount {
            let segX = CGFloat(i) * (segmentWidth + segmentSpacing)
            let segment = NSView(frame: NSRect(x: segX, y: 0, width: segmentWidth, height: barHeight))
            segment.wantsLayer = true
            segment.layer?.cornerRadius = 2
            segment.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.addSubview(segment)
            segments.append(segment)
        }

        self.barContainer = bar
    }

    // MARK: - Mouse Interaction

    /// Convert a click/drag x position in the bar to a brightness level.
    fileprivate func handleBarInteraction(locationInBar: CGFloat) {
        guard let bar = barContainer else { return }
        let fraction = max(0.0, min(1.0, Double(locationInBar / bar.bounds.width)))

        // Snap to segment boundaries for clean steps
        let snapped = round(fraction * Double(segmentCount)) / Double(segmentCount)

        updateContent(level: snapped)
        onBrightnessChanged?(snapped)
        scheduleHide()
    }

    fileprivate func beginDrag() {
        isDragging = true
        hideTimer?.invalidate()
    }

    fileprivate func endDrag() {
        isDragging = false
        scheduleHide()
    }

    private func updateContent(level: Double) {
        let filledSegments = Int(round(level * Double(segmentCount)))

        for (i, segment) in segments.enumerated() {
            let isFilled = i < filledSegments
            segment.layer?.backgroundColor = isFilled
                ? NSColor.white.withAlphaComponent(0.9).cgColor
                : NSColor.white.withAlphaComponent(0.15).cgColor
        }

        // Update sun icon based on level
        if let icon = iconView {
            let symbolName: String
            if level <= 0.01 {
                symbolName = "sun.min"
            } else if level < 0.5 {
                symbolName = "sun.min.fill"
            } else {
                symbolName = "sun.max.fill"
            }
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Brightness") {
                let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                icon.image = img.withSymbolConfiguration(config)
            }
        }
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let x = screenFrame.midX - window.frame.width / 2
        let y = screenFrame.origin.y + 80

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Auto-Hide

    private func scheduleHide() {
        guard !isDragging else { return }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let win = window, !isDragging else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            win.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
    }
}

// MARK: - OSD Hit Area View (expanded click/drag target for the thin bar)

/// Invisible view with expanded hit area around the progress bar.
/// Converts mouse events to bar-relative coordinates.
private final class OSDHitAreaView: NSView {

    weak var barView: NSView?
    weak var osd: BrightnessOSD?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        osd?.beginDrag()
        handleMouse(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouse(event)
    }

    override func mouseUp(with event: NSEvent) {
        handleMouse(event)
        osd?.endDrag()
    }

    private func handleMouse(_ event: NSEvent) {
        guard let bar = barView, let osd = osd else { return }
        let pointInSelf = convert(event.locationInWindow, from: nil)
        // Convert to bar's coordinate space
        let pointInBar = bar.convert(pointInSelf, from: self)
        osd.handleBarInteraction(locationInBar: pointInBar.x)
    }

    // Change cursor to indicate interactivity
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
