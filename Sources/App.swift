import AppKit
import SwiftUI

/// App entry point: a menu-bar-only app whose only window is the floating volume HUD.
@main
struct SlideHudVolumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("SlideHudVolume", systemImage: "speaker.wave.2.fill") {
            MenuView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Boots the audio monitor and key interceptor once the app has finished launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        MainActor.assumeIsolated {
            _ = AudioController.shared
            _ = HUDController.shared
            // Prompt only on first run; afterwards the menu offers a button to open the pane.
            let firstRun = !UserDefaults.standard.bool(forKey: "didPromptAccessibility")
            UserDefaults.standard.set(true, forKey: "didPromptAccessibility")
            KeyInterceptor.shared.start(prompt: firstRun)
        }
    }
}
