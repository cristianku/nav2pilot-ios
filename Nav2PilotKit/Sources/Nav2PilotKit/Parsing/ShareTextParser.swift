import Foundation

/// What another app shared with us (text, URL and title from the share sheet), split into a link and
/// the surrounding text lines.
///
/// Google Maps typically shares the place name and address as text lines followed by a
/// maps.app.goo.gl link; this is observed behaviour, not a documented format, so every part is optional.
public struct SharedText: Equatable {
    public let link: String
    public let title: String
    public let details: String
    public let textWithoutLink: String
}

public enum ShareTextParser {
    private static let linkPattern = Pattern(#"(?:https?://|geo:|google\.navigation:)[^\s<>"]+"#, caseInsensitive: true)

    public static func parse(_ text: String, subject: String) -> SharedText {
        var link = ""
        var remaining = text
        if let match = linkPattern.firstMatch(text) {
            link = trimTrailingPunctuation(match.value)
            remaining = text.replacingCharacters(in: match.range, with: "")
        }

        var lines: [String] = []
        for line in TextLines.split(remaining) {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                lines.append(cleaned)
            }
        }

        var title = ""
        var details = ""
        if !lines.isEmpty {
            title = lines[0]
            details = lines.dropFirst().joined(separator: ", ")
        } else {
            title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return SharedText(
            link: link,
            title: title,
            details: details,
            textWithoutLink: lines.joined(separator: ", ")
        )
    }

    private static func trimTrailingPunctuation(_ link: String) -> String {
        var result = link
        while let last = result.last {
            if last == "." || last == "," || last == ";" {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }
}

enum TextLines {
    /// Splits on \n, \r\n and \r, like Kotlin's lines().
    static func split(_ text: String) -> [String] {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return unified.components(separatedBy: "\n")
    }
}
