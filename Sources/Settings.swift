import Foundation

/// Central list of persisted preference keys and their default values.
enum Prefs {
    static let takeover = "takeoverEnabled"
    static let position = "hudPosition"
    static let step = "stepSize"
    static let scale = "hudScale"
    static let fadeDelay = "fadeDelay"

    /// Registers defaults so `UserDefaults` reads match the `@AppStorage` initial values.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            takeover: true,
            position: HUDPosition.bottomCenter.rawValue,
            step: StepSize.normal.rawValue,
            scale: 1.0,
            fadeDelay: 2.0,
        ])
    }
}

/// Where the HUD appears on the active display.
enum HUDPosition: String, CaseIterable, Identifiable {
    case bottomCenter, topCenter, bottomLeft
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .topCenter: return "Top Center"
        case .bottomLeft: return "Bottom Left"
        }
    }

    static var current: HUDPosition {
        HUDPosition(rawValue: UserDefaults.standard.string(forKey: Prefs.position) ?? "") ?? .bottomCenter
    }
}

/// How far a single volume key press moves the level.
enum StepSize: String, CaseIterable, Identifiable {
    case coarse, normal, fine, extraFine
    var id: String { rawValue }

    var title: String {
        switch self {
        case .coarse: return "Coarse (1/8)"
        case .normal: return "Normal (1/16)"
        case .fine: return "Fine (1/64)"
        case .extraFine: return "Extra Fine (1%)"
        }
    }

    var amount: Float {
        switch self {
        case .coarse: return 1.0 / 8.0
        case .normal: return 1.0 / 16.0
        case .fine: return 1.0 / 64.0
        case .extraFine: return 1.0 / 100.0
        }
    }

    static var current: StepSize {
        StepSize(rawValue: UserDefaults.standard.string(forKey: Prefs.step) ?? "") ?? .normal
    }
}
