import Foundation

/// Extract hashtags from Bear-flavoured markdown and reason about hierarchical
/// tag relationships. Used to keep the CloudKit `tagsStrings` / `tags` index in
/// sync with the actual `#hashtags` that appear in a note's body.
public enum TagParser {

    /// Extract hashtag names from markdown body text.
    ///
    /// Rules (matching Bear's own behaviour conservatively):
    ///   - `#tag` must start at line-start or after whitespace
    ///   - `#tag/child` is allowed; `/` is part of the tag
    ///   - `#multi word tag#` form: `#` … `#` on one line with spaces inside
    ///   - Fenced code blocks (``` or ~~~) are skipped
    ///   - Inline code (`…`) is skipped
    ///   - Markdown headings (`# `, `## `, … `###### `) are skipped
    ///   - Trailing punctuation (.,:;)]!?/) is stripped from simple tags
    public static func extractTags(from text: String) -> [String] {
        var tags: [String] = []
        var seen = Set<String>()
        var inFence = false
        var inFrontMatter = false
        var sawFirstNonEmpty = false

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // YAML front matter: a `---` line as the first non-empty line opens
            // a frontmatter block; the next `---` closes it. Skip contents.
            if !sawFirstNonEmpty {
                if trimmed.isEmpty { continue }
                sawFirstNonEmpty = true
                if trimmed == "---" {
                    inFrontMatter = true
                    continue
                }
            }
            if inFrontMatter {
                if trimmed == "---" { inFrontMatter = false }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if isHeadingLine(rawLine) { continue }
            extractFromLine(rawLine, into: &tags, seen: &seen)
        }
        return tags
    }

    /// Expand hierarchical tags to include their ancestors.
    /// `["a/b/c"]` → `["a/b/c", "a/b", "a"]`. Deduplicates across the input
    /// while preserving leaf-first order per input tag (matches Bear desktop).
    public static func expandAncestors(_ tags: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for tag in tags {
            let parts = tag.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            for i in stride(from: parts.count, through: 1, by: -1) {
                let prefix = parts.prefix(i).joined(separator: "/")
                if seen.insert(prefix).inserted {
                    result.append(prefix)
                }
            }
        }
        return result
    }

    /// Return only "leaf" tags — tags with no strict descendant in the input.
    /// For `["parent", "parent/child"]` returns `["parent/child"]`.
    public static func leafTags(_ tags: [String]) -> [String] {
        tags.filter { t in
            !tags.contains(where: { $0 != t && $0.hasPrefix(t + "/") })
        }
    }

    /// Compute the new indexed-tag list after removing `tag` from `strings`,
    /// additionally pruning any ancestor that no longer has a descendant in
    /// the result. Input order of surviving entries is preserved.
    ///
    /// The ancestor pass walks **deep → shallow** so that each ancestor's
    /// "do I still have a descendant?" check sees the removals made in prior
    /// iterations. Walking shallow → deep strands the shallowest ancestor:
    /// given `["a/b/c", "a/b", "a"]` and removal of `"a/b/c"`, the old order
    /// left `"a"` in the result because `"a/b"` was still present when `"a"`
    /// was evaluated. See the matching unit tests.
    ///
    /// Pure and order-stable — safe to unit-test without CloudKit.
    public static func remainingTagsAfterRemoval(
        from strings: [String], removing tag: String
    ) -> [String] {
        var result = strings
        result.removeAll(where: { $0 == tag })

        let parts = tag.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return result }

        for i in (1..<parts.count).reversed() {
            let ancestor = parts.prefix(i).joined(separator: "/")
            let stillHasDescendant = result.contains { $0.hasPrefix(ancestor + "/") }
            if !stillHasDescendant {
                result.removeAll(where: { $0 == ancestor })
            }
        }
        return result
    }

    /// Remove every occurrence of `#tagName` (or `#multi word tag#`) from a
    /// markdown body, honouring tag-boundary rules so that stripping `parent`
    /// does not truncate `#parent/child`. Collapses the adjacent space so the
    /// body doesn't accumulate double-spaces.
    public static func stripTag(from text: String, name: String) -> String {
        let marker = name.contains(" ") ? "#\(name)#" : "#\(name)"

        var resultLines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == marker {
                continue
            }
            resultLines.append(stripMarker(in: line, marker: marker, multiWord: name.contains(" ")))
        }
        return resultLines.joined(separator: "\n")
    }

    private static func stripMarker(in line: String, marker: String, multiWord: Bool) -> String {
        var out = ""
        var i = line.startIndex
        while i < line.endIndex {
            if line[i...].hasPrefix(marker) {
                let after = line.index(i, offsetBy: marker.count)
                // For simple tags, refuse to strip if the char right after is a
                // tag-continuing character (letter, digit, /, _, -) — that
                // means `#parent` is actually the start of `#parent/child`.
                let continues: Bool = {
                    guard !multiWord, after < line.endIndex else { return false }
                    let c = line[after]
                    return c.isLetter || c.isNumber || c == "/" || c == "_" || c == "-"
                }()
                if !continues {
                    // Consume one trailing space if present, else trim one leading space from `out`.
                    if after < line.endIndex, line[after] == " " {
                        i = line.index(after: after)
                    } else {
                        if out.hasSuffix(" ") { out.removeLast() }
                        i = after
                    }
                    continue
                }
            }
            out.append(line[i])
            i = line.index(after: i)
        }
        return out
    }

    // MARK: - Private

    private static func isHeadingLine(_ line: String) -> Bool {
        guard let first = line.firstIndex(where: { !$0.isWhitespace }) else { return false }
        var i = first
        var hashes = 0
        while i < line.endIndex, line[i] == "#", hashes < 6 {
            hashes += 1
            i = line.index(after: i)
        }
        guard hashes > 0, i < line.endIndex else { return false }
        return line[i] == " "
    }

    private static func extractFromLine(
        _ line: String, into tags: inout [String], seen: inout Set<String>
    ) {
        let chars = Array(line)
        var i = 0
        var inInlineCode = false

        while i < chars.count {
            let c = chars[i]

            if c == "`" {
                inInlineCode.toggle()
                i += 1
                continue
            }
            if inInlineCode {
                i += 1
                continue
            }

            if c == "#" {
                let precededByBoundary = (i == 0) || chars[i - 1].isWhitespace
                if !precededByBoundary {
                    i += 1
                    continue
                }
                let nextIdx = i + 1
                if nextIdx >= chars.count {
                    i += 1
                    continue
                }
                let next = chars[nextIdx]
                if next == "#" || next.isWhitespace {
                    i += 1
                    continue
                }

                // Multi-word `#...#` form: a closing `#` on the same line with
                // only tag-chars and spaces in between. If any non-tag-char
                // (like `,` or `.`) appears, bail — those are two simple tags.
                var j = nextIdx
                var closeIdx: Int? = nil
                var sawSpace = false
                var allValid = true
                while j < chars.count {
                    let ch = chars[j]
                    if ch == "#" {
                        closeIdx = j
                        break
                    }
                    if ch == " " || ch == "\t" {
                        sawSpace = true
                    } else if !isTagChar(ch) {
                        allValid = false
                        break
                    }
                    j += 1
                }

                // Reject if the char right before the closing `#` is a space —
                // that means the closing `#` is actually the start of a new
                // simple tag, not the end of this one.
                if allValid, sawSpace, let close = closeIdx,
                   close > nextIdx, !chars[close - 1].isWhitespace {
                    let name = String(chars[nextIdx..<close]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        append(name, to: &tags, seen: &seen)
                    }
                    i = close + 1
                    continue
                }

                // Simple tag: walk while tag-chars (letter/digit/_/-//).
                var k = nextIdx
                while k < chars.count, isTagChar(chars[k]) {
                    k += 1
                }
                let name = String(chars[nextIdx..<k])
                if !name.isEmpty {
                    append(name, to: &tags, seen: &seen)
                }
                // Advance past the tag. If we stopped on `#`, don't consume it
                // so the outer loop can re-evaluate it as a new boundary.
                i = k
                continue
            }

            i += 1
        }
    }

    private static func isTagChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "/"
    }

    private static func append(_ tag: String, to tags: inout [String], seen: inout Set<String>) {
        if seen.insert(tag).inserted {
            tags.append(tag)
        }
    }

    /// Rename every occurrence of a tag prefix in the body markdown, keeping
    /// sub-tag tails intact. `#old` → `#new`, `#old/sub` → `#new/sub`.
    /// A tag is only rewritten when the prefix is followed by end-of-tag
    /// (whitespace, punctuation, `/`, or end-of-line); `#oldfoo` is left alone.
    public static func renameTagPrefix(in text: String, from oldPrefix: String, to newPrefix: String) -> String {
        guard !oldPrefix.isEmpty, oldPrefix != newPrefix else { return text }
        let lines = text.components(separatedBy: "\n").map {
            renameLine($0, oldPrefix: oldPrefix, newPrefix: newPrefix)
        }
        return lines.joined(separator: "\n")
    }

    private static func renameLine(_ line: String, oldPrefix: String, newPrefix: String) -> String {
        let chars = Array(line)
        let old = Array(oldPrefix)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "#" {
                let boundary = (i == 0) || chars[i - 1].isWhitespace
                if boundary, matches(chars: chars, at: i + 1, prefix: old) {
                    let afterPrefix = i + 1 + old.count
                    if afterPrefix >= chars.count {
                        out.append("#" + newPrefix)
                        i = afterPrefix
                        continue
                    }
                    let next = chars[afterPrefix]
                    if next == "/" {
                        var k = afterPrefix
                        while k < chars.count, isTagChar(chars[k]) { k += 1 }
                        let tail = String(chars[afterPrefix..<k])
                        out.append("#" + newPrefix + tail)
                        i = k
                        continue
                    }
                    if !isTagChar(next) {
                        out.append("#" + newPrefix)
                        i = afterPrefix
                        continue
                    }
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func matches(chars: [Character], at start: Int, prefix: [Character]) -> Bool {
        guard start + prefix.count <= chars.count else { return false }
        for j in 0..<prefix.count where chars[start + j] != prefix[j] { return false }
        return true
    }
}
