import UIKit

@MainActor
struct MarkdownTextRenderer {
    static func render(
        _ source: String,
        fontSize: CGFloat = 17,
        isBold: Bool = false
    ) -> NSAttributedString {
        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(
                ofSize: fontSize,
                weight: isBold ? .bold : .regular
            )
        )

        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return NSAttributedString(
                string: source,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.label
                ]
            )
        }

        let result = NSMutableAttributedString(string: "")

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent

            let isCode = intent?.contains(.code) == true

            let baseFont: UIFont

            if isCode {
                baseFont = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            } else {
                baseFont = .systemFont(ofSize: fontSize)
            }

            var traits = baseFont.fontDescriptor.symbolicTraits

            if isBold || intent?.contains(.stronglyEmphasized) == true {
                traits.insert(.traitBold)
            }

            if intent?.contains(.emphasized) == true {
                traits.insert(.traitItalic)
            }

            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor

            let styledFont = UIFont(
                descriptor: descriptor, size: fontSize
            )

            let scaledFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: styledFont)

            var attributes: [NSAttributedString.Key: Any] = [
                .font: scaledFont,
                .foregroundColor: UIColor.label
            ]

            if isCode {
                attributes[.backgroundColor] = UIColor.secondarySystemBackground
            }

            result.append(
                NSAttributedString(
                    string: text,
                    attributes: attributes
                )
            )
        }

        return result
    }
}
