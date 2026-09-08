import Foundation

/// Inline markup carried inside SRT / WebVTT / mov_text cue bodies.
///
/// Cue text in the wild mixes HTML-ish tags (`<i>`, `<font color=…>`, `<v Speaker>`),
/// ASS override blocks (`{\i1}`), WebVTT karaoke timestamps and XML entities into the
/// text payload. Neither the sidecar renderer nor `AVPlayerItemLegibleOutput` removes
/// those, so they reach `NativeSubtitleOverlay` verbatim and draw as literal characters.
enum SubtitleMarkup {
    struct Parsed: Equatable {
        var text: String
        /// UTF-16 ranges of `text` that were marked italic.
        var italicRanges: [NSRange]

        static let empty = Parsed(text: "", italicRanges: [])
    }

    static func plainText(_ raw: String) -> String {
        parse(raw).text
    }

    /// Removes markup and reports the italic runs of the surviving text.
    ///
    /// Unbalanced italics are tolerated: a second `<i>` while already italic closes the
    /// run, since files that write `<i>text<i>` instead of `<i>text</i>` are common.
    static func parse(_ raw: String) -> Parsed {
        guard raw.contains(where: { $0 == "<" || $0 == "{" || $0 == "&" }) else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return Parsed(text: trimmed, italicRanges: [])
        }

        var out = ""
        var length = 0
        var ranges: [NSRange] = []
        var italicStart: Int?
        var italicPending = false
        var pendingSpace = false
        var atLineStart = true

        func emit(_ character: Character) {
            if character == "\n" {
                pendingSpace = false
                out.append("\n")
                length += 1
                atLineStart = true
                return
            }
            if character == " " || character == "\t" || character == "\r" {
                pendingSpace = true
                return
            }
            if pendingSpace {
                pendingSpace = false
                if !out.isEmpty, !atLineStart {
                    out.append(" ")
                    length += 1
                }
            }
            if italicPending {
                italicPending = false
                italicStart = length
            }
            out.append(character)
            length += character.utf16Count
            atLineStart = false
        }

        func closeItalic() {
            if italicPending {
                italicPending = false
                return
            }
            if let start = italicStart, length > start {
                ranges.append(NSRange(location: start, length: length - start))
            }
            italicStart = nil
        }

        func openItalic() {
            guard italicStart == nil, !italicPending else {
                closeItalic()
                return
            }
            italicPending = true
        }

        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "<", let tag = readTag(raw, from: index) {
                if tag.name == "i" {
                    if tag.isClosing {
                        closeItalic()
                    } else {
                        openItalic()
                    }
                }
                index = tag.end
                continue
            }
            if character == "{", let block = readOverrideBlock(raw, from: index) {
                for command in block.commands {
                    switch command {
                    case .italic(true): openItalic()
                    case .italic(false): closeItalic()
                    }
                }
                index = block.end
                continue
            }
            if character == "&", let entity = readEntity(raw, from: index) {
                for decoded in entity.text {
                    emit(decoded)
                }
                index = entity.end
                continue
            }
            emit(character)
            index = raw.index(after: index)
        }
        closeItalic()

        return Parsed(text: out, italicRanges: ranges)
    }

    // MARK: - Tokens

    private struct Tag {
        let name: String
        let isClosing: Bool
        let end: String.Index
    }

    private enum OverrideCommand: Equatable {
        case italic(Bool)
    }

    private struct OverrideBlock {
        let commands: [OverrideCommand]
        let end: String.Index
    }

    private struct Entity {
        let text: String
        let end: String.Index
    }

    /// Longest plausible tag body; guards against treating a stray `<` as markup.
    private static let maxTagLength = 256

    private static func readTag(_ raw: String, from start: String.Index) -> Tag? {
        var cursor = raw.index(after: start)
        var body = ""
        while cursor < raw.endIndex, body.count <= maxTagLength {
            let character = raw[cursor]
            if character == ">" {
                guard let name = tagName(in: body) else { return nil }
                return Tag(
                    name: name,
                    isClosing: body.hasPrefix("/"),
                    end: raw.index(after: cursor)
                )
            }
            if character == "<" || character == "\n" { return nil }
            body.append(character)
            cursor = raw.index(after: cursor)
        }
        return nil
    }

    /// Returns the lowercased element name, or `""` for tag-shaped bodies without a name
    /// (WebVTT karaoke timestamps such as `<00:00:04.500>`). `nil` means "not markup".
    private static func tagName(in body: String) -> String? {
        let content = body.hasPrefix("/") ? String(body.dropFirst()) : body
        guard let first = content.first else { return nil }
        if first.isLetter {
            return String(content.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
        }
        if first.isNumber, content.contains(":") { return "" }
        return nil
    }

    private static func readOverrideBlock(_ raw: String, from start: String.Index) -> OverrideBlock? {
        var cursor = raw.index(after: start)
        var body = ""
        while cursor < raw.endIndex, body.count <= maxTagLength {
            let character = raw[cursor]
            if character == "}" {
                guard body.hasPrefix("\\") else { return nil }
                return OverrideBlock(
                    commands: overrideCommands(in: body),
                    end: raw.index(after: cursor)
                )
            }
            if character == "{" || character == "\n" { return nil }
            body.append(character)
            cursor = raw.index(after: cursor)
        }
        return nil
    }

    private static func overrideCommands(in body: String) -> [OverrideCommand] {
        body.split(separator: "\\").compactMap { token in
            switch token.lowercased() {
            case "i1": return .italic(true)
            case "i0": return .italic(false)
            default: return nil
            }
        }
    }

    private static let namedEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": "\u{00A0}",
        "lrm": "\u{200E}",
        "rlm": "\u{200F}"
    ]

    private static func readEntity(_ raw: String, from start: String.Index) -> Entity? {
        var cursor = raw.index(after: start)
        var body = ""
        while cursor < raw.endIndex, body.count <= 12 {
            let character = raw[cursor]
            if character == ";" {
                guard let text = decodeEntity(body) else { return nil }
                return Entity(text: text, end: raw.index(after: cursor))
            }
            if !character.isLetter, !character.isNumber, character != "#" { return nil }
            body.append(character)
            cursor = raw.index(after: cursor)
        }
        return nil
    }

    private static func decodeEntity(_ body: String) -> String? {
        if let named = namedEntities[body.lowercased()] { return named }
        guard body.hasPrefix("#") else { return nil }
        let digits = String(body.dropFirst())
        let value: UInt32?
        if digits.lowercased().hasPrefix("x") {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits)
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }
}

private extension Character {
    var utf16Count: Int { String(self).utf16.count }
}
