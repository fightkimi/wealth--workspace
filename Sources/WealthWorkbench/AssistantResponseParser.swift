import Foundation

enum AssistantResponseBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case table(headers: [String], rows: [[String]])
}

enum AssistantResponseParser {
    static func parse(_ markdown: String) -> [AssistantResponseBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [AssistantResponseBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bullets(bullets))
            bullets.removeAll()
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushBullets()
                index += 1
                continue
            }

            if line.hasPrefix("#") {
                flushParagraph()
                flushBullets()
                let title = line.drop(while: { $0 == "#" || $0 == " " })
                if !title.isEmpty { blocks.append(.heading(String(title))) }
                index += 1
                continue
            }

            if index + 1 < lines.count,
               isTableRow(line),
               isTableSeparator(lines[index + 1]) {
                flushParagraph()
                flushBullets()
                let headers = cells(in: line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count, isTableRow(lines[index]) {
                    let row = cells(in: lines[index])
                    guard !row.isEmpty else { break }
                    rows.append(normalized(row, count: headers.count))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if let bullet = bulletText(line) {
                flushParagraph()
                bullets.append(bullet)
                index += 1
                continue
            }

            flushBullets()
            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        flushBullets()
        return blocks
    }

    private static func isTableRow(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespaces)
        return value.hasPrefix("|") && value.dropFirst().contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let values = cells(in: line)
        guard !values.isEmpty else { return false }
        return values.allSatisfy { value in
            let cleaned = value.replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return cleaned.count >= 3 && cleaned.allSatisfy { $0 == "-" }
        }
    }

    private static func cells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func normalized(_ row: [String], count: Int) -> [String] {
        if row.count == count { return row }
        if row.count > count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let prefix = line[..<dot]
        guard prefix.allSatisfy(\.isNumber) else { return nil }
        let next = line.index(after: dot)
        guard next < line.endIndex, line[next] == " " else { return nil }
        return String(line[line.index(after: next)...]).trimmingCharacters(in: .whitespaces)
    }
}
