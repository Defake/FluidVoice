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

    /// A new spoken possessive is still the enrolled name. Preserve its grammatical ending,
    /// unless a recorded correction explicitly taught a possessive-to-nonpossessive replacement.
    static func labelPreservingPossessive(
        _ label: String, heardText: String, profile: PronunciationDictionaryProfile
    ) -> String {
        guard profile.hasOriginalAudio,
              let last = label.last, last.isLetter || last.isNumber,
              let suffix = self.possessiveSuffix(heardText),
              self.possessiveSuffix(label) == nil,
              !profile.enrollments.contains(where: {
                  $0.observedText.map { self.possessiveSuffix($0) != nil } ?? false
              })
        else { return label }
        return label + suffix
    }

    private static func possessiveSuffix(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.lowercased().hasSuffix("'s") || trimmed.lowercased().hasSuffix("’s") else { return nil }
        return String(trimmed.suffix(2))
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
