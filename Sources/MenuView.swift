import ServiceManagement
import SwiftUI

/// The MenuBarExtra panel: permission guidance, takeover options, HUD appearance and support.
struct MenuView: View {
    @ObservedObject var keys = KeyInterceptor.shared
    @ObservedObject var audio = AudioController.shared
    @AppStorage(Prefs.takeover) private var takeover = true
    @AppStorage(Prefs.position) private var position = HUDPosition.bottomCenter.rawValue
    @AppStorage(Prefs.step) private var step = StepSize.normal.rawValue
    @AppStorage(Prefs.scale) private var scale = 1.0
    @AppStorage(Prefs.fadeDelay) private var fadeDelay = 2.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SlideHudVolume").font(.headline)

            if !keys.isTrusted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Accessibility access needed", systemImage: "hand.raised.fill").font(.subheadline.bold())
                    Text("To capture the volume keys and hide the stock pop-up, allow SlideHudVolume in System Settings › Privacy & Security › Accessibility. Until then you can still use the HUD's drag bar.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings") { keys.openAccessibilitySettings() }
                }
                .padding(8)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Toggle("Enable Takeover", isOn: $takeover).disabled(!keys.isTrusted)

            HStack {
                Image(systemName: "speaker.wave.2.fill")
                Slider(value: Binding(get: { Double(audio.volume) },
                                      set: { audio.setVolume(Float($0)); HUDController.shared.show() }))
                    .disabled(!audio.hasVolumeControl)
            }
            Text(audio.hasVolumeControl ? audio.deviceName : "\(audio.deviceName): no volume control")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Picker("Position", selection: $position) {
                ForEach(HUDPosition.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Step Size", selection: $step) {
                ForEach(StepSize.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Text("Hold ⌥ Option while pressing the keys for the finest step.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Size") {
                Slider(value: $scale, in: 0.75...1.75) { editing in if !editing { HUDController.shared.show() } }
            }
            LabeledContent("Fade after \(fadeDelay, specifier: "%.1f")s") {
                Slider(value: $fadeDelay, in: 0.5...6, step: 0.5)
            }
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
                Spacer()
                Button("Preview HUD") { HUDController.shared.show() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            audio.refresh()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
