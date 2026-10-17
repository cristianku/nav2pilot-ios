import Foundation

struct PatternMatch {
    /// The whole matched text.
    let value: String
    /// Capture groups, "" for a group that did not take part in the match.
    let groups: [String]
    let range: Range<String.Index>
}

/// Thin wrapper around NSRegularExpression that works with Swift strings.
struct Pattern {
    private let expression: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        var options: NSRegularExpression.Options = []
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }
        // The patterns are constants in this module; an invalid one is a programming error.
        expression = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// The match only when it covers the whole text.
    func matchEntire(_ text: String) -> PatternMatch? {
        guard let match = firstMatch(text) else {
            return nil
        }
        if match.range != text.startIndex..<text.endIndex {
            return nil
        }
        return match
    }

    func matches(_ text: String) -> Bool {
        return matchEntire(text) != nil
    }

    func firstMatch(_ text: String) -> PatternMatch? {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = expression.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }
        return convert(result, in: text)
    }

    func allMatches(_ text: String) -> [PatternMatch] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var matches: [PatternMatch] = []
        for result in expression.matches(in: text, options: [], range: fullRange) {
            if let match = convert(result, in: text) {
                matches.append(match)
            }
        }
        return matches
    }

    private func convert(_ result: NSTextCheckingResult, in text: String) -> PatternMatch? {
        guard let range = Range(result.range, in: text) else {
            return nil
        }
        var groups: [String] = []
        if result.numberOfRanges > 1 {
            for index in 1..<result.numberOfRanges {
                let groupRange = result.range(at: index)
                if groupRange.location == NSNotFound {
                    groups.append("")
                    continue
                }
                if let swiftRange = Range(groupRange, in: text) {
                    groups.append(String(text[swiftRange]))
                } else {
                    groups.append("")
                }
            }
        }
        return PatternMatch(value: String(text[range]), groups: groups, range: range)
    }
}
