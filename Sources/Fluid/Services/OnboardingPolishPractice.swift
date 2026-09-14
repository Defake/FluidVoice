import Foundation

/// Local practice progress; never writes dictation, provider, or persisted settings.
struct OnboardingPolishPractice {
    struct Example {
        let spoken: String
        let expected: String
    }

    static let examples = [
        Example(spoken: "Hey John, Newline, how are you doing today?", expected: "Hey John,\nHow are you doing today?"),
        Example(
            spoken: "Hey, can we meet at five thirty tomorrow morning? Sorry, can you make it three thirty p.m. today?",
            expected: "Hey, can we meet at 3:30 PM today?"
        ),
        Example(
            spoken: "Make a grocery list. First one is banana, second one is apple, third one is orange.",
            expected: "Grocery list:\n- banana\n- apple\n- orange"
        ),
    ]

    private(set) var index = 0
    private(set) var results: [Int: String] = [:]
    private var awaitingOutput = false
    var example: Example { Self.examples[self.index] }
    var result: String? { self.results[self.index] }
    var isLast: Bool { self.index == Self.examples.count - 1 }

    mutating func beginAttempt() {
        self.awaitingOutput = true
        self.results[self.index] = nil
    }

    mutating func receive(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.awaitingOutput, !text.isEmpty else { return }
        self.results[self.index] = text
        self.awaitingOutput = false
    }

    @discardableResult
    mutating func advance(isBusy: Bool) -> Bool {
        guard !isBusy, self.result != nil, !self.isLast else { return false }
        self.index += 1
        self.awaitingOutput = false
        return true
    }
}
