import AppKit
import ApplicationServices
import WritingCore

struct EditorSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let text: String
    let frame: CGRect
}

@MainActor
final class AccessibilityBridge {
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    func snapshot() -> EditorSnapshot? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let focus = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focus) == AXUIElementGetTypeID() else { return nil }
        let element = focus as! AXUIElement
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        guard [kAXTextAreaRole, kAXTextFieldRole, "AXComboBox"].contains(role),
              subrole != kAXSecureTextFieldSubrole,
              let text = attribute(element, kAXValueAttribute) as? String,
              !text.isEmpty, (text as NSString).length <= 20_000,
              let frame = rect(element), frame.width > 0, frame.height > 0 else { return nil }
        return EditorSnapshot(element: element, pid: app.processIdentifier, text: text, frame: frame)
    }
    func bounds(_ range: NSRange, in editor: EditorSnapshot) -> CGRect? {
        var range = CFRange(location: range.location, length: range.length)
        guard let input = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(editor.element, kAXBoundsForRangeParameterizedAttribute as CFString, input, &output) == .success,
              let output, CFGetTypeID(output) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(output as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        let clipped = rect.intersection(editor.frame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return cocoaRect(clipped)
    }
    func cocoaRect(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
    func apply(_ edit: TextEdit, to editor: EditorSnapshot) -> Bool {
        guard let current = snapshot(), current.pid == editor.pid, CFEqual(current.element, editor.element),
              edit.applying(to: current.text, snapshot: editor.text) != nil else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(editor.element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue else { return false }
        var range = CFRange(location: edit.range.location, length: edit.range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(editor.element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        return AXUIElementSetAttributeValue(editor.element, kAXSelectedTextAttribute as CFString, edit.replacement as CFString) == .success
    }
}
