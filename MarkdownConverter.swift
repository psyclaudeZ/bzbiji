import Foundation

enum MarkdownConverter {
    static func toHTML(_ markdown: String) -> String { wrapHTML(toBodyHTML(markdown)) }

    static func toBodyHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var i = 0
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLang = ""

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
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                i += 1; continue
            }
            if inCodeBlock { codeLines.append(line); i += 1; continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                html += "\n"; i += 1; continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html += "<hr>\n"; i += 1; continue
            }

            // Table: header row followed by separator row
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSep(lines[i + 1]) {
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

            // Lists are parsed as a complete indentation-aware block so child
            // bullets and numbers become nested lists inside their parent item.
            if let item = listItem(in: line) {
                html += renderList(lines, index: &i, indent: item.indent, kind: item.kind)
                continue
            }

            // Headers
            if line.hasPrefix("######") {
                html += "<h6>\(inline(String(line.dropFirst(7))))</h6>\n"
            } else if line.hasPrefix("#####") {
                html += "<h5>\(inline(String(line.dropFirst(6))))</h5>\n"
            } else if line.hasPrefix("####") {
                html += "<h4>\(inline(String(line.dropFirst(5))))</h4>\n"
            } else if line.hasPrefix("###") {
                html += "<h3>\(inline(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("##") {
                html += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                html += "<h1>\(inline(String(line.dropFirst(2))))</h1>\n"
            }
            // Blockquote
            else if line.hasPrefix("> ") {
                html += "<blockquote><p>\(inline(String(line.dropFirst(2))))</p></blockquote>\n"
            }
            // Paragraph
            else {
                html += "<p>\(inline(line))</p>\n"
            }

            i += 1
        }

        return html
    }

    // MARK: - Helpers

    private enum ListKind: Equatable {
        case unordered
        case ordered
    }

    private struct ParsedListItem {
        let indent: Int
        let kind: ListKind
        let text: String
        let number: Int?
    }

    private static func listItem(in line: String) -> ParsedListItem? {
        var index = line.startIndex
        var indent = 0
        while index < line.endIndex {
            if line[index] == " " {
                indent += 1
            } else if line[index] == "\t" {
                indent += 4
            } else {
                break
            }
            index = line.index(after: index)
        }

        let content = String(line[index...])
        if content.hasPrefix("- ") || content.hasPrefix("* ") || content.hasPrefix("+ ") {
            return ParsedListItem(
                indent: indent,
                kind: .unordered,
                text: String(content.dropFirst(2)),
                number: nil
            )
        }

        var markerEnd = content.startIndex
        while markerEnd < content.endIndex && content[markerEnd].isNumber {
            markerEnd = content.index(after: markerEnd)
        }
        guard markerEnd > content.startIndex,
              markerEnd < content.endIndex,
              content[markerEnd] == "." else { return nil }
        let afterDot = content.index(after: markerEnd)
        guard afterDot < content.endIndex, content[afterDot] == " " else { return nil }

        return ParsedListItem(
            indent: indent,
            kind: .ordered,
            text: String(content[content.index(after: afterDot)...]),
            number: Int(content[..<markerEnd])
        )
    }

    private static func renderList(_ lines: [String], index: inout Int,
                                   indent: Int, kind: ListKind) -> String {
        let tag = kind == .unordered ? "ul" : "ol"
        let first = listItem(in: lines[index])
        let start = kind == .ordered && first?.number != 1
            ? " start=\"\(first?.number ?? 1)\""
            : ""
        var html = "<\(tag)\(start)>\n"

        while index < lines.count,
              let item = listItem(in: lines[index]),
              item.indent == indent,
              item.kind == kind {
            let itemHTML = kind == .unordered ? taskItem(item.text) : inline(item.text)
            html += "<li>\(itemHTML)"
            index += 1

            while index < lines.count,
                  let child = listItem(in: lines[index]),
                  child.indent > indent {
                html += "\n" + renderList(
                    lines,
                    index: &index,
                    indent: child.indent,
                    kind: child.kind
                )
            }

            html += "</li>\n"
        }

        html += "</\(tag)>\n"
        return html
    }

    private static func taskItem(_ text: String) -> String {
        if text.hasPrefix("[ ] ") {
            return "<input type=\"checkbox\" disabled> \(inline(String(text.dropFirst(4))))"
        } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return "<input type=\"checkbox\" disabled checked> \(inline(String(text.dropFirst(4))))"
        }
        return inline(text)
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
        html {
            scroll-behavior: smooth;
            background: #f5f2ea;
        }
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
            html { background: #262522; }
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
        /* Fixed marker column: markers align to the parent text edge while item
           copy starts 2em to the right, including for multi-digit numbers. */
        ul, ol { list-style: none; padding-left: 2em; margin: 0.4em 0; }
        li { position: relative; margin: 0.25em 0; }
        ul > li::before, ol > li::before {
            position: absolute;
            left: -2em;
            width: 1.5em;
            text-align: left;
        }
        ul > li::before { content: "•"; }
        ol { counter-reset: bzbiji-list-item; }
        ol > li { counter-increment: bzbiji-list-item; }
        ol > li::before { content: counter(bzbiji-list-item) "."; }
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
        mark.bzbiji-hit {
            background: rgba(255, 213, 79, 0.75);
            color: #1a1a1a;
            border-radius: 3px;
            padding: 1px 2px;
            box-shadow: 0 0 0 1px rgba(200, 140, 0, 0.45);
        }
        mark.bzbiji-hit-current {
            background: #ff9500;
            color: #000;
            box-shadow: 0 0 0 2px #ff9500, 0 0 10px 2px rgba(255, 149, 0, 0.85);
        }
        @media (prefers-color-scheme: dark) {
            mark.bzbiji-hit { background: rgba(255, 200, 70, 0.55); color: #1a1a1a; }
            mark.bzbiji-hit-current { background: #ffb020; color: #000; box-shadow: 0 0 0 2px #ffb020, 0 0 12px 3px rgba(255, 176, 32, 0.9); }
        }
        </style>
        </head>
        <body>
        <div id="bzbiji-content">\(body)</div>
        <script>
        (function(){
          var hits = [], curr = -1, lastQ = null;
          function clear() {
            hits.forEach(function(m){
              var p = m.parentNode;
              if (p) { p.replaceChild(document.createTextNode(m.textContent), m); p.normalize(); }
            });
            hits = []; curr = -1; lastQ = null;
          }
          function showCurrent() {
            hits.forEach(function(h, i){ h.classList.toggle('bzbiji-hit-current', i === curr); });
            var h = hits[curr];
            if (h) h.scrollIntoView({block:'center', behavior:'smooth'});
          }
          window.__bzbijiClearHits = clear;
          window.__bzbijiSearch = function(q, dir) {
            if (lastQ === q && hits.length) {
              curr = (curr + dir + hits.length) % hits.length;
              showCurrent();
              return hits.length;
            }
            clear();
            if (!q) return 0;
            lastQ = q;
            var qq = q.toLowerCase();
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
              acceptNode: function(n) {
                var t = n.parentNode && n.parentNode.nodeName;
                if (t === 'SCRIPT' || t === 'STYLE' || t === 'MARK') return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
              }
            });
            var nodes = [], n;
            while ((n = walker.nextNode())) nodes.push(n);
            nodes.forEach(function(node){
              var text = node.nodeValue;
              var lower = text.toLowerCase();
              var pos = 0, idx, had = false;
              var frag = document.createDocumentFragment();
              while ((idx = lower.indexOf(qq, pos)) !== -1) {
                if (idx > pos) frag.appendChild(document.createTextNode(text.slice(pos, idx)));
                var m = document.createElement('mark');
                m.className = 'bzbiji-hit';
                m.textContent = text.slice(idx, idx + qq.length);
                frag.appendChild(m);
                hits.push(m);
                pos = idx + qq.length;
                had = true;
              }
              if (had) {
                if (pos < text.length) frag.appendChild(document.createTextNode(text.slice(pos)));
                node.parentNode.replaceChild(frag, node);
              }
            });
            if (hits.length) {
              curr = dir >= 0 ? 0 : hits.length - 1;
              showCurrent();
            }
            return hits.length;
          };
        })();
        </script>
        </body>
        </html>
        """
    }
}
