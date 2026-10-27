import SwiftUI

/// The only haptics the app plays, at moments that matter: send, receive while
/// visible, errors and toggles. Use with `.sensoryFeedback(Haptics.sent, trigger:)`.
public enum Haptics {
    public static let sent = SensoryFeedback.impact(weight: .light)
    public static let received = SensoryFeedback.impact(weight: .light, intensity: 0.5)
    public static let failed = SensoryFeedback.error
    public static let toggled = SensoryFeedback.selection
    public static let succeeded = SensoryFeedback.success
}
