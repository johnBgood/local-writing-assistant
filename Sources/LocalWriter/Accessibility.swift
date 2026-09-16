import AppKit
import ApplicationServices
import WritingCore

struct EditorSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let text: String
    let frame: CGRect
    var nativeView: NSTextView? = nil
    func sameEditor(as other: EditorSnapshot) -> Bool {
        if let nativeView { return nativeView === other.nativeView }
        return other.nativeView == nil && pid == other.pid && CFEqual(element, other.element)
    }
}

@MainActor
final class AccessibilityBridge {
    weak var practiceEditor: NSTextView?
    private(set) var failure = "Focus an editor to begin"
    private var prepared: Set<pid_t> = []

    func practiceSnapshot() -> EditorSnapshot? {
        guard let view = practiceEditor, let window = view.window, !view.string.isEmpty else { return nil }
        return EditorSnapshot(element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),
                              pid: ProcessInfo.processInfo.processIdentifier, text: view.string,
                              frame: window.convertToScreen(view.convert(view.visibleRect, to: nil)), nativeView: view)
    }

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
    func diagnosticSummary() -> String {
        var lines = ["Accessibility permission: \(AXIsProcessTrusted())"]
        guard let app = NSWorkspace.shared.frontmostApplication else { return lines.joined(separator: "\n") }
        lines.append("App: \(app.localizedName ?? "Unknown")")
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
        lines.append("Focused element result: \(result.rawValue)")
        if let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            let element = value as! AXUIElement
            lines.append("Role: \(attribute(element, kAXRoleAttribute) as? String ?? "missing")")
            lines.append("Subrole: \(attribute(element, kAXSubroleAttribute) as? String ?? "missing")")
            lines.append("Text length: \((attribute(element, kAXValueAttribute) as? String)?.utf16.count ?? -1)")
            var names: CFArray?
            AXUIElementCopyParameterizedAttributeNames(element, &names)
            lines.append("Range APIs: \(names as? [String] ?? [])")
        }
        return lines.joined(separator: "\n")
    }
    func snapshot() -> EditorSnapshot? {
        if NSApp.isActive, let view = practiceEditor, view.window?.isKeyWindow == true {
            failure = view.string.isEmpty ? "Type in the practice editor" : ""
            return practiceSnapshot()
        }
        guard AXIsProcessTrusted() else { failure = "Accessibility access needed for other apps"; return nil }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            failure = "Focus a text editor to begin"; return nil
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        // Chromium/Electron exposes its full editor tree only after an assistive client requests it.
        if !prepared.contains(app.processIdentifier) {
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            prepared.insert(app.processIdentifier)
        }
        guard let focus = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focus) == AXUIElementGetTypeID() else {
            failure = "\(app.localizedName ?? "App") is not exposing a focused editor"; return nil
        }
        var candidate: AXUIElement? = (focus as! AXUIElement)
        for _ in 0..<5 {
            guard let element = candidate else { break }
            let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
            if subrole == kAXSecureTextFieldSubrole { failure = "Password fields are excluded"; return nil }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let editable = attribute(element, "AXEditable") as? Bool ?? false
            if [kAXTextAreaRole, kAXTextFieldRole, "AXComboBox"].contains(role) || editable {
                guard let text = attribute(element, kAXValueAttribute) as? String else {
                    failure = "Editor does not expose readable text"; return nil
                }
                guard !text.isEmpty else { failure = "Type a sentence to begin"; return nil }
                guard text.utf16.count <= 4000 else { failure = "Draft too long · limit is 4,000 characters"; return nil }
                guard let frame = rect(element), frame.width > 0, frame.height > 0 else {
                    failure = "Editor does not expose its position"; return nil
                }
                failure = ""
                return EditorSnapshot(element: element, pid: app.processIdentifier, text: text, frame: frame)
            }
            if let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() { candidate = (parent as! AXUIElement) }
            else { candidate = nil }
        }
        failure = "Focused control is not an editable text field"
        return nil
    }
    func bounds(_ range: NSRange, in editor: EditorSnapshot) -> CGRect? {
        if let view = editor.nativeView {
            let rect = view.firstRect(forCharacterRange: range, actualRange: nil).intersection(editor.frame)
            return rect.isNull || rect.isEmpty ? nil : rect
        }
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
        if let view = editor.nativeView {
            guard edit.applying(to: view.string, snapshot: editor.text) != nil,
                  view.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return false }
            view.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            view.didChangeText()
            return true
        }
        guard let current = snapshot(), current.sameEditor(as: editor),
              edit.applying(to: current.text, snapshot: editor.text) != nil else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(editor.element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue else { return false }
        var range = CFRange(location: edit.range.location, length: edit.range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(editor.element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        return AXUIElementSetAttributeValue(editor.element, kAXSelectedTextAttribute as CFString, edit.replacement as CFString) == .success
    }
}
