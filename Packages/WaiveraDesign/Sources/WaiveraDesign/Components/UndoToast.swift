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

    /// A floating pill confirming an action in place, with Undo. Preferred over a confirmation
    /// dialog for reversible actions (UX research).
    public struct UndoToast: View {
        private let message: String
        private let onUndo: () -> Void

        public init(message: String, onUndo: @escaping () -> Void) {
            self.message = message
            self.onUndo = onUndo
        }

        public var body: some View {
            HStack(spacing: Spacing.smallPlus) {
                Text(message)
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(DesignStrings.undo, action: onUndo)
                    .font(WaiveraFont.button)
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                    .accessibilityIdentifier("undoToast.undo")
            }
            .padding(.leading, Spacing.medium)
            .padding(.trailing, Spacing.small)
            .padding(.vertical, Spacing.extraSmall)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .accessibilityElement(children: .contain)
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
    #Preview("AX XXXL") { UndoToastGallery().dynamicTypeSize(.accessibility5) }
#endif
