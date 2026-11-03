import UIKit
import SwiftUI

final class SourceDetailViewController: UIViewController {
    private let source: SourceChunk
    private let pathLabel = UILabel()
    private let codeTextView = UITextView()

    init(source: SourceChunk) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(source:) 创建源码详情")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "源码片段"
        view.backgroundColor = .systemBackground

        setupViews()
        setupLayout()
        displaySource()
    }

    private func setupViews() {
        pathLabel.numberOfLines = 0
        pathLabel.font = .preferredFont(forTextStyle: .subheadline)
        pathLabel.textColor = .secondaryLabel
        pathLabel.adjustsFontForContentSizeCategory = true

        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.backgroundColor = .secondarySystemBackground
        codeTextView.textColor = .label

        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        codeTextView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: font)

        codeTextView.adjustsFontForContentSizeCategory = true
        codeTextView.textContainerInset = UIEdgeInsets(
            top: 12,
            left: 8,
            bottom: 12,
            right: 8
        )
    }

    private func setupLayout() {
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        codeTextView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(pathLabel)
        view.addSubview(codeTextView)

        let safeArea = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            pathLabel.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: 12
            ),
            pathLabel.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 16
            ),
            pathLabel.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -16
            ),

            codeTextView.topAnchor.constraint(
                equalTo: pathLabel.bottomAnchor,
                constant: 12
            ),
            codeTextView.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 16
            ),
            codeTextView.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -16
            ),
            codeTextView.bottomAnchor.constraint(
                equalTo: safeArea.bottomAnchor,
                constant: -12
            )
        ])
    }

    private func displaySource() {
        pathLabel.text = "\(source.path)\n第 \(source.startLine)–\(source.endLine) 行"

        let lines = source.content.components(separatedBy: "\n")
        var numberedLines: [String] = []

        for (offset, line) in lines.enumerated() {
            let lineNumber = source.startLine + offset
            numberedLines.append("\(lineNumber) \(line)")
        }

        codeTextView.text = numberedLines.joined(separator: "\n")
    }
}

#Preview("源码详情") {
    UINavigationController(
        rootViewController: SourceDetailViewController(
            source: SourceChunk(
                path: "示例目录/Example.swift",
                startLine: 10,
                endLine: 14,
                content: """
                    func greet() {
                        let message = "Hello"

                        print(message)
                    }
                """
            )
        )
    )
}
