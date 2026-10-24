import Markdown

struct MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let document = Document(parsing: source)
        return parseChildren(of: document)
    }

    private static func parseChildren(
        of parent: any Markup
    ) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        for child in parent.children {
            if let codeBlock = child as? CodeBlock {
                blocks.append(
                    .code(
                        language: codeBlock.language ?? "",
                        content: codeBlock.code
                    )
                )
            } else if let heading = child as? Heading {
                var formatter = MarkupFormatter()

                for inline in heading.children {
                    formatter.visit(inline.detachedFromParent)
                }

                blocks.append(
                    .heading(
                        level: heading.level,
                        text: formatter.result
                    )
                )
            } else if let list = child as? OrderedList {
                blocks.append(
                    parseList(list, start: Int(list.startIndex))
                )
            } else if let list = child as? UnorderedList {
                blocks.append(
                    parseList(list, start: nil)
                )
            } else if let quote = child as? BlockQuote {
                let content = parseChildren(of: quote)
                blocks.append(.quote(content))
            } else {
                var formatter = MarkupFormatter()
                formatter.visit(child.detachedFromParent)

                blocks.append(.text(formatter.result))
            }
        }

        return blocks
    }

    private static func parseList(
        _ list: any Markup,
        start: Int?
    ) -> MarkdownBlock {
        var items: [[MarkdownBlock]] = []

        for item in list.children {
            let blocks = parseChildren(of: item)
            items.append(blocks)
        }

        return .list(start: start, items: items)
    }
}
