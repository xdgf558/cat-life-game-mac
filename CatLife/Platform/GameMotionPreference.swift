import SwiftUI

private struct GameMotionPreferenceKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var gameReduceMotionOverride: Bool {
        get { self[GameMotionPreferenceKey.self] }
        set { self[GameMotionPreferenceKey.self] = newValue }
    }
}
