import UIKit
import SwiftUI

final class MarkdownAnswerView: UIView {
    private let stackView = UIStackView()
    private var renderedBlocks: [MarkdownBlock] = []

    convenience init(markdown: String) {
        self.init(blocks: MarkdownBlockParser.parse(markdown))
    }

    init(blocks: [MarkdownBlock]) {
        super.init(frame: .zero)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12

        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        apply(blocks: blocks)
    }

    private func makeView(for block: MarkdownBlock) -> UIView {
        switch block {
        case .text(let text):
            let label = UILabel()
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            label.attributedText = MarkdownTextRenderer.render(text)
            return label

        case .heading(let level, let text):
            let fontSize: CGFloat

            switch level {
            case 1:
                fontSize = 28
            case 2:
                fontSize = 24
            case 3:
                fontSize = 20
            case 4:
                fontSize = 18
            case 5:
                fontSize = 17
            default:
                fontSize = 16
            }

            let label = UILabel()
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            label.accessibilityTraits.insert(.header)
            label.attributedText = MarkdownTextRenderer.render(
                text,
                fontSize: fontSize,
                isBold: true
            )
            return label

        case .code(let language, let content):
            return CodeBlockContainerView(
                language: language, code: content
            )

        case .list(let start, let items):
            return makeListView(
                start: start, items: items
            )

        case .quote(let blocks):
            return makeQuoteView(blocks: blocks)
        }
    }

    private func makeListView(
        start: Int?,
        items: [[MarkdownBlock]]
    ) -> UIStackView {
        let listView = UIStackView()
        listView.axis = .vertical
        listView.spacing = 8

        var firstMarker: UILabel?

        for (index, blocks) in items.enumerated() {
            let marker = UILabel()
            marker.font = .preferredFont(forTextStyle: .body)
            marker.textColor = .label
            marker.textAlignment = .right
            marker.adjustsFontForContentSizeCategory = true

            if let start {
                marker.text = "\(start + index)."
            } else {
                marker.text = "•"
            }

            marker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            marker.setContentCompressionResistancePriority(.required, for: .horizontal)

            marker.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true

            let contentView = MarkdownAnswerView(blocks: blocks)

            let row = UIStackView(arrangedSubviews: [marker, contentView])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 8

            listView.addArrangedSubview(row)

            if let firstMarker {
                marker.widthAnchor.constraint(
                    equalTo: firstMarker.widthAnchor
                ).isActive = true
            } else {
                firstMarker = marker
            }
        }

        return listView
    }

    private func makeQuoteView(
        blocks: [MarkdownBlock]
    ) -> UIView {
        let lineView = UIView()
        lineView.backgroundColor = .separator
        lineView.layer.cornerRadius = 2

        let contentView = MarkdownAnswerView(blocks: blocks)

        let quoteView = UIStackView(arrangedSubviews: [lineView, contentView])
        quoteView.axis = .horizontal
        quoteView.alignment = .fill
        quoteView.spacing = 12

        lineView.widthAnchor.constraint(
            equalToConstant: 4
        ).isActive = true

        return quoteView
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(markdown:) 创建回答视图")
    }

    func update(markdown: String) {
        let newBlocks = MarkdownBlockParser.parse(markdown)
        apply(blocks: newBlocks)
    }

    private func apply(blocks newBlocks: [MarkdownBlock]) {
        guard newBlocks != renderedBlocks else {
            return
        }

        var unchangedCount = 0

        while unchangedCount < renderedBlocks.count,
              unchangedCount < newBlocks.count,
              renderedBlocks[unchangedCount] == newBlocks[unchangedCount] {
            unchangedCount += 1
        }

        let viewsToRemove = Array(stackView.arrangedSubviews.dropFirst(unchangedCount))

        for view in viewsToRemove {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for block in newBlocks.dropFirst(unchangedCount) {
            let view = makeView(for: block)
            stackView.addArrangedSubview(view)
        }

        renderedBlocks = newBlocks
    }
}

#Preview("Markdown 回答") {
    let sample = """
    ## 取消请求

    下面是一段说明：

    > **取消是协作式的。**
    >
    > 调用 `cancel()` 后，仍需要检查取消状态。
    >
    > - 保留已经生成的内容。
    > - 阻止旧任务继续更新界面。

    引用结束，这里恢复普通正文。
    """

    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground

    let answerView = MarkdownAnswerView(markdown: sample)
    answerView.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(answerView)

    controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: "追加内容",
        primaryAction: UIAction { [weak answerView] _ in
            answerView?.update(
                markdown: sample + "\n\n这是新追加的内容，支持 **粗体**。"
            )
        }
    )

    let safeArea = controller.view.safeAreaLayoutGuide

    NSLayoutConstraint.activate([
        answerView.topAnchor.constraint(
            equalTo: safeArea.topAnchor,
            constant: 24
        ),
        answerView.leadingAnchor.constraint(
            equalTo: safeArea.leadingAnchor,
            constant: 16
        ),
        answerView.trailingAnchor.constraint(
            equalTo: safeArea.trailingAnchor,
            constant: -16
        )
    ])

    return UINavigationController(rootViewController: controller)
}
