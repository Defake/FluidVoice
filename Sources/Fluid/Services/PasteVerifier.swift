import AppKit
import ApplicationServices
import Foundation

/// Reads the focused element back after a paste to learn whether the text
/// landed. `notLanded` is returned only when the same element, its value,
/// its character count and its caret all stayed unchanged across two reads.
/// Every other situation is `unknown`, and the caller stays silent.
enum PasteVerifier {
    struct Snapshot {
        let element: AXUIElement
        let pid: pid_t
        let role: String
        let value: String?
        let characterCount: Int?
        let caret: CFRange?

        var summary: String {
            "role=\(self.role) valueLen=\(self.value.map { String($0.count) } ?? "nil") " +
                "chars=\(self.characterCount.map(String.init) ?? "nil") " +
                "caret=\(self.caret.map { "\($0.location)+\($0.length)" } ?? "nil")"
        }
    }

    enum Verdict: Equatable {
        case confirmed(method: String)
        case notLanded(reason: String)
        case unknown(reason: String)

        var logDescription: String {
            switch self {
            case let .confirmed(method): "confirmed method=\(method)"
            case let .notLanded(reason): "notLanded reason=\(reason)"
            case let .unknown(reason): "unknown reason=\(reason)"
            }
        }
    }

    /// Value reads are skipped above this size; count and caret still work.
    private static let maxReadableCharacters = 60_000

    nonisolated static func capture() -> Snapshot? {
        guard AXIsProcessTrusted() else { return nil }
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard result == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let role = self.string(element, kAXRoleAttribute as CFString) ?? "unknown"
        let count = self.number(element, kAXNumberOfCharactersAttribute as CFString)
        let value: String? = (count ?? 0) <= self.maxReadableCharacters
            ? self.string(element, kAXValueAttribute as CFString)
            : nil
        return Snapshot(
            element: element,
            pid: pid,
            role: role,
            value: value,
            characterCount: count,
            caret: self.range(element, kAXSelectedTextRangeAttribute as CFString)
        )
    }

    /// Call off the main thread after the paste command was posted.
    nonisolated static func verify(before: Snapshot, pastedText: String) async -> Verdict {
        let needle = self.normalize(pastedText)
        guard !needle.isEmpty else { return .unknown(reason: "empty_text") }
        guard before.value != nil || before.characterCount != nil || before.caret != nil else {
            return .unknown(reason: "before_unreadable")
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        guard let first = self.capture() else { return .unknown(reason: "after_unreadable") }
        guard CFEqual(first.element, before.element) else { return .unknown(reason: "focus_moved") }

        if let verdict = self.confirmation(before: before, after: first, needle: needle) { return verdict }

        // Nothing changed yet. Give slow apps a second chance before deciding.
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard let second = self.capture(), CFEqual(second.element, before.element) else {
            return .unknown(reason: "focus_moved_late")
        }
        if let verdict = self.confirmation(before: before, after: second, needle: needle) { return verdict }

        let valueKnown = before.value != nil && second.value != nil
        let countKnown = before.characterCount != nil && second.characterCount != nil
        let caretKnown = before.caret != nil && second.caret != nil
        guard valueKnown, countKnown, caretKnown else {
            return .unknown(reason: "signals_incomplete value=\(valueKnown) count=\(countKnown) caret=\(caretKnown)")
        }
        guard before.value == second.value,
              before.characterCount == second.characterCount,
              before.caret?.location == second.caret?.location,
              before.caret?.length == second.caret?.length
        else { return .unknown(reason: "changed_without_text") }
        return .notLanded(reason: "value_count_caret_unchanged")
    }

    private nonisolated static func confirmation(before: Snapshot, after: Snapshot, needle: String) -> Verdict? {
        if let afterValue = after.value {
            let beforeCount = before.value.map { self.occurrences(of: needle, in: self.normalize($0)) } ?? 0
            if self.occurrences(of: needle, in: self.normalize(afterValue)) > beforeCount {
                return .confirmed(method: "value")
            }
        }
        if let beforeCount = before.characterCount, let afterCount = after.characterCount,
           afterCount - beforeCount == needle.count || afterCount - beforeCount == needle.count + 1
        {
            return .confirmed(method: "count")
        }
        if let beforeCaret = before.caret, let afterCaret = after.caret,
           afterCaret.location - beforeCaret.location - beforeCaret.length == needle.count
        {
            return .confirmed(method: "caret")
        }
        return nil
    }

    private nonisolated static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }

    private nonisolated static func number(_ element: AXUIElement, _ attribute: CFString) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }

    private nonisolated static func range(_ element: AXUIElement, _ attribute: CFString) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success, let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(ref, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }
}

extension Notification.Name {
    /// Posted on the main queue with `userInfo["transcript"]` when a paste
    /// was verified to not land.
    static let fluidPasteNotLanded = Notification.Name("com.FluidApp.pasteNotLanded")
}
