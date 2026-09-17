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
    private func parameter(_ element: AXUIElement, _ name: String, _ input: CFTypeRef) -> CFTypeRef? {
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, input, &output) == .success else { return nil }
        return output
    }

    func practiceSnapshot() -> EditorSnapshot? {
        guard let view = practiceEditor, let window = view.window, !view.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
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
    func diagnosticSummary(app target: NSRunningApplication? = nil) -> String {
        var lines = ["Accessibility permission: \(AXIsProcessTrusted())"]
        guard let app = target ?? NSWorkspace.shared.frontmostApplication else { return lines.joined(separator: "\n") }
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
            for name in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXValueAttribute] {
                var settable = DarwinBoolean(false)
                let status = AXUIElementIsAttributeSettable(element, name as CFString, &settable)
                lines.append("\(name) writable: \(status == .success && settable.boolValue)")
            }
            var names: CFArray?
            AXUIElementCopyParameterizedAttributeNames(element, &names)
            lines.append("Range APIs: \(names as? [String] ?? [])")
        }
        return lines.joined(separator: "\n")
    }
    func snapshot(app target: NSRunningApplication? = nil) -> EditorSnapshot? {
        if target == nil, NSApp.isActive, let view = practiceEditor, view.window?.isKeyWindow == true {
            failure = view.string.isEmpty ? "Type in the practice editor" : ""
            return practiceSnapshot()
        }
        guard AXIsProcessTrusted() else { failure = "Accessibility access needed for other apps"; return nil }
        guard let app = target ?? NSWorkspace.shared.frontmostApplication,
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
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { failure = "Type a sentence to begin"; return nil }
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
        let container = focus as! AXUIElement
        let containerRole = attribute(container, kAXRoleAttribute) as? String ?? ""
        if ["AXWebArea", "AXGroup"].contains(containerRole),
           let editor = EditorSearch.resolve(root: container,
               children: { self.attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] },
               isEditor: { [kAXTextAreaRole, kAXTextFieldRole, "AXComboBox"].contains(self.attribute($0, kAXRoleAttribute) as? String ?? "") || (self.attribute($0, "AXEditable") as? Bool ?? false) },
               isTextArea: { self.attribute($0, kAXRoleAttribute) as? String == kAXTextAreaRole },
               isFocused: { self.attribute($0, kAXFocusedAttribute) as? Bool ?? false },
               isSecure: { self.attribute($0, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole }),
           let text = attribute(editor, kAXValueAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 4000,
           let frame = rect(editor), !frame.isEmpty {
            failure = ""
            return EditorSnapshot(element: editor, pid: app.processIdentifier, text: text, frame: frame)
        }
        failure = "Focused control is not an editable text field"
        return nil
    }
    private func descendantBounds(_ range: NSRange, in editor: EditorSnapshot) -> CGRect? {
        var queue = Array((attribute(editor.element, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed())
        var leaves: [(AXUIElement, String)] = []
        var index = 0
        while !queue.isEmpty && index < 256 {
            let element = queue.removeLast(); index += 1
            if attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return nil }
            if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole,
               let text = attribute(element, kAXValueAttribute) as? String {
                leaves.append((element, text))
            } else { queue.append(contentsOf: (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed()) }
        }
        guard queue.isEmpty, let ranges = TextLeafRanges.align(leaves.map({ $0.1 }), in: editor.text) else { return nil }
        var result = CGRect.null
        for ((element, _), leafRange) in zip(leaves, ranges) {
            let intersection = NSIntersectionRange(range, leafRange)
            guard intersection.length > 0 else { continue }
            var local = CFRange(location: intersection.location - leafRange.location, length: intersection.length)
            guard let input = AXValueCreate(.cfRange, &local),
                  let output = parameter(element, kAXBoundsForRangeParameterizedAttribute, input),
                  CFGetTypeID(output) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(output as! AXValue, .cgRect, &rect), !rect.isEmpty else { return nil }
            result = result.union(rect)
        }
        return result.isNull ? nil : result
    }
    func rangeDiagnostic(_ range: NSRange, editor: EditorSnapshot) -> String {
        var cfRange = CFRange(location: range.location, length: range.length)
        let input = AXValueCreate(.cfRange, &cfRange)!
        var output: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(editor.element, kAXBoundsForRangeParameterizedAttribute as CFString, input, &output)
        var rect = CGRect.zero
        if let output, CFGetTypeID(output) == AXValueGetTypeID() { AXValueGetValue(output as! AXValue, .cgRect, &rect) }
        return "Range status: \(error.rawValue), raw rect: \(rect)"
    }
    func selectedRange(in editor: EditorSnapshot) -> NSRange? {
        let range: NSRange
        if let view = editor.nativeView { range = view.selectedRange() }
        else {
            guard let value = attribute(editor.element, kAXSelectedTextRangeAttribute),
                  CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .cfRange else { return nil }
            var selected = CFRange()
            guard AXValueGetValue(value as! AXValue, .cfRange, &selected), selected.location >= 0, selected.length > 0 else { return nil }
            range = NSRange(location: selected.location, length: selected.length)
        }
        let count = editor.text.utf16.count
        guard range.location != NSNotFound, range.location <= count, range.length > 0,
              range.length <= count - range.location,
              !(editor.text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return range
    }
    func bounds(_ range: NSRange, in editor: EditorSnapshot) -> CGRect? {
        if let view = editor.nativeView {
            let rect = view.firstRect(forCharacterRange: range, actualRange: nil).intersection(editor.frame)
            return rect.isNull || rect.isEmpty ? nil : rect
        }
        var cfRange = CFRange(location: range.location, length: range.length)
        var rect = CGRect.zero
        if let input = AXValueCreate(.cfRange, &cfRange),
           let output = parameter(editor.element, kAXBoundsForRangeParameterizedAttribute, input),
           CFGetTypeID(output) == AXValueGetTypeID() {
            AXValueGetValue(output as! AXValue, .cgRect, &rect)
        }
        if rect.isEmpty { rect = descendantBounds(range, in: editor) ?? .zero }
        guard rect.width > 0, rect.height > 0, rect != editor.frame else { return nil }
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
        return false
    }

    func applyVerified(_ edit: TextEdit, to editor: EditorSnapshot) async -> Bool {
        if editor.nativeView != nil { return apply(edit, to: editor) }
        guard let current = snapshot(), current.sameEditor(as: editor),
              let expected = edit.applying(to: current.text, snapshot: editor.text) else {
            failure = "The draft or focused editor changed. Hover the new suggestion and try again."; return false
        }
        var settable = DarwinBoolean(false)
        let directReplacement = AXUIElementIsAttributeSettable(editor.element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
        var range = CFRange(location: edit.range.location, length: edit.range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(editor.element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            failure = "This editor could not select the correction range."; return false
        }
        var selected = false
        for _ in 0..<20 {
            guard let fresh = snapshot(), fresh.sameEditor(as: editor), fresh.text == editor.text else {
                failure = "The draft or focus changed before replacement."; return false
            }
            if let value = attribute(editor.element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                var actual = CFRange()
                if AXValueGetValue(value as! AXValue, .cfRange, &actual), actual.location == range.location, actual.length == range.length,
                   attribute(editor.element, kAXSelectedTextAttribute) as? String == edit.original {
                    selected = true; break
                }
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        guard selected else { failure = "The editor did not select the requested words. Nothing was replaced."; return false }
        let status = directReplacement ? AXUIElementSetAttributeValue(editor.element, kAXSelectedTextAttribute as CFString, edit.replacement as CFString) : .attributeUnsupported
        for _ in 0..<(status == .success ? 30 : 0) {
            let actual = attribute(editor.element, kAXValueAttribute) as? String
            if actual == expected { failure = "Correction applied"; return true }
            if let actual, actual != editor.text { failure = "The draft changed unexpectedly. Check it before trying again."; return false }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        // Rich editors may acknowledge AXSelectedText without implementing the edit.
        // Paste only into the same, unchanged, explicitly verified selection.
        return await pasteReplacement(edit, editor: editor, expected: expected)
    }

    private func selectionMatches(_ edit: TextEdit, editor: EditorSnapshot) -> Bool {
        guard let current = snapshot(), current.sameEditor(as: editor), current.text == editor.text,
              let value = attribute(editor.element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID(),
              attribute(editor.element, kAXSelectedTextAttribute) as? String == edit.original else { return false }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) && range.location == edit.range.location && range.length == edit.range.length
    }

    private func pasteReplacement(_ edit: TextEdit, editor: EditorSnapshot, expected: String) async -> Bool {
        guard !Task.isCancelled, selectionMatches(edit, editor: editor) else {
            failure = "The draft, selection, or focus changed. Nothing was pasted."; return false
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false),
              let clipboard = PasteboardLease(text: edit.replacement) else {
            failure = "Could not prepare replacement while preserving the clipboard."; return false
        }
        defer { clipboard.restore() }
        guard selectionMatches(edit, editor: editor) else {
            failure = "The draft, selection, or focus changed. Nothing was pasted."; return false
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(editor.pid); up.postToPid(editor.pid)
        for _ in 0..<50 {
            let actual = attribute(editor.element, kAXValueAttribute) as? String
            if actual == expected { failure = "Correction applied"; return true }
            if let actual, actual != editor.text {
                failure = "The draft changed unexpectedly. Check it before trying again."; return false
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        failure = "The editor did not apply the paste. Your previous clipboard has been restored."
        return false
    }
}
