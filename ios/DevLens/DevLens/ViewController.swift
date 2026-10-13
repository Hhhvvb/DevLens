import UIKit
import SwiftUI

final class ViewController: UIViewController {

    private let questionTextField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let resultTextView = UITextView()
    private let apiClient = APIClient()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupViews()
        setupActions()
    }

    private func setupViews() {
        let titleLabel = UILabel()
        titleLabel.text = "DevLens"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true

        questionTextField.placeholder = "例如：网络请求在哪里实现?"
        questionTextField.borderStyle = .roundedRect
        questionTextField.font = .preferredFont(forTextStyle: .body)
        questionTextField.adjustsFontForContentSizeCategory = true
        questionTextField.clearButtonMode = .whileEditing

        var configuration = UIButton.Configuration.filled()
        configuration.title = "提交问题"
        configuration.cornerStyle = .medium
        submitButton.configuration = configuration

        resultTextView.text = "提交后，结果会显示在这里"
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

    private func setupActions() {
        submitButton.addAction(
            UIAction { [weak self] _ in
                self?.submitQuestion()
            },
            for: .touchUpInside
        )
    }

    private func submitQuestion() {
        guard submitButton.isEnabled else {
            return
        }
        
        view.endEditing(true)
        
        let question = (questionTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !question.isEmpty else {
            resultTextView.text = "请输入问题，不能只输入空格。"
            return
        }
        
        submitButton.isEnabled = false
        submitButton.configuration?.showsActivityIndicator = true
        resultTextView.text = "正在提交问题……"
        
        Task { [weak self ] in
            guard let self else {
                return
            }
            
            defer {
                self.submitButton.isEnabled = true
                self.submitButton.configuration?.showsActivityIndicator = false
            }
            
            do {
                let response = try await self.apiClient.sendQuestion(question)
                
                self.resultTextView.text = "\(response.message)\n\n问题长度：\(response.questionLength)"
            } catch {
                self.resultTextView.text = "请求失败：\(error.localizedDescription)"
            }
        }
    }
}

#Preview("提问页面") {
    ViewController()
}
