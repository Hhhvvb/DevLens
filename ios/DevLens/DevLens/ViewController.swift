import UIKit
import SwiftUI

final class ViewController: UIViewController {

    private let questionTextField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let resultTextView = UITextView()
    private let viewModel = QuestionViewModel(
        apiClient: APIClient()
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupViews()
        bindViewModel()
        setupActions()
    }

    private func setupViews() {
        let titleLabel = UILabel()
        titleLabel.text = "DevLens"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true

        questionTextField.placeholder = "例如：UIKit 中 delegate 怎么用？"
        questionTextField.borderStyle = .roundedRect
        questionTextField.font = .preferredFont(forTextStyle: .body)
        questionTextField.adjustsFontForContentSizeCategory = true
        questionTextField.clearButtonMode = .whileEditing

        var configuration = UIButton.Configuration.filled()
        configuration.title = "提交问题"
        configuration.cornerStyle = .medium
        submitButton.configuration = configuration

        resultTextView.font = .preferredFont(forTextStyle: .body)
        resultTextView.adjustsFontForContentSizeCategory = true
        resultTextView.isEditable = false
        resultTextView.backgroundColor = .secondarySystemBackground
        resultTextView.layer.cornerRadius = 12
        resultTextView.textContainerInset = UIEdgeInsets(
            top: 12,
            left: 12,
            bottom: 12,
            right: 12
        )

        let subviews: [UIView] = [
            titleLabel,
            questionTextField,
            submitButton,
            resultTextView
        ]

        for subview in subviews {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 24
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 24
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -24
            ),

            questionTextField.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 24
            ),
            questionTextField.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            questionTextField.trailingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor
            ),
            questionTextField.heightAnchor.constraint(
                equalToConstant: 48
            ),

            submitButton.topAnchor.constraint(
                equalTo: questionTextField.bottomAnchor,
                constant: 16
            ),
            submitButton.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            submitButton.trailingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor
            ),
            submitButton.heightAnchor.constraint(
                equalToConstant: 50
            ),

            resultTextView.topAnchor.constraint(
                equalTo: submitButton.bottomAnchor,
                constant: 20
            ),
            resultTextView.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            resultTextView.trailingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor
            ),
            resultTextView.bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor,
                constant: -16
            )
        ])
    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self ] state in
            self?.render(state)
        }

        render(viewModel.state)
    }

    private func render(_ state: QuestionViewState) {
        submitButton.isEnabled = true
        submitButton.configuration?.title = state.isLoading ? "停止生成" : "提交问题"
        submitButton.configuration?.showsActivityIndicator = state.isLoading

        switch state {
        case .idle:
            resultTextView.text = "提交后，结果会显示在这里。"

        case .loading:
            resultTextView.text = "AI 正在生成回答，请稍候……"

        case .streaming(let answer):
            resultTextView.text = answer

        case .success(let response):
            if response.sources.isEmpty {
                resultTextView.text = response.answer
            } else {
                let sourceText = response.sources.joined(
                    separator: "\n"
                )

                resultTextView.text = "\(response.answer)\n\n" + "—— 本次提供给模型的文件 ——\n" + sourceText
            }

        case .failure(let message):
            resultTextView.text = message

        case .cancelled(let answer):
            if answer.isEmpty {
                resultTextView.text = "已停止生成。"
            } else {
                resultTextView.text = "\(answer)\n\n-- 已停止生成 --"
            }
        }
    }

    private func setupActions() {
        submitButton.addAction(
            UIAction { [weak self] _ in
                self?.submitQuestion()
            },
            for: .touchUpInside
        )
    }

    private func submitQuestion() {
        view.endEditing(true)

        if viewModel.state.isLoading {
            viewModel.cancel()
        } else {
            viewModel.submit(questionTextField.text ?? "")
        }
    }
}

#Preview("提问页面") {
    ViewController()
}
