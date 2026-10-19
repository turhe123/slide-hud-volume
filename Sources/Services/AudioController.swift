import AudioToolbox
import CoreAudio
import Foundation

/// Reads and writes the default output device's volume and mute state through Core Audio,
/// and keeps published state in sync with changes made by other apps or device switches.
@MainActor
final class AudioController: ObservableObject {
    static let shared = AudioController()

    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var deviceName = "Unknown Device"
    @Published private(set) var hasVolumeControl = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            MainActor.assumeIsolated { AudioController.shared.reloadDevice() }
        }
        reloadDevice()
    }

    // MARK: Public API

    /// Sets the absolute level (0...1); unmutes when raising the level above zero.
    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        guard hasVolumeControl else { return }
        if isMuted && clamped > 0 { setMuted(false) }
        if !write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: kAudioObjectPropertyElementMain, value: clamped) {
            var wrote = write(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain, value: clamped)
            for channel: UInt32 in [1, 2] where write(kAudioDevicePropertyVolumeScalar, element: channel, value: clamped) {
                wrote = true
            }
            if !wrote { hasVolumeControl = false }
        }
        refresh()
    }

    /// Moves the level by `delta`, snapping to the step grid like the stock behaviour.
    func adjust(by delta: Float) {
        let steps = (volume / abs(delta)).rounded()
        setVolume((steps + (delta > 0 ? 1 : -1)) * abs(delta))
    }

    func toggleMute() { setMuted(!isMuted) }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var address = Self.address(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
        refresh()
    }

    /// Re-reads volume, mute and capability from the current device.
    func refresh() {
        if let v = read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: kAudioObjectPropertyElementMain)
            ?? read(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            volume = v
            hasVolumeControl = true
        } else {
            let channels = [UInt32(1), 2].compactMap { read(kAudioDevicePropertyVolumeScalar, element: $0) }
            hasVolumeControl = !channels.isEmpty
            volume = channels.isEmpty ? 0 : channels.reduce(0, +) / Float(channels.count)
        }
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.address(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(deviceID, &address),
           AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute) == noErr {
            isMuted = mute != 0
        } else {
            isMuted = false
        }
    }

    // MARK: Device tracking

    /// Called on launch and whenever the default output changes (e.g. Bluetooth headphones connect).
    private func reloadDevice() {
        removeDeviceListeners()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        deviceID = id
        deviceName = readName() ?? "Unknown Device"
        addDeviceListeners()
        refresh()
    }

    private func addDeviceListeners() {
        guard deviceID != kAudioObjectUnknown else { return }
        let watched: [(AudioObjectPropertySelector, UInt32)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in watched {
            var address = Self.address(selector, element: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { AudioController.shared.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for (addr, block) in deviceListeners {
            var address = addr
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        }
        deviceListeners.removeAll()
    }

    // MARK: Low-level helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func read(_ selector: AudioObjectPropertySelector, element: UInt32) -> Float? {
        var address = Self.address(selector, element: element)
        guard deviceID != kAudioObjectUnknown, AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func write(_ selector: AudioObjectPropertySelector, element: UInt32, value: Float) -> Bool {
        var address = Self.address(selector, element: element)
        guard deviceID != kAudioObjectUnknown, AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(value)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    private func readName() -> String? {
        var address = Self.address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
              let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }
}
