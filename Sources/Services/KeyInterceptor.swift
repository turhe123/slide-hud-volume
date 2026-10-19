import AppKit
import ApplicationServices
import CoreGraphics

/// Owns the session-level CGEventTap that captures the hardware volume/mute keys,
/// applies the change itself and swallows the event so macOS shows no stock overlay.
@MainActor
final class KeyInterceptor: ObservableObject {
    static let shared = KeyInterceptor()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pollTimer: Timer?

    // NX_SYSDEFINED event type, aux-control-button subtype and key codes from IOKit's ev_keymap.h.
    private static let systemDefinedType: UInt32 = 14
    private static let auxControlSubtype: Int16 = 8
    private static let soundUp = 0, soundDown = 1, mute = 7

    /// Checks permission (optionally prompting) and starts the tap, polling until access is granted.
    func start(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if isTrusted {
            installTap()
        } else if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let interceptor = KeyInterceptor.shared
                    guard AXIsProcessTrusted() else { return }
                    interceptor.pollTimer?.invalidate()
                    interceptor.pollTimer = nil
                    interceptor.isTrusted = true
                    interceptor.installTap()
                }
            }
        }
    }

    func openAccessibilitySettings() {
        start(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, _ in
                                               MainActor.assumeIsolated {
                                                   KeyInterceptor.shared.handle(type: type, event: event)
                                               }
                                           }, userInfo: nil) else {
            isRunning = false
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isRunning = true
    }

    /// Returns nil to swallow a handled key, or the original event to let it pass through.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let passthrough = Unmanaged.passUnretained(event)
        guard type.rawValue == Self.systemDefinedType,
              UserDefaults.standard.bool(forKey: Prefs.takeover),
              let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == Self.auxControlSubtype else { return passthrough }

        let data = ns.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyDown = ((data & 0xFF00) >> 8) == 0xA
        guard [Self.soundUp, Self.soundDown, Self.mute].contains(keyCode) else { return passthrough }

        let audio = AudioController.shared
        audio.refresh()
        guard audio.hasVolumeControl else {
            if keyDown { HUDController.shared.show(message: "Device has no volume control") }
            return passthrough
        }
        guard keyDown else { return nil }

        let step = ns.modifierFlags.contains(.option) ? StepSize.extraFine.amount : StepSize.current.amount
        switch keyCode {
        case Self.soundUp: audio.adjust(by: step)
        case Self.soundDown: audio.adjust(by: -step)
        default: audio.toggleMute()
        }
        HUDController.shared.show()
        return nil
    }
}
