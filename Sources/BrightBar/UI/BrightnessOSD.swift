import AppKit

/// Custom on-screen display that mimics the macOS system brightness indicator.
/// Shows a dark rounded rectangle with a sun icon and a segmented progress bar.
final class BrightnessOSD {

    private var window: NSWindow?
    private var hideTimer: Timer?

    // Direct references to subviews (avoiding NSView.tag which is read-only)
    private var iconView: NSImageView?
    private var segments: [NSView] = []

    /// Number of segments in the brightness bar (matches macOS).
    private let segmentCount = 16

    /// Duration to show the OSD before fading out.
    private let displayDuration: TimeInterval = 1.5

    /// Fade-out animation duration.
    private let fadeOutDuration: TimeInterval = 0.3

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

    private func getOrCreateWindow() -> NSWindow {
        if let existing = window {
            return existing
        }

        let osdWidth: CGFloat = 220
        let osdHeight: CGFloat = 70
        let frame = NSRect(x: 0, y: 0, width: osdWidth, height: osdHeight)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.animationBehavior = .utilityWindow
        win.isReleasedWhenClosed = false

        // Background with vibrancy
        let visualEffect = NSVisualEffectView(frame: frame)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true

        win.contentView = visualEffect

        // Build the content hierarchy
        buildOSDContent(in: visualEffect, frame: frame)

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

        // Segmented progress bar
        let barHeight: CGFloat = 8
        let barInset: CGFloat = 20
        let barWidth = frame.width - barInset * 2
        let barY: CGFloat = 14

        let barContainer = NSView(frame: NSRect(x: barInset, y: barY, width: barWidth, height: barHeight))
        barContainer.wantsLayer = true
        barContainer.layer?.cornerRadius = barHeight / 2
        barContainer.layer?.masksToBounds = true
        barContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        container.addSubview(barContainer)

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
            barContainer.addSubview(segment)
            segments.append(segment)
        }
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
        let y = screenFrame.origin.y + 80  // 80pt from the bottom

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Auto-Hide

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let win = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            win.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
    }
}
