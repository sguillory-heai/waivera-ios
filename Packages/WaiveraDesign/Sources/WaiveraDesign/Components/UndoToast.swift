#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// What an undo toast shows. A new `id` restarts the timer.
    public struct UndoToastItem: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let message: String

        public init(id: UUID = UUID(), message: String) {
            self.id = id
            self.message = message
        }
    }

    /// The snackbar (Android `WaiveraSnackbar`): an inverse pill confirming something in place,
    /// with an optional text action.
    public struct SnackbarView: View {
        private let message: String
        private let actionTitle: String?
        private let actionIdentifier: String
        private let action: (() -> Void)?

        public init(
            message: String,
            actionTitle: String? = nil,
            actionIdentifier: String = "snackbar.action",
            action: (() -> Void)? = nil
        ) {
            self.message = message
            self.actionTitle = actionTitle
            self.actionIdentifier = actionIdentifier
            self.action = action
        }

        public var body: some View {
            HStack(spacing: Spacing.mediumSmall) {
                Text(message)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.onSnackbar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.mediumSmall)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .waiveraTextStyle(.labelLarge)
                            .foregroundStyle(Palette.snackbarAction)
                            .padding(.horizontal, Spacing.small)
                            .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityIdentifier(actionIdentifier)
                }
            }
            .padding(.leading, Spacing.medium)
            .padding(.trailing, actionTitle == nil ? Spacing.medium : Spacing.small)
            .padding(.vertical, Spacing.extraSmall)
            .background(Palette.snackbar, in: RoundedRectangle(cornerRadius: Radius.snackbar, style: .continuous))
            .shadow(
                color: Palette.buttonRaise,
                radius: Elevation.shadow(for: Elevation.overlay).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.overlay).y
            )
            .accessibilityElement(children: .contain)
        }
    }

    /// The snackbar with Undo, preferred over a confirmation for reversible actions.
    public struct UndoToast: View {
        private let message: String
        private let onUndo: () -> Void

        public init(message: String, onUndo: @escaping () -> Void) {
            self.message = message
            self.onUndo = onUndo
        }

        public var body: some View {
            SnackbarView(
                message: message,
                actionTitle: DesignStrings.undo,
                actionIdentifier: "undoToast.undo",
                action: onUndo
            )
        }
    }

    public extension View {
        /// Shows an undo toast at the bottom while `item` is non-nil and clears it after the timeout.
        func undoToast(item: Binding<UndoToastItem?>, onUndo: @escaping (UndoToastItem) -> Void) -> some View {
            modifier(UndoToastModifier(item: item, onUndo: onUndo))
        }
    }

    private struct UndoToastModifier: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Binding var item: UndoToastItem?
        let onUndo: (UndoToastItem) -> Void

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .bottom) {
                    if let current = item {
                        UndoToast(message: current.message) {
                            onUndo(current)
                            item = nil
                        }
                        .padding(Spacing.medium)
                        .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                        .task(id: current.id) {
                            UIAccessibility.post(notification: .announcement, argument: current.message)
                            let lifetime =
                                UIAccessibility.isVoiceOverRunning
                                ? FeedbackTiming.undoToastAccessible
                                : FeedbackTiming.undoToast
                            try? await Task.sleep(for: .seconds(lifetime))
                            if !Task.isCancelled, item?.id == current.id {
                                item = nil
                            }
                        }
                    }
                }
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: item)
        }
    }

    private struct UndoToastGallery: View {
        var body: some View {
            VStack {
                Spacer()
                UndoToast(message: "Marked all activity as read") {}
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { UndoToastGallery() }
    #Preview("Dark") { UndoToastGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { UndoToastGallery().dynamicTypeSize(.accessibility5) }
#endif
