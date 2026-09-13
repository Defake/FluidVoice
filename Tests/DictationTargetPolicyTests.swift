import Foundation

@main
enum DictationTargetPolicyTests {
    static func main() {
        let cases: [(String, Bool, Int32?, Int32?, Bool, Int32?, Bool)] = [
            ("off follows app B", false, 200, 100, false, 200, false),
            ("on restores app A", true, 200, 100, false, 100, true),
            ("off follows another field in A", false, 100, 100, false, 100, false),
            ("on restores original field in A", true, 100, 100, false, 100, true),
            ("already focused needs no restore", true, 100, 100, true, 100, false),
            ("off works without recording context", false, 200, nil, false, 200, false),
            ("overlay recovers saved target", false, 999, 100, false, 100, true),
            ("unknown focus recovers saved target", false, nil, 100, false, 100, true),
            ("invalid focus is not a destination", false, 0, 100, false, 100, true),
            ("missing target does not invent a PID", true, nil, nil, false, nil, true),
        ]
        for (name, enabled, focused, original, stillFocused, expectedPID, restores) in cases {
            let result = DictationTargetPolicy.resolve(
                returnToStartingField: enabled, focusedPID: focused, ownPID: 999,
                originalPID: original, originalFieldIsFocused: stillFocused
            )
            precondition(result.pid == expectedPID && result.shouldRestoreOriginalFocus == restores, name)
        }
        print("PASS: \(cases.count) dictation destination cases, including app switches, field switches, overlays and missing focus")
    }
}
