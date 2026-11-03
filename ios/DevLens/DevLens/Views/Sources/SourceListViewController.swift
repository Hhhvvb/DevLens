import UIKit
import SwiftUI

final class SourceListViewController: UICollectionViewController {
    private let sources: [SourceChunk]

    private let sourceRegistration = UICollectionView.CellRegistration<
        UICollectionViewListCell,
        SourceChunk
    > { cell, _, source in
        var content = cell.defaultContentConfiguration()

        content.text = source.path
        content.secondaryText = "第 \(source.startLine)–\(source.endLine) 行"

        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = content
        cell.accessories = []
    }

    init(sources: [SourceChunk]) {
        self.sources = sources

        let configuration = UICollectionLayoutListConfiguration(
            appearance: .insetGrouped
        )
        let layout = UICollectionViewCompositionalLayout.list(
            using: configuration
        )

        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(sources:) 创建来源列表")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "本次参考源码"
        collectionView.allowsSelection = true
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        sources.count
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: sourceRegistration,
            for: indexPath,
            item: sources[indexPath.item]
        )
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        collectionView.deselectItem(
            at: indexPath,
            animated: false
        )

        let source = sources[indexPath.item]
        let detailController = SourceDetailViewController(source: source)

        navigationController?.pushViewController(detailController, animated: true)
    }
}

#Preview("来源列表") {
    UINavigationController(
        rootViewController: SourceListViewController(
            sources: [
                SourceChunk(
                    path: "示例目录/Example.swift",
                    startLine: 10,
                    endLine: 12,
                    content: """
                    func greet() {
                        print("Heelo")
                    }
                    """
                )
            ]
        )
    )
}
