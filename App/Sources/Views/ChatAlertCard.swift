import SwiftUI
import UIKit
import WaiveraData
import WaiveraDesign

/// A message that arrives while the app is open (option A, the lifted card): the sender's photo
/// or tile, who it's from, and two lines of the message on a raised card that floats over the
/// screen. Tap opens the chat; a flick up dismisses it. It never plays a sound or vibrates.
struct ChatAlertCard: View {
    let alert: ChatAlert
    let loadAvatar: @MainActor (String) async -> Data?
    let onOpen: () -> Void
    let onDismiss: () -> Void
    /// The finger is on the card; the owner holds its timer.
    let onHoldChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: Image?
    @State private var drag: CGFloat = 0
    @State private var holding = false

    /// Upward travel that dismisses, and the downward give before the card resists.
    private static let dismissTravel: CGFloat = 40
    private static let pullGive: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.mediumSmall) {
            AvatarView(name: AppStrings.chatAlertAvatarName(alert), image: photo, size: ControlSize.iconTile)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(AppStrings.chatAlertTitle(alert))
                        .waiveraTextStyle(.titleSmall, weight: .bold)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(AppStrings.chatAlertNow)
                        .waiveraTextStyle(.labelSmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                message(AppStrings.chatAlertBody(alert))
            }
        }
        .padding(Spacing.mediumSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: shape)
        .overlay {
            if colorScheme == .dark {
                shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            }
        }
        .floatingShadow()
        .offset(y: drag)
        .contentShape(shape)
        // One gesture for both: a touch that barely moves opens, a flick up dismisses.
        .gesture(dismissDrag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppStrings.chatAlert(alert)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(AppStrings.alertDismiss), onDismiss)
        .task(id: alert.sender?.userId) {
            photo = nil
            guard let userId = alert.sender?.userId, let data = await loadAvatar(userId),
                let decoded = UIImage(data: data)
            else { return }
            photo = Image(uiImage: decoded)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
    }

    private func message(_ text: AttributedString) -> some View {
        Text(text)
            .waiveraTextStyle(.bodySmall)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !holding {
                    holding = true
                    onHoldChanged(true)
                }
                let travel = value.translation.height
                drag = travel < 0 ? travel : min(Self.pullGive, travel / 3)
            }
            .onEnded { value in
                holding = false
                onHoldChanged(false)
                if value.translation.height < -Self.dismissTravel
                    || value.predictedEndTranslation.height < -Self.dismissTravel * 2
                {
                    onDismiss()
                } else if abs(value.translation.height) < Spacing.small {
                    drag = 0
                    onOpen()
                } else {
                    withAnimation(Motion.animation(.state, reduceMotion: reduceMotion)) { drag = 0 }
                }
            }
    }
}
