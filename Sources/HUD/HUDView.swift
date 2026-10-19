import SwiftUI

/// The slim HUD content: speaker glyph, device name over a draggable level bar, and percentage.
struct HUDView: View {
    @ObservedObject var audio: AudioController
    @ObservedObject var model: HUDModel
    @AppStorage(Prefs.scale) private var scale = 1.0

    var body: some View {
        let s = CGFloat(scale)
        HStack(spacing: 10 * s) {
            Image(systemName: glyph)
                .font(.system(size: 15 * s, weight: .semibold))
                .frame(width: 22 * s)
            if let message = model.message {
                Text(message)
                    .font(.system(size: 12 * s, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(audio.deviceName)
                        .font(.system(size: 9 * s, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    LevelBar(level: audio.isMuted ? 0 : audio.volume, height: 6 * s) { value in
                        audio.setVolume(value)
                    } onDragChanged: { model.isDragging = $0 }
                }
                Text(audio.isMuted ? "Muted" : "\(Int((audio.volume * 100).rounded()))%")
                    .font(.system(size: 12 * s, weight: .semibold).monospacedDigit())
                    .frame(width: 44 * s, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var glyph: String {
        if model.message != nil { return "speaker.badge.exclamationmark.fill" }
        if audio.isMuted || audio.volume <= 0.001 { return "speaker.slash.fill" }
        switch audio.volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// A capsule progress bar that sets an exact level when clicked or dragged.
struct LevelBar: View {
    var level: Float
    var height: CGFloat
    var onChange: (Float) -> Void
    var onDragChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.18))
                Capsule().fill(.primary)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDragChanged(true)
                        guard geo.size.width > 0 else { return }
                        onChange(Float(value.location.x / geo.size.width))
                        HUDController.shared.show()
                    }
                    .onEnded { _ in onDragChanged(false) }
            )
        }
        .frame(height: max(height * 2.5, 14))
    }
}
