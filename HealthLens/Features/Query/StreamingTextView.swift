import SwiftUI

struct StreamingTextView: View {
    let text: String
    var isStreaming: Bool = false
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // SwiftUI's Text init with LocalizedStringKey parses basic markdown
            // (**bold**, *italic*, `code`, etc.) without requiring AttributedString.
            Text(.init(text))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isStreaming {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 18)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: cursorVisible
                    )
                    .onAppear { cursorVisible = false }
            }
        }
    }
}

// MARK: - Markdown Block Model

private enum MDBlock {
    case heading2(String)
    case heading3(String)
    case bullet(depth: Int, text: String)
    case numbered(n: Int, text: String)
    case paragraph(String)
    case divider
}

// MARK: - Markdown-aware display view

struct MarkdownResponseView: View {
    let text: String
    var isStreaming: Bool = false
    @State private var cursorVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if text.isEmpty && isStreaming {
                thinkingIndicator
            } else {
                let blocks = Self.parseBlocks(text)
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    BlockRowView(block: block)
                }
                if isStreaming {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 16)
                        .opacity(cursorVisible ? 1 : 0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                            value: cursorVisible
                        )
                        .onAppear { cursorVisible = false }
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                ThinkingDot(index: index)
            }
            Text("Analyzing your health data…")
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(.secondaryText)
        }
    }

    // MARK: - Block Parser

    private static func parseBlocks(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraphLines = []
        }

        for line in text.components(separatedBy: .newlines) {
            let leading = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                flushParagraph()
                let prefix = trimmed.hasPrefix("## ") ? "## " : "# "
                blocks.append(.heading2(String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading3(String(trimmed.dropFirst(4))
                    .trimmingCharacters(in: .whitespaces)))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let depth = leading / 2
                blocks.append(.bullet(depth: depth, text: String(trimmed.dropFirst(2))))
            } else if let item = Self.parseNumberedItem(trimmed) {
                flushParagraph()
                blocks.append(.numbered(n: item.n, text: item.text))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraphLines.append(trimmed)
            }
        }
        flushParagraph()
        return blocks
    }

    private static func parseNumberedItem(_ line: String) -> (n: Int, text: String)? {
        var idx = line.startIndex
        var digits = ""
        while idx < line.endIndex && line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty, let n = Int(digits),
              idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let contentIdx = line.index(after: afterDot)
        return (n, String(line[contentIdx...]))
    }
}

// MARK: - Block Row View

private struct BlockRowView: View {
    let block: MDBlock

    var body: some View {
        switch block {
        case .heading2(let title):
            Text(title)
                .font(DesignTokens.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.xs)

        case .heading3(let title):
            Text(title)
                .font(DesignTokens.Typography.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DesignTokens.Spacing.sm)
                .padding(.bottom, 2)

        case .bullet(let depth, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, CGFloat(depth) * 12)
                Text(.init(text))
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)

        case .numbered(let n, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(n).")
                    .font(DesignTokens.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(.init(text))
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)

        case .paragraph(let text):
            Text(.init(text))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignTokens.Spacing.xs)

        case .divider:
            Divider()
                .padding(.vertical, DesignTokens.Spacing.xs)
        }
    }
}

// MARK: - Thinking Dot

private struct ThinkingDot: View {
    let index: Int
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .offset(y: animating ? -4 : 0)
            .animation(
                .easeInOut(duration: 0.45)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.15),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - Thinking Dots View (public — used by QueryView and AnalysisResultView)

struct ThinkingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .offset(y: animating ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
