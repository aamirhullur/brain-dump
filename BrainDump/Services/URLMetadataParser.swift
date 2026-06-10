import Foundation

struct URLMetadata: Equatable {
    var title: String?
    var description: String?
    var ogTitle: String?
    var ogDescription: String?
    var ogImage: String?

    var bestTitle: String? {
        ogTitle ?? title
    }

    var bestDescription: String? {
        ogDescription ?? description
    }

    var contentText: String {
        [bestTitle, bestDescription].compactMap { $0 }.joined(separator: "\n")
    }

    var metadataJSON: String {
        var object: [String: String] = [:]
        object["title"] = title
        object["description"] = description
        object["og_title"] = ogTitle
        object["og_description"] = ogDescription
        object["og_image"] = ogImage
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum URLMetadataParser {
    static func parse(html: String) -> URLMetadata {
        var metadata = URLMetadata()

        if let rawTitle = firstCapture(in: html, pattern: "<title[^>]*>(.*?)</title\\s*>") {
            let normalized = normalize(rawTitle)
            metadata.title = normalized.isEmpty ? nil : normalized
        }

        for tag in matches(in: html, pattern: "<meta\\b[^>]*>") {
            let attributes = attributes(in: tag)
            guard let content = attributes["content"], !content.isEmpty else { continue }
            let key = attributes["property"] ?? attributes["name"]
            switch key?.lowercased() {
            case "og:title":
                metadata.ogTitle = metadata.ogTitle ?? content
            case "og:description":
                metadata.ogDescription = metadata.ogDescription ?? content
            case "og:image":
                metadata.ogImage = metadata.ogImage ?? content
            case "description":
                metadata.description = metadata.description ?? content
            default:
                break
            }
        }

        return metadata
    }

    private static func firstCapture(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static func matches(in html: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            Range(match.range, in: html).map { String(html[$0]) }
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = "([a-zA-Z][a-zA-Z0-9:_-]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }

        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = tag[nameRange].lowercased()
            let rawValue: String
            if let doubleQuoted = Range(match.range(at: 3), in: tag) {
                rawValue = String(tag[doubleQuoted])
            } else if let singleQuoted = Range(match.range(at: 4), in: tag) {
                rawValue = String(tag[singleQuoted])
            } else {
                continue
            }
            result[name] = normalize(rawValue)
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        decodeEntities(value)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }

        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "&",
               let semicolon = value[index...].firstIndex(of: ";"),
               value.distance(from: index, to: semicolon) <= 12 {
                let name = String(value[value.index(after: index)..<semicolon])
                if let decoded = decodeEntity(name) {
                    result.append(decoded)
                    index = value.index(after: semicolon)
                    continue
                }
            }
            result.append(character)
            index = value.index(after: index)
        }
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        switch name.lowercased() {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        case "nbsp":
            return " "
        default:
            break
        }
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            guard let code = UInt32(name.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) else { return nil }
            return String(Character(scalar))
        }
        if name.hasPrefix("#") {
            guard let code = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(code) else { return nil }
            return String(Character(scalar))
        }
        return nil
    }
}
