import ApplicationServices
import Foundation

/// Decides, before pasting, whether the focused UI element can take text.
/// `notEditable` is only returned when the answer is certain; every ambiguous
/// case is `unknown` so delivery proceeds exactly as before.
enum DeliveryTargetAssessment: Equatable {
    case editable(role: String)
    case notEditable(role: String)
    case unknown(reason: String)

    var isCertainlyNotEditable: Bool {
        if case .notEditable = self { return true }
        return false
    }

    var logDescription: String {
        switch self {
        case let .editable(role): "editable role=\(role)"
        case let .notEditable(role): "notEditable role=\(role)"
        case let .unknown(reason): "unknown reason=\(reason)"
        }
    }

    /// Roles that never accept typed text. Containers such as AXGroup and
    /// AXWebArea are deliberately absent: web editors report those. Table
    /// roles are absent too: a selected spreadsheet cell reports AXCell or
    /// AXTable and does accept pasted text.
    private static let nonEditableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXMenu", "AXMenuBar", "AXMenuBarItem",
        "AXStaticText", "AXImage", "AXLink", "AXDisclosureTriangle",
        "AXScrollBar", "AXSlider", "AXIncrementor", "AXTabGroup", "AXToolbar",
        "AXSplitter", "AXWindow", "AXSheet", "AXDrawer", "AXApplication", "AXDockItem",
    ]

    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField",
    ]

    nonisolated static func assessFocusedElement() -> DeliveryTargetAssessment {
        guard AXIsProcessTrusted() else { return .unknown(reason: "accessibility_not_trusted") }
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard result == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return .unknown(reason: "focused_element_\(result.rawValue)")
        }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else { return .unknown(reason: "role_unreadable") }

        if self.editableRoles.contains(role) { return .editable(role: role) }

        var valueSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        if settableResult == .success, valueSettable.boolValue { return .editable(role: role) }

        guard self.nonEditableRoles.contains(role) else { return .unknown(reason: "role_\(role)") }
        return .notEditable(role: role)
    }
}
