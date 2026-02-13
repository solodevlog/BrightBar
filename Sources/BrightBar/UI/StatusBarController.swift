import AppKit
import SwiftUI

/// Manages the NSStatusItem (menu bar icon) and its popover.
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?
    private let brightnessManager: BrightnessManager

    init(brightnessManager: BrightnessManager) {
        self.brightnessManager = brightnessManager

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Configure the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 140)
        popover.behavior = .transient
        popover.animates = true

        let popoverView = BrightnessPopover(brightnessManager: brightnessManager)
        popover.contentViewController = NSHostingController(rootView: popoverView)

        // Configure the button
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "BrightBar") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = img.withSymbolConfiguration(config)
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NSLog("[StatusBar] Menu bar item created")
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            showPopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            if popover.isShown {
                hidePopover()
            } else {
                showPopover()
            }
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Monitor clicks outside the popover to dismiss it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopover()
        }
    }

    private func hidePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // App name header
        let headerItem = NSMenuItem(title: "BrightBar", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // Display list with selection
        let displays = brightnessManager.availableDisplays
        if displays.isEmpty {
            let noDisplayItem = NSMenuItem(title: "No display connected", action: nil, keyEquivalent: "")
            noDisplayItem.isEnabled = false
            menu.addItem(noDisplayItem)
        } else {
            let displaysHeader = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
            displaysHeader.isEnabled = false
            menu.addItem(displaysHeader)

            for display in displays {
                let isActive = display.index == brightnessManager.activeDisplayIndex
                let title = isActive
                    ? "\(display.name) — \(Int(brightnessManager.brightness * 100))%"
                    : display.name

                let item = NSMenuItem(title: title, action: #selector(selectDisplay(_:)), keyEquivalent: "")
                item.target = self
                item.tag = display.index
                item.state = isActive ? .on : .off
                item.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit BrightBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click goes to popover again
        statusItem.menu = nil
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        brightnessManager.selectDisplay(at: sender.tag)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
