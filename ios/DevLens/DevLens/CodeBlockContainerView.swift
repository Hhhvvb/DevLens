import UIKit

final class CodeBlockContainerView: UIView {
    init(language: String, code: String) {
        super.init(frame: .zero)

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        clipsToBounds = true

        let languageLabel = UILabel()
        languageLabel.text = language.isEmpty ? "代码" : language
        languageLabel.font = .preferredFont(forTextStyle: .subheadline)
        languageLabel.textColor = .secondaryLabel
        languageLabel.adjustsFontForContentSizeCategory = true

        let codeView = CodeBlockView(code: code)

        let copyAction = UIAction(title: "复制代码") { [weak codeView] action in
            guard let codeView,
                  let button = action.sender as? UIButton else {
                return
            }

            let code = codeView.text ?? ""
            guard !code.isEmpty else { return }

            let pasteboard = UIPasteboard.general
            pasteboard.string = code

            let copied = pasteboard.string == code

            button.setTitle(
                copied ? "已复制" : "复制失败",
                for: .normal
            )

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 1.5
            ) { [weak button] in
                button?.setTitle("复制代码", for: .normal)
            }
        }

        let copyButton = UIButton(
            type: .system,
            primaryAction: copyAction
        )

        copyButton.setContentHuggingPriority(
            .required,
            for: .horizontal
        )

        let header = UIStackView(
            arrangedSubviews: [languageLabel, copyButton]
        )

        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(
            top: 4,
            left: 12,
            bottom: 0,
            right: 12
        )

        let stack = UIStackView(
            arrangedSubviews: [header, codeView]
        )

        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            copyButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            ),

            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(language:code:) 创建代码卡片")
    }
}
