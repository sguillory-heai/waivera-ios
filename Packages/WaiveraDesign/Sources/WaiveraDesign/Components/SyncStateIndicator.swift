#if canImport(UIKit)
    import SwiftUI

    /// Shows an optimistic item's send state: nothing when synced, "Sending…" while pending, and a
    /// "Not sent. Tap to retry" button on failure. Plays the failure haptic once on the transition.
    public struct SyncStateIndicator: View {
        private let state: SyncState
        private let onRetry: () -> Void

        public init(state: SyncState, onRetry: @escaping () -> Void) {
            self.state = state
            self.onRetry = onRetry
        }

        public var body: some View {
            Group {
                switch state {
                case .synced:
                    EmptyView()
                case .pending:
                    Label(DesignStrings.sending, systemImage: "clock")
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("sync.pending")
                case .failed:
                    Button(action: onRetry) {
                        Label(DesignStrings.tapToRetry, systemImage: "exclamationmark.circle.fill")
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.danger)
                            .frame(minHeight: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityIdentifier("sync.retry")
                }
            }
            .waiveraAnimation(.state, value: state)
            .waiveraHaptic(.failure, trigger: state) { _, new in new == .failed }
        }
    }

    private struct SyncGallery: View {
        var body: some View {
            VStack(alignment: .trailing, spacing: Spacing.small) {
                SyncStateIndicator(state: .pending) {}
                SyncStateIndicator(state: .failed) {}
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { SyncGallery() }
    #Preview("Dark") { SyncGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { SyncGallery().dynamicTypeSize(.accessibility5) }
#endif
