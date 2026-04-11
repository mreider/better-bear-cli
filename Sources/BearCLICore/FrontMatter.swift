import Foundation

/// Lightweight YAML front matter parser/serializer for Bear notes.
/// Handles the `---` delimited block at the top of a note.
/// No external YAML dependency — supports flat key-value pairs,
/// inline arrays, quoted strings, and booleans.
public struct FrontMatter {
    /// Ordered key-value pairs preserving insertion order.
    public private(set) var fields: [(key: String, value: String)]

    public init(fields: [(key: String, value: String)] = []) {
        self.fields = fields
    }

    /// Create from "key=value" strings (as used in CLI --fm arguments).
    public init(fromPairs pairs: [String]) {
        self.fields = pairs.compactMap { pair in
            guard let eqIdx = pair.firstIndex(of: "=") else { return nil }
            let key = String(pair[pair.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return (key, value)
        }
    }

    // MARK: - Parse

    /// Parse front matter from the beginning of a markdown string.
    /// Returns (frontMatter, remainingBody). If no front matter, returns (nil, originalText).
    public static func parse(_ text: String) -> (FrontMatter?, String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, text)
        }

        // Find the closing ---
        var closingIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let endIdx = closingIndex else {
            return (nil, text)
        }

        // Parse the fields between the --- delimiters
        var fields: [(key: String, value: String)] = []
        for i in 1..<endIdx {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and YAML comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Split on first ":"
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            guard !key.isEmpty else { continue }

            // Unquote if wrapped in quotes
            let value: String
            if (rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"")) ||
               (rawValue.hasPrefix("'") && rawValue.hasSuffix("'")) {
                value = String(rawValue.dropFirst().dropLast())
            } else {
                value = rawValue
            }

            fields.append((key, value))
        }

        // Build remaining body (everything after the closing ---)
        let bodyLines = Array(lines[(endIdx + 1)...])
        let body = bodyLines.joined(separator: "\n")

        return (FrontMatter(fields: fields), body)
    }

    // MARK: - Accessors

    /// Get a field value by key.
    public func get(_ key: String) -> String? {
        fields.first(where: { $0.key == key })?.value
    }

    /// Set or update a field. Returns a new FrontMatter.
    public func setting(_ key: String, value: String) -> FrontMatter {
        var newFields = fields
        if let idx = newFields.firstIndex(where: { $0.key == key }) {
            newFields[idx] = (key, value)
        } else {
            newFields.append((key, value))
        }
        return FrontMatter(fields: newFields)
    }

    /// Remove a field by key. Returns a new FrontMatter.
    public func removing(_ key: String) -> FrontMatter {
        FrontMatter(fields: fields.filter { $0.key != key })
    }

    /// Merge with another FrontMatter. Other's fields are added if not already present.
    public func merging(with other: FrontMatter) -> FrontMatter {
        var result = self
        for (key, value) in other.fields {
            if result.get(key) == nil {
                result = result.setting(key, value: value)
            }
        }
        return result
    }

    // MARK: - Serialize

    /// Serialize to a YAML front matter block string (with --- delimiters and trailing newline).
    public func toString() -> String {
        guard !fields.isEmpty else { return "" }
        var result = "---\n"
        for (key, value) in fields {
            result += "\(key): \(quoteIfNeeded(value))\n"
        }
        result += "---\n"
        return result
    }

    /// Build full note text: front matter + body.
    public func toNoteText(body: String) -> String {
        if fields.isEmpty {
            return body
        }
        let fm = toString()
        // Ensure there's a blank line between front matter and body
        if body.hasPrefix("\n") {
            return fm + body
        }
        return fm + body
    }

    /// Convert fields to a JSON-compatible dictionary.
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in fields {
            // Try to preserve types
            if value == "true" {
                dict[key] = true
            } else if value == "false" {
                dict[key] = false
            } else if let intVal = Int64(value) {
                dict[key] = intVal
            } else if let doubleVal = Double(value), value.contains(".") {
                dict[key] = doubleVal
            } else if value.hasPrefix("[") && value.hasSuffix("]") {
                // Inline array: [a, b, c]
                let inner = String(value.dropFirst().dropLast())
                let items = inner.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                     .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                dict[key] = items
            } else {
                dict[key] = value
            }
        }
        return dict
    }

    // MARK: - Private

    /// Quote a value if it contains YAML-special characters.
    private func quoteIfNeeded(_ value: String) -> String {
        let needsQuoting = value.contains(":") || value.contains("#") ||
            value.contains("{") || value.contains("}") ||
            value.contains("[") || value.contains("]") ||
            value.contains(",") || value.contains("&") ||
            value.contains("*") || value.contains("!") ||
            value.contains("|") || value.contains(">") ||
            value.contains("'") || value.contains("\"") ||
            value.contains("%") || value.contains("@") ||
            value.hasPrefix(" ") || value.hasSuffix(" ")

        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
