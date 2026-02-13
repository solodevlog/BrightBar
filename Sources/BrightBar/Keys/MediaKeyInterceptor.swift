import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - Media Key Constants (from IOKit/hidsystem/ev_keymap.h)

/// NX_KEYTYPE constants for brightness keys
private let NX_KEYTYPE_BRIGHTNESS_UP: Int   = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int = 3

// MARK: - MediaKeyInterceptor

/// Intercepts hardware brightness keys (F1/F2) via CGEventTap
/// and routes them to the BrightnessManager.
final class MediaKeyInterceptor {

    private let brightnessManager: BrightnessManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(brightnessManager: BrightnessManager) {
        self.brightnessManager = brightnessManager
    }

    // MARK: - Public

    /// Start intercepting brightness keys. Requires Accessibility permission.
    func start() {
        // Check/request accessibility permission
        if !checkAccessibility() {
            NSLog("[MediaKeyInterceptor] Accessibility permission not granted. Requesting...")
            requestAccessibility()
        }

        createEventTap()
    }

    /// Stop intercepting brightness keys.
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        NSLog("[MediaKeyInterceptor] Stopped")
    }

    // MARK: - Private

    private func createEventTap() {
        // NX_SYSDEFINED events = type 14 (NSEvent.EventType.systemDefined)
        let eventMask: CGEventMask = 1 << 14

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("[MediaKeyInterceptor] Failed to create event tap. Grant Accessibility permission in System Settings.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("[MediaKeyInterceptor] Event tap active")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap being disabled by the system (e.g., timeout)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("[MediaKeyInterceptor] Event tap was disabled, re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Convert CGEvent to NSEvent for easier parsing of system-defined events
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        // Must be system-defined with subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        guard nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1

        // Extract key code (bits 16-23 of data1) and key state
        let keyCode = (data1 >> 16) & 0xFF
        let keyFlags = (data1 >> 8) & 0xFF
        let keyState = keyFlags & 0x0F
        let keyDown = keyState == 0x0A  // 0x0A = key down

        // Only handle brightness keys
        guard keyCode == NX_KEYTYPE_BRIGHTNESS_UP || keyCode == NX_KEYTYPE_BRIGHTNESS_DOWN else {
            return Unmanaged.passUnretained(event)
        }

        // Act on key down only
        if keyDown {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if keyCode == NX_KEYTYPE_BRIGHTNESS_UP {
                    self.brightnessManager.increaseBrightness()
                } else {
                    self.brightnessManager.decreaseBrightness()
                }
            }
        }

        // Consume the event (both key-down and key-up) to prevent system handling
        return nil
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
