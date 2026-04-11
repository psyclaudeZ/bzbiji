import Foundation

enum MarkdownConverter {
    static func toHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var i = 0
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLang = ""
        var inUL = false
        var inOL = false

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                if inCodeBlock {
                    let code = codeLines.joined(separator: "\n")
                    let lang = codeLang.isEmpty ? "" : " class=\"language-\(codeLang)\""
                    html += "<pre><code\(lang)>\(esc(code))</code></pre>\n"
                    codeLines = []; codeLang = ""; inCodeBlock = false
                } else {
                    closeLists(&html, ul: &inUL, ol: &inOL)
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                i += 1; continue
            }
            if inCodeBlock { codeLines.append(line); i += 1; continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "\n"; i += 1; continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<hr>\n"; i += 1; continue
            }

            // Table: header row followed by separator row
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSep(lines[i + 1]) {
                closeLists(&html, ul: &inUL, ol: &inOL)
                let headers = tableRow(line)
                i += 2
                html += "<table><thead><tr>"
                for h in headers { html += "<th>\(inline(h))</th>" }
                html += "</tr></thead><tbody>"
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    html += "<tr>"
                    for c in tableRow(lines[i]) { html += "<td>\(inline(c))</td>" }
                    html += "</tr>"
                    i += 1
                }
                html += "</tbody></table>\n"
                continue
            }

            // Headers
            if line.hasPrefix("######") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<h6>\(inline(String(line.dropFirst(7))))</h6>\n"
            } else if line.hasPrefix("#####") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<h5>\(inline(String(line.dropFirst(6))))</h5>\n"
            } else if line.hasPrefix("####") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<h4>\(inline(String(line.dropFirst(5))))</h4>\n"
            } else if line.hasPrefix("###") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<h3>\(inline(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("##") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<h1>\(inline(String(line.dropFirst(2))))</h1>\n"
            }
            // Blockquote
            else if line.hasPrefix("> ") {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<blockquote><p>\(inline(String(line.dropFirst(2))))</p></blockquote>\n"
            }
            // Unordered list (including task list items)
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                if inOL { html += "</ol>\n"; inOL = false }
                if !inUL { html += "<ul>\n"; inUL = true }
                html += "<li>\(taskItem(String(line.dropFirst(2))))</li>\n"
            }
            // Ordered list
            else if let text = orderedItem(line) {
                if inUL { html += "</ul>\n"; inUL = false }
                if !inOL { html += "<ol>\n"; inOL = true }
                html += "<li>\(inline(text))</li>\n"
            }
            // Paragraph
            else {
                closeLists(&html, ul: &inUL, ol: &inOL)
                html += "<p>\(inline(line))</p>\n"
            }

            i += 1
        }

        closeLists(&html, ul: &inUL, ol: &inOL)
        return wrapHTML(html)
    }

    // MARK: - Helpers

    private static func closeLists(_ html: inout String, ul: inout Bool, ol: inout Bool) {
        if ul { html += "</ul>\n"; ul = false }
        if ol { html += "</ol>\n"; ol = false }
    }

    private static func taskItem(_ text: String) -> String {
        if text.hasPrefix("[ ] ") {
            return "<input type=\"checkbox\" disabled> \(inline(String(text.dropFirst(4))))"
        } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return "<input type=\"checkbox\" disabled checked> \(inline(String(text.dropFirst(4))))"
        }
        return inline(text)
    }

    private static func orderedItem(_ line: String) -> String? {
        var idx = line.startIndex
        while idx < line.endIndex && line[idx].isNumber { idx = line.index(after: idx) }
        guard idx > line.startIndex, idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    private static func isTableSep(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard s.contains("|") else { return false }
        return s.components(separatedBy: "|")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).allSatisfy { $0 == "-" || $0 == ":" } }
    }

    private static func tableRow(_ line: String) -> [String] {
        var cells = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func inline(_ text: String) -> String {
        var r = text
        r = rx(r, #"\*\*\*(.+?)\*\*\*"#, "<strong><em>$1</em></strong>")
        r = rx(r, #"\*\*(.+?)\*\*"#,     "<strong>$1</strong>")
        r = rx(r, #"__(.+?)__"#,          "<strong>$1</strong>")
        r = rx(r, #"\*(.+?)\*"#,          "<em>$1</em>")
        r = rx(r, #"_(.+?)_"#,            "<em>$1</em>")
        r = rx(r, #"~~(.+?)~~"#,          "<del>$1</del>")
        r = rx(r, #"`(.+?)`"#,            "<code>$1</code>")
        r = rx(r, #"!\[(.+?)\]\((.+?)\)"#, "<img alt=\"$1\" src=\"$2\" style=\"max-width:100%\">")
        r = rx(r, #"\[(.+?)\]\((.+?)\)"#,  "<a href=\"$2\">$1</a>")
        return r
    }

    private static func rx(_ s: String, _ pattern: String, _ replacement: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: replacement)
    }

    static func wrapHTML(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        html { scroll-behavior: smooth; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            font-size: 15px;
            line-height: 1.7;
            padding: 28px 32px;
            margin: 0;
            color: #1a1a1a;
            background: transparent;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #e8e8e8; }
            code { background: rgba(255,255,255,0.1); }
            pre  { background: rgba(255,255,255,0.07); }
            a { color: #5aafff; }
            blockquote { border-color: rgba(255,255,255,0.2); color: rgba(255,255,255,0.55); }
            th { background: rgba(255,255,255,0.05); }
            th, td { border-color: rgba(255,255,255,0.15); }
        }
        h1 { font-size: 1.85em; font-weight: 700; margin: 0 0 0.5em; }
        h2 { font-size: 1.45em; font-weight: 600; margin: 1.2em 0 0.4em; }
        h3 { font-size: 1.2em;  font-weight: 600; margin: 1em 0 0.3em; }
        h4,h5,h6 { font-size: 1em; font-weight: 600; margin: 0.8em 0 0.3em; }
        p { margin: 0.5em 0; }
        code {
            font-family: 'SF Mono', Menlo, monospace;
            background: rgba(0,0,0,0.06);
            padding: 2px 5px;
            border-radius: 4px;
            font-size: 0.87em;
        }
        pre {
            background: rgba(0,0,0,0.05);
            border-radius: 8px;
            padding: 16px;
            overflow-x: auto;
            margin: 0.8em 0;
        }
        pre code { background: none; padding: 0; font-size: 0.9em; }
        ul, ol { padding-left: 1.6em; margin: 0.4em 0; }
        li { margin: 0.25em 0; }
        input[type="checkbox"] { margin-right: 5px; accent-color: #0066cc; }
        blockquote {
            border-left: 3px solid rgba(0,0,0,0.18);
            margin: 0.8em 0;
            padding: 0.1em 0 0.1em 1em;
            color: rgba(0,0,0,0.55);
        }
        hr { border: none; border-top: 1px solid rgba(0,0,0,0.1); margin: 1.5em 0; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
        del { opacity: 0.55; }
        img { max-width: 100%; border-radius: 6px; }
        table { border-collapse: collapse; width: 100%; margin: 0.8em 0; font-size: 0.95em; }
        th, td { border: 1px solid rgba(0,0,0,0.12); padding: 7px 12px; text-align: left; }
        th { background: rgba(0,0,0,0.04); font-weight: 600; }
        tr:nth-child(even) td { background: rgba(0,0,0,0.02); }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
