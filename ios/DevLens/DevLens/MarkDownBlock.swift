enum MarkdownBlock: Equatable {
    case text(String)
    case heading(level: Int, text: String)
    case code(language: String, content: String)
    case list(start: Int?, items: [[MarkdownBlock]])
    case quote([MarkdownBlock])
}
