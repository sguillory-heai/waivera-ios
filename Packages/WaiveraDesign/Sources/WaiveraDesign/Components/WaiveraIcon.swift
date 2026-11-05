#if canImport(UIKit)
    import SwiftUI

    /// Android's icon set. `Resources/Icons.xcassets` holds waivera-android's vector drawables as
    /// template SVGs (24pt boxes, 2pt round strokes), so both apps draw the same icons. Screens
    /// still name an icon by the SF Symbol for its meaning; this table picks Android's drawing for
    /// it, and the few meanings Android has no icon for keep the symbol.
    public enum WaiveraIcons {
        /// Filled and outline forms share Android's one (outline) drawing.
        public static func asset(for systemName: String) -> String? {
            // An Android drawing with no SF Symbol counterpart is named directly.
            if systemName.hasPrefix("wv-") { return systemName }
            let outline = systemName.hasSuffix(".fill") ? String(systemName.dropLast(".fill".count)) : systemName
            let name = table[systemName] ?? table[outline] ?? table[outline + ".fill"]
            return name.map { "wv-\($0)" }
        }

        private static let table: [String: String] = [
            "alarm.fill": "schedule",
            "bell.badge": "notifications",
            "person.3": "people",
            "archivebox": "archive",
            "archivebox.fill": "archive",
            "arrow.clockwise": "refresh",
            "arrow.triangle.2.circlepath": "refresh",
            "arrow.down.to.line": "feature_chat-download",
            "arrow.left": "back",
            "chevron.backward": "back",
            "arrow.up": "arrow_upward",
            "arrow.up.forward.square": "open_external",
            "arrow.up.right.square": "open_external",
            "arrow.up.left.and.arrow.down.right": "feature_chat-maximize",
            "arrowshape.turn.up.left": "reply",
            "arrowshape.turn.up.left.fill": "reply",
            "arrowshape.turn.up.left.2": "reply",
            "at": "feature_today-mention",
            "beach.umbrella": "feature_calendar-time_off",
            "sun.max": "feature_calendar-time_off",
            "sun.max.fill": "feature_calendar-time_off",
            "bell": "notifications",
            "bell.fill": "notifications",
            "bell.badge.fill": "notifications",
            "birthday.cake": "cake",
            "birthday.cake.fill": "cake",
            "bookmark": "bookmark",
            "bookmark.fill": "feature_chat-bookmark_filled",
            "bookmark.slash": "feature_profile-bookmark_remove",
            "bubble.left": "chat",
            "bubble.left.fill": "chat",
            "bubble.left.and.bubble.right": "chat",
            "bubble.left.and.bubble.right.fill": "chat",
            "text.bubble": "chat",
            "building.2": "building",
            "building.2.fill": "building",
            "calendar": "calendar",
            "calendar.badge.checkmark": "calendar",
            "calendar.badge.clock": "calendar",
            "calendar.badge.minus": "calendar",
            "checklist": "feature_tasks-task",
            "list.bullet.clipboard": "feature_tasks-task",
            "list.clipboard": "feature_tasks-task",
            "checkmark": "check",
            "checkmark.message": "mark_read",
            "chevron.down": "expand_more",
            "chevron.up": "expand_less",
            "chevron.left": "feature_calendar-chevron_left",
            "chevron.right": "chevron_right",
            "clock": "schedule",
            "clock.fill": "schedule",
            "clock.arrow.circlepath": "schedule",
            "clock.badge.exclamationmark": "schedule",
            "hourglass": "schedule",
            "doc": "feature_chat-file",
            "doc.text": "feature_chat-file_text",
            "doc.text.fill": "feature_chat-file_text",
            "doc.on.doc": "feature_chat-copy",
            "tablecells": "feature_chat-file_sheet",
            "ellipsis": "more",
            "envelope": "mail",
            "envelope.open": "mark_read",
            "envelope.open.fill": "mark_read",
            "exclamationmark.circle": "error",
            "exclamationmark.circle.fill": "error",
            "exclamationmark.triangle": "warning",
            "exclamationmark.triangle.fill": "warning",
            "eye": "feature_auth-visibility",
            "eye.slash": "feature_auth-visibility_off",
            "face.smiling": "feature_today-reaction",
            "gearshape": "settings",
            "gearshape.fill": "settings",
            "globe": "globe",
            "safari": "globe",
            "house": "today",
            "house.fill": "today",
            "icloud.slash": "cloud_off",
            "wifi.slash": "cloud_off",
            "info.circle": "info",
            "iphone.radiowaves.left.and.right": "feature_settings-haptics",
            "lock": "lock",
            "lock.fill": "lock",
            "magnifyingglass": "search",
            "mappin.and.ellipse": "location",
            "mappin": "location",
            "megaphone": "announcement",
            "megaphone.fill": "announcement",
            "minus": "feature_tasks-minus",
            "number": "hash",
            "paintpalette": "feature_settings-palette",
            "paintpalette.fill": "feature_settings-palette",
            "paperclip": "attachment",
            "paperplane": "feature_chat-send",
            "paperplane.fill": "feature_chat-send",
            "party.popper": "celebration",
            "party.popper.fill": "celebration",
            "pencil": "feature_chat-edit",
            "person": "person",
            "person.fill": "person",
            "person.crop.circle": "person",
            "person.crop.square": "person",
            "person.2": "people",
            "person.2.fill": "people",
            "person.3.fill": "people",
            "person.text.rectangle": "badge",
            "phone": "phone",
            "phone.fill": "phone",
            "phone.down.fill": "feature_chat-phone_missed",
            "photo": "feature_chat-image",
            "photo.badge.plus": "feature_chat-image_add",
            "plus": "add",
            "plus.circle": "add",
            "rectangle.portrait.and.arrow.right": "feature_settings-logout",
            "rosette": "award",
            "signature": "feature_today-signature",
            "ticket": "feature_today-ticket",
            "trash": "feature_chat-delete",
            "video": "video",
            "video.fill": "video",
            "waveform.path.ecg": "feature_tasks-activity",
            "xmark": "close",
            "xmark.circle": "close",
            "xmark.circle.fill": "close",
            "figure.walk.motion": "feature_settings-motion",
            "sparkles": "celebration",
            "seal": "award",
            "checkmark.seal": "award",
            "rectangle.and.pencil.and.ellipsis": "feature_chat-edit",
            "camera": "camera",
            "camera.fill": "camera",
            "photo.on.rectangle": "image",
            "folder": "folder",
            "folder.fill": "folder",
            "square.and.arrow.up": "share",
            "square.and.arrow.down": "download",
            "arrow.up.doc": "upload",
            "arrow.down": "arrow_downward",
            "chevron.up.chevron.down": "expand_more",
            "checkmark.circle": "mark_read",
        ]
    }

    public extension Image {
        /// Android's drawing for an icon's meaning (`WaiveraIcons`), named by its SF Symbol, as a
        /// template image; the symbol itself when Android has none. Use it where the image is
        /// resized to a frame; use `WaiveraIcon` where the icon should follow the font.
        init(waivera systemName: String) {
            if let asset = WaiveraIcons.asset(for: systemName) {
                self = Image(decorative: asset, bundle: .module).renderingMode(.template)
            } else {
                self.init(systemName: systemName)
            }
        }
    }

    /// An icon sized by the current font, like an SF Symbol: Android's drawing (`WaiveraIcons`) in
    /// a square as tall as a line of the current font, so it follows Dynamic Type. `pointSize`
    /// gives it the size a symbol drawn at that font size would have instead.
    public struct WaiveraIcon: View {
        private let systemName: String
        private let pointSize: CGFloat?

        @Environment(\.imageScale) private var imageScale

        public init(systemName: String, pointSize: CGFloat? = nil) {
            self.systemName = systemName
            self.pointSize = pointSize
        }

        public var body: some View {
            if let asset = WaiveraIcons.asset(for: systemName) {
                let image = Image(decorative: asset, bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                if let pointSize {
                    let side = pointSize * Self.boxRatio * scale
                    image.frame(width: side, height: side)
                } else {
                    LineSquare(scale: scale) {
                        Text(verbatim: "X").hidden().accessibilityHidden(true)
                        image
                    }
                }
            } else if let pointSize {
                Image(systemName: systemName).font(.system(size: pointSize))
            } else {
                Image(systemName: systemName)
            }
        }

        /// `.imageScale(.small)` and `.large` shrink and grow the icon, as they do a symbol.
        private var scale: CGFloat {
            switch imageScale {
            case .small: 0.8
            case .large: 1.2
            default: 1
            }
        }

        /// Android's 24pt box draws its strokes inside a 20pt area, so a box 1.2 times a symbol's
        /// point size draws the icon as large as that symbol.
        private static let boxRatio: CGFloat = 1.2
    }

    /// A square as tall as its first subview (a hidden line of text in the current font), with the
    /// second subview filling it.
    /// Never wider or taller than the frame it is given, so a caller's fixed frame still holds.
    private struct LineSquare: Layout {
        let scale: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let line = (subviews.first?.sizeThatFits(.unspecified).height ?? 0) * scale
            // A zero proposal is a layout probe, not a frame; answer it with the full size.
            let width = proposal.width.flatMap { $0 > 0 ? $0 : nil } ?? line
            let height = proposal.height.flatMap { $0 > 0 ? $0 : nil } ?? line
            let side = min(line, width, height)
            return CGSize(width: side, height: side)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard subviews.count == 2 else { return }
            subviews[0].place(at: bounds.origin, proposal: .unspecified)
            subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
#endif
