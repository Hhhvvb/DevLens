import UIKit
import SwiftUI
import Markdown

final class CodeBlockView: UITextView {
    init(code: String) {
        super.init(frame: .zero, textContainer: nil)

        text = code

        isEditable = false
        isSelectable = true
        isScrollEnabled = false

        backgroundColor = .secondarySystemBackground
        textColor = .label

        let baseFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)

        adjustsFontForContentSizeCategory = true

        textContainerInset = UIEdgeInsets(
            top: 12,
            left: 12,
            bottom: 12,
            right: 12
        )

        textContainer.lineFragmentPadding = 0
        layer.cornerRadius = 10
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(code:) 创建代码块")
    }
}

#Preview("代码块") {
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground

    let codeView = CodeBlockContainerView(
        language: "swift",
        code: """
        func cancel() {
            requestTask?.cancel()
            requestTask = nil
        }
        """
    )

    codeView.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(codeView)

    let safeArea = controller.view.safeAreaLayoutGuide

    NSLayoutConstraint.activate([
        codeView.topAnchor.constraint(
            equalTo: safeArea.topAnchor,
            constant: 24
        ),
        codeView.leadingAnchor.constraint(
            equalTo: safeArea.leadingAnchor,
            constant: 16
        ),
        codeView.trailingAnchor.constraint(
            equalTo: safeArea.trailingAnchor,
            constant: -16
        )
    ])

    return controller
}
