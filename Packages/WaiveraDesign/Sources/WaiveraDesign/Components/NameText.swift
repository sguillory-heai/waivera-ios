#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// A chat name on one line (v7 item 3): it may shrink up to 15% before it ends in "…", never
    /// wrapping or breaking inside a word. Use it for conversation, member and sender names.
    public struct OneLineName: View {
        private let name: String
        private let style: TextStyleToken

        public init(_ name: String, style: TextStyleToken = .titleSmall) {
            self.name = name
            self.style = style
        }

        public var body: some View {
            Text(name)
                .waiveraTextStyle(style)
                .lineLimit(1)
                .minimumScaleFactor(NameFit.minimumScale)
                .truncationMode(.tail)
        }
    }

    /// A person's name where it is a headline (wave 29): up to `lines` lines, wrapping between
    /// words, then "…". Pick `lines` from `NameLines` for the place it is shown.
    public struct NameText: View {
        private let name: String
        private let style: TextStyleToken
        private let lines: Int

        public init(_ name: String, style: TextStyleToken, lines: Int) {
            self.name = name
            self.style = style
            self.lines = lines
        }

        public var body: some View {
            Text(name)
                .waiveraTextStyle(style)
                .lineLimit(max(1, lines))
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A one-line title composed around a name, such as "Maria-Fernanda R. & 4 others" (v7 item 4):
    /// full size when it fits, then a step smaller down to 85%, then only the name ends in "…" so
    /// "& 4 others" always shows, then "Name… +4". It takes the full width it is offered.
    public struct ShortenedNameText: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let title: String
        private let name: String
        private let compactSuffix: String?
        private let style: TextStyleToken

        /// - Parameters:
        ///   - title: the whole title.
        ///   - name: the part of `title` that may be cut; when it is not in `title`, the title is
        ///     only shrunk and then tail-truncated.
        ///   - compactSuffix: the short count ("+4") for when even "…" and the count do not fit.
        public init(_ title: String, name: String, compactSuffix: String? = nil, style: TextStyleToken = .titleSmall) {
            self.title = title
            self.name = name
            self.compactSuffix = compactSuffix
            self.style = style
        }

        /// A group conversation's title: the first member's short label and how many others.
        public init(groupTitle: String, firstName: String, others: Int, style: TextStyleToken = .titleSmall) {
            self.init(
                groupTitle,
                name: firstName,
                compactSuffix: others > 0 ? GroupTitle.compactSuffix(others: others) : nil,
                style: style
            )
        }

        public var body: some View {
            Text(verbatim: "Hg")
                .waiveraTextStyle(style)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        let fitted = fit(width: proxy.size.width)
                        Text(fitted.shown)
                            .font(.custom(style.spec.weight.postScriptName, fixedSize: fitted.size))
                            .tracking(style.spec.trackingEm * fitted.size)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(title))
        }

        private func fit(width: CGFloat) -> ShortenedName {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            let fullSize = Double(style.uiFont(compatibleWith: traits).pointSize)
            let range = GroupTitle.nameRange(in: title, name: name) ?? 0..<0
            let postScriptName = style.spec.weight.postScriptName
            let trackingEm = style.spec.trackingEm
            return ShortenedNameFitter.fit(
                text: title,
                shortenable: range,
                fullSize: fullSize,
                compactSuffix: compactSuffix
            ) { candidate, size in
                let font = UIFont(name: postScriptName, size: size) ?? UIFont.systemFont(ofSize: size)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: trackingEm * size]
                return Double((candidate as NSString).size(withAttributes: attributes).width) <= Double(width)
            }
        }
    }

    private struct NameGallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                OneLineName("Maria-Fernanda Rodriguez-Villanueva")
                ShortenedNameText(
                    groupTitle: "Maria-Fernanda Rodriguez & 4 others",
                    firstName: "Maria-Fernanda Rodriguez",
                    others: 4
                )
                .frame(width: 200)
                ShortenedNameText(groupTitle: "Priya & 2 others", firstName: "Priya", others: 2)
                NameText(
                    "Bartholomew Alexander Montgomery-Fairweather",
                    style: .headlineSmall,
                    lines: NameLines.hero(.large)
                )
            }
            .foregroundStyle(Palette.text)
            .padding(Spacing.medium)
            .background(Palette.surface)
        }
    }

    #Preview("Light") { NameGallery() }
    #Preview("Dark") { NameGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { NameGallery().dynamicTypeSize(.accessibility5) }
#endif
