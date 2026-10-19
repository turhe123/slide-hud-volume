import AppKit
import SwiftUI

/// Borderless, non-activating panel that never steals focus and floats over full-screen apps.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first click so dragging works without activating the app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Transient state the HUD view renders besides the audio state.
final class HUDModel: ObservableObject {
    @Published var message: String?
    @Published var isDragging = false
}

/// Positions, shows and fades the volume HUD on the display containing the mouse pointer.
@MainActor
final class HUDController {
    static let shared = HUDController()

    let model = HUDModel()
    private let panel: HUDPanel
    private var hideWork: DispatchWorkItem?
    private var hoverTimer: Timer?
    private static let baseSize = CGSize(width: 220, height: 44)

    private init() {
        panel = HUDPanel(contentRect: CGRect(origin: .zero, size: Self.baseSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = FirstMouseHostingView(rootView: HUDView(audio: .shared, model: model))
    }

    /// Shows the HUD (optionally with a message instead of the bar) and schedules the fade-out.
    func show(message: String? = nil) {
        guard !Self.isScreenLocked else { return }
        model.message = message
        layout()
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = panel.isVisible ? panel.alphaValue : 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        }
        startHoverTracking()
        scheduleHide()
    }

    private func layout() {
        let scale = CGFloat(min(max(UserDefaults.standard.double(forKey: Prefs.scale), 0.75), 1.75))
        let size = CGSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let margin: CGFloat = 48
        let origin: CGPoint
        switch HUDPosition.current {
        case .bottomCenter: origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + margin)
        case .topCenter: origin = CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - margin / 2)
        case .bottomLeft: origin = CGPoint(x: area.minX + margin / 2, y: area.minY + margin)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let delay = max(UserDefaults.standard.double(forKey: Prefs.fadeDelay), 0.5)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hideIfIdle() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Keeps the HUD up while the pointer is over it or a drag is in progress.
    private func hideIfIdle() {
        if isPointerInside || model.isDragging { scheduleHide(); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                let controller = HUDController.shared
                guard controller.panel.alphaValue == 0 else { return }
                controller.panel.orderOut(nil)
                controller.panel.ignoresMouseEvents = true
                controller.hoverTimer?.invalidate()
                controller.hoverTimer = nil
            }
        }
    }

    /// Only accept mouse events while the pointer is over the HUD, so it never blocks clicks.
    private func startHoverTracking() {
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let controller = HUDController.shared
                controller.panel.ignoresMouseEvents = !(controller.isPointerInside || controller.model.isDragging)
            }
        }
    }

    private var isPointerInside: Bool {
        panel.isVisible && NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
    }

    private static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
