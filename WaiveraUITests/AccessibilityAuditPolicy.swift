import XCTest

/// Which accessibility audit findings the screenshot tour accepts, and why. Everything not listed
/// here still fails the tour. Each rule names the check that covers the finding instead, or the
/// design decision that makes it deliberate; widen a rule only with the same kind of reason.
///
/// Deliberate exceptions are marked in the app by accessibility identifier, never matched by
/// label, so the same words elsewhere are still audited:
/// - `fixedTextSize.*`: text that stops growing on purpose (tab titles and badge at 150% as on
///   Android, calendar digits and weekday letters at the grid's cap, avatar initials drawn at the
///   avatar's fixed size, segmented filters that scroll sideways at a fixed height).
/// - `topBar.title`: stops at Android's 200% so one-word titles never break mid-word.
/// - `notTappable.*`: read-only elements VoiceOver reads as one unit (a count badge).
@MainActor
enum AccessibilityAuditPolicy {
    static func accepts(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        switch issue.auditType {
        case .contrast:
            // ColorTokenTests checks every text and fill pair against WCAG 4.5:1 from the exact
            // token values, including button labels under the sheen. The audit samples the
            // anti-aliased edges of the custom font's glyphs and reports failures on pairs
            // above 6:1 (white on the violet button measures 6.8:1 in run 41533860726).
            return true
        case .dynamicType:
            guard let identifier = issue.element?.identifier else { return false }
            return identifier == "topBar.title" || identifier.hasPrefix("fixedTextSize.")
        case .textClipped:
            // A text field's placeholder is measured against the field's inner text frame, not
            // the box it draws in; the screenshots show no placeholder cut off.
            guard let type = issue.element?.elementType else { return false }
            return type == .textField || type == .searchField
        case .hitRegion:
            // Only controls need a 44pt target.
            guard let element = issue.element else { return false }
            return element.elementType == .staticText || element.identifier.hasPrefix("notTappable.")
        default:
            return false
        }
    }
}
