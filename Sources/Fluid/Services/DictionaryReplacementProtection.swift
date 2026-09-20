import Foundation

/// Prevents a rule from expanding a completed occurrence of its own replacement.
/// Only rules whose output contains a partial trigger need this extra scan.
nonisolated enum DictionaryReplacementProtection {
    static func replacingMatches(
        in text: String,
        regex: NSRegularExpression,
        template: String,
        canonical: NSRegularExpression?
    ) -> String {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let canonical else {
            return regex.stringByReplacingMatches(in: text, range: fullRange, withTemplate: template)
        }
        let completed = canonical.matches(in: text, range: fullRange).map(\.range)
        guard !completed.isEmpty else {
            return regex.stringByReplacingMatches(in: text, range: fullRange, withTemplate: template)
        }

        var completedIndex = 0
        let matches = regex.matches(in: text, range: fullRange).filter { match in
            while completedIndex < completed.count, NSMaxRange(completed[completedIndex]) <= match.range.location {
                completedIndex += 1
            }
            guard completedIndex < completed.count else { return true }
            let range = completed[completedIndex]
            let isPartialTriggerInsideCompletedOutput = range.location <= match.range.location &&
                NSMaxRange(match.range) <= NSMaxRange(range) && match.range.length < range.length
            return !isPartialTriggerInsideCompletedOutput
        }
        guard !matches.isEmpty else { return text }
        let output = NSMutableString(string: text)
        for match in matches.reversed() {
            output.replaceCharacters(
                in: match.range,
                with: regex.replacementString(for: match, in: text, offset: 0, template: template)
            )
        }
        return output as String
    }
}
