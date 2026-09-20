import Foundation

/// Original corrections provide both text and acoustic evidence for the same intended spelling.
/// These conservative thresholds are evaluated separately from the legacy three-recording preview.
enum DictionaryPronunciationDecision {
    static func accepts(score: Float, heardText: String, profile: PronunciationDictionaryProfile) -> Bool {
        guard score.isFinite else { return false }
        let heard = self.normalized(heardText)
        let knownVariant = profile.enrollments.contains {
            $0.observedText.map(self.normalized) == heard
        }
        return score >= (knownVariant ? 0.70 : 0.85)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
