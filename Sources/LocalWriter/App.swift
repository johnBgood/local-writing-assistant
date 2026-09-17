import AppKit
import ApplicationServices
import WritingCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var preferences = WritingPreferences()
    private var preferencesChecked = Date.distantPast
    private let languageMenu = NSMenu(title: "Language")
    private let dictionaryMenu = NSMenu(title: "Personal dictionary")
    private var item: NSStatusItem!
    private let bridge = AccessibilityBridge()
    private let overlay = Overlay()
    private var timer: Timer?
    private var snapshot: EditorSnapshot?
    private var marks: [Mark] = []
    private var paused = false
    private var applying = false
    private var pendingText = ""
    private var changedAt = Date()
    private var hovered: Mark?
    private var hoverBegan = Date()
    private var displayed: Mark?
    private var selectedRange: NSRange?
    private var selectionBegan = Date()
    private var selectionRequested = false
    private var rewriteResult: String?
    private let runtime = LocalRuntime()
    private var analysisTask: Task<Void, Never>?
    private var currentEdits: [TextEdit] = []
    private var analyzedText: String?
    private var demoStatus: NSTextField?
    private var rewriteTask: Task<Void, Never>?
    private var demoWindow: NSWindow?
    private var lastGeometryUpdate = Date.distantPast
    private var availability = AppAvailability(excluded: Set(UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []))
    private var lastExternalApp: AppAvailability.Target?
    private var appToggle: NSMenuItem!
    private var pauseToggle: NSMenuItem!
    private let appStatus = NSMenuItem(title: "No app selected", action: nil, keyEquivalent: "")
    private let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")

    private var feedback: String {
        get { status.title }
        set { status.title = newValue; demoStatus?.stringValue = newValue }
    }
    func applicationWillTerminate(_ notification: Notification) { runtime.stop() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "✎"
        let menu = NSMenu(); menu.delegate = self; menu.addItem(status); menu.addItem(appStatus)
        menu.addItem(.separator())
        add("Grant Accessibility Access…", #selector(permission), to: menu)
        pauseToggle = add("Pause LocalWriter", #selector(toggle), to: menu)
        appToggle = add(availability.actionTitle, #selector(exclude), to: menu)
        add("Editor Diagnostics…", #selector(diagnostics), to: menu)
        add("Open Practice Editor", #selector(demo), to: menu)
        add("Start Local Model", #selector(startModel), to: menu)
        add("Check Again", #selector(checkAgain), to: menu)
        add("Model Setup Instructions", #selector(modelHelp), to: menu)
        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: ""); languageItem.submenu = languageMenu; menu.addItem(languageItem)
        let dictionaryItem = NSMenuItem(title: "Personal dictionary", action: nil, keyEquivalent: ""); dictionaryItem.submenu = dictionaryMenu; menu.addItem(dictionaryItem)
        menu.addItem(.separator()); add("Quit LocalWriter", #selector(quit), to: menu)
        item.menu = menu
        overlay.action = { [weak self] replacement in self?.apply(replacement) }
        overlay.dictionaryAction = { [weak self] word in
            do { try PreferenceStore.add(word); self?.clear(); self?.feedback = "Added “\(word)” to dictionary" }
            catch { self?.feedback = error.localizedDescription }
        }
        overlay.rewriteAction = { [weak self] in self?.rewrite() }
        overlay.dismissAction = { [weak self] in self?.rewriteTask?.cancel(); self?.displayed = nil; self?.hoverBegan = Date() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        try? runtime.start()
        feedback = AXIsProcessTrusted() ? "Ready · Qwen3 · Local" : "Accessibility needed for other apps · Practice editor works"
        if CommandLine.arguments.contains("--practice") || CommandLine.arguments.contains("--practice-check") || CommandLine.arguments.contains("--selection-check") { demo() }
        if CommandLine.arguments.contains("--practice-check") { runPracticeCheck() }
        if CommandLine.arguments.contains("--selection-check") { runSelectionCheck() }
    }
    private func runSelectionCheck() {
        Task { @MainActor in
            guard let view = bridge.practiceEditor else { exit(1) }
            view.string = "She go to work yesterday."
            let fullRange = NSRange(location: 0, length: view.string.utf16.count)
            view.setSelectedRange(fullRange)
            for _ in 0..<300 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if let result = rewriteResult, displayed?.range == fullRange {
                    guard result != view.string, overlay.popover.isVisible else { exit(1) }
                    apply(result)
                    for _ in 0..<100 where applying { try? await Task.sleep(nanoseconds: 30_000_000) }
                    guard view.string == result else { print("FAIL: selected phrase was not replaced"); exit(1) }
                    view.setSelectedRange(NSRange(location: 0, length: 0))
                    guard bridge.practiceSnapshot().flatMap({ bridge.selectedRange(in: $0) }) == nil else { exit(1) }
                    print("PASS: native selection → automatic local rewrite → full-range replacement; invalid selection rejected")
                    NSApp.terminate(nil); return
                }
            }
            print("FAIL: selection rewrite timed out: \(feedback)"); exit(1)
        }
    }
    private func runPracticeCheck() {
        Task { @MainActor in
            for _ in 0..<150 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let mark = marks.first(where: { !$0.sentence && $0.word == "speling" }),
                   overlay.window.isVisible, let editor = snapshot {
                    let localMark = overlay.view.marks.first(where: { $0.word == "speling" })!
                    let area = localMark.rect.insetBy(dx: -4, dy: -4)
                    guard let bitmap = overlay.view.bitmapImageRepForCachingDisplay(in: area) else { exit(1) }
                    overlay.view.cacheDisplay(in: area, to: bitmap)
                    var redPixels = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                               color.alphaComponent > 0.1, color.redComponent > 0.6, color.greenComponent < 0.5 { redPixels += 1 }
                        }
                    }
                    guard redPixels > 0, marks.contains(where: { !$0.sentence && $0.suggestions.contains("went") }) else {
                        print("FAIL: missing rendered underline or grammar correction"); exit(1)
                    }
                    displayed = mark
                    apply("spelling")
                    for _ in 0..<100 where applying { try? await Task.sleep(nanoseconds: 30_000_000) }
                    guard bridge.practiceEditor?.string.contains("spelling") == true,
                          !bridge.apply(TextEdit(range: mark.range, original: mark.word, replacement: "spelling"), to: editor) else {
                        print("FAIL: practice acceptance"); exit(1)
                    }
                    print("PASS: running practice app debounce → local model → \(redPixels) red underline pixels → accept correction")
                    NSApp.terminate(nil); return
                }
            }
            print("FAIL: practice loop timed out: \(feedback), active=\(NSApp.isActive)")
            exit(1)
        }
    }
    @discardableResult func add(_ title: String, _ selector: Selector, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: ""); entry.target = self; menu.addItem(entry); return entry
    }
    @objc func permission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private func rememberExternalApp() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let id = app.bundleIdentifier {
            lastExternalApp = .init(id: id, name: id == "com.openai.codex" ? "Codex" : (app.localizedName ?? id))
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        preferences = (try? PreferenceStore.read()) ?? preferences
        languageMenu.removeAllItems(); dictionaryMenu.removeAllItems()
        for (code, title) in [("auto", "Automatic · EN / FR / DE"), ("en", "English"), ("fr", "Français"), ("de", "Deutsch")] {
            let entry = add(title, #selector(setLanguage(_:)), to: languageMenu)
            entry.representedObject = code; entry.state = preferences.language == code ? .on : .off
        }
        add("Add a word…", #selector(addDictionaryWord), to: dictionaryMenu)
        for word in preferences.words {
            let entry = add("Remove “\(word)”", #selector(removeDictionaryWord(_:)), to: dictionaryMenu); entry.representedObject = word
        }

        rememberExternalApp()
        availability.capture(lastExternalApp)
        updateMenuState()
    }
    private func updateMenuState() {
        appToggle.title = availability.actionTitle
        appToggle.isEnabled = availability.target != nil
        appStatus.title = availability.statusTitle
        pauseToggle.title = paused ? "Resume LocalWriter" : "Pause LocalWriter"
        item.button?.toolTip = paused ? "LocalWriter paused" : availability.statusTitle
    }
    @objc func toggle() {
        paused.toggle(); clear(); item.button?.title = paused ? "✎Ⅱ" : "✎"
        feedback = paused ? "Paused" : "Ready · English · Local"
        updateMenuState()
    }
    @objc func exclude() {
        availability.toggle()
        UserDefaults.standard.set(Array(availability.excluded).sorted(), forKey: "excludedApps")
        clear(); feedback = availability.statusTitle
        updateMenuState()
    }
    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        do { try PreferenceStore.update { $0.language = code }; clear() } catch { feedback = error.localizedDescription }
    }
    @objc func addDictionaryWord() {
        let alert = NSAlert(); alert.messageText = "Add a word to your personal dictionary"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); alert.accessoryView = input
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try PreferenceStore.add(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)); clear() }
        catch { feedback = error.localizedDescription }
    }
    @objc func removeDictionaryWord(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        do { try PreferenceStore.update { $0.words.removeAll { $0 == word } }; clear() }
        catch { feedback = error.localizedDescription }
    }
    @objc func diagnostics() {
        let report = bridge.diagnosticSummary()
        let alert = NSAlert(); alert.messageText = "Editor diagnostics"
        alert.informativeText = report + "\n\nNo editor text is included."
        alert.runModal()
    }
    @objc func startModel() {
        do { try runtime.start(); clear(); feedback = "Starting local model…" }
        catch { feedback = error.localizedDescription }
    }
    @objc func checkAgain() { clear(); feedback = "Ready to check again" }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func modelHelp() {
        let alert = NSAlert(); alert.messageText = "Local sentence rewrites"
        alert.informativeText = "Install Ollama from ollama.com, then run:\n\nollama pull qwen3:4b\n\nKeep Ollama running. LocalWriter connects only to 127.0.0.1:11434. Spelling, grammar, and rewrites all use the local model. The repository includes scripts/setup-model.sh."
        alert.runModal()
    }
    @objc func demo() {
        if demoWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 720, height: 350), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "LocalWriter — Model Practice Editor"
            window.isReleasedWhenClosed = false
            let content = window.contentView!
            let label = NSTextField(labelWithString: "Checking with Qwen3 on your Mac…")
            label.frame = NSRect(x: 16, y: 10, width: 688, height: 26)
            label.autoresizingMask = [.width, .maxYMargin]
            content.addSubview(label); demoStatus = label
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 46, width: 720, height: 304))
            scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isRichText = false; text.font = .systemFont(ofSize: 20)
            text.textContainerInset = NSSize(width: 20, height: 20)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            text.isContinuousSpellCheckingEnabled = false; text.isGrammarCheckingEnabled = false
            text.isAutomaticSpellingCorrectionEnabled = false
            text.string = "This is a speling mistake. She go to work yesterday."
            scroll.documentView = text; content.addSubview(scroll)
            bridge.practiceEditor = text; demoWindow = window
            window.makeFirstResponder(text)
        }
        clear(); NSApp.activate(ignoringOtherApps: true); demoWindow?.makeKeyAndOrderFront(nil)
    }
    func clear() {
        analysisTask?.cancel(); analysisTask = nil; analyzedText = nil; currentEdits = []
        rewriteTask?.cancel(); rewriteTask = nil
        selectedRange = nil; selectionRequested = false; rewriteResult = nil
        snapshot = nil; marks = []; hovered = nil; displayed = nil; pendingText = ""; overlay.hide()
    }
    func tick() {
        guard !applying else { return }
        if Date().timeIntervalSince(preferencesChecked) > 1 {
            preferencesChecked = Date()
            if let latest = try? PreferenceStore.read(), latest != preferences { preferences = latest; clear() }
        }
        rememberExternalApp()
        guard !paused else { feedback = "Paused"; return }
        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !(UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []).contains(appID) else { clear(); feedback = "Disabled for \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "this app")"; return }
        guard let current = bridge.snapshot() else { clear(); feedback = bridge.failure; return }
        if let old = snapshot, !old.sameEditor(as: current) { clear() }
        if current.text != pendingText {
            clear(); pendingText = current.text; changedAt = Date(); snapshot = current
            feedback = "Waiting for typing pause…"; return
        }
        snapshot = current
        let selection = bridge.selectedRange(in: current)
        if selection != selectedRange {
            rewriteTask?.cancel(); rewriteResult = nil
            selectedRange = selection; selectionBegan = Date(); selectionRequested = false
            displayed = nil; overlay.popover.orderOut(nil)
        }
        if let selection {
            // Wait for mouse/keyboard selection to settle, independent of pointer hover.
            guard NSEvent.pressedMouseButtons == 0, Date().timeIntervalSince(selectionBegan) > 0.3 else { return }
            if !selectionRequested {
                selectionRequested = true
                let wordRanges = HighlightRanges.words(in: selection, text: current.text)
                guard let anchor = wordRanges.compactMap({ bridge.bounds($0, in: current) }).first else {
                    feedback = "Selected text has no accessible position"; return
                }
                displayed = Mark(range: selection, rect: anchor,
                    word: (current.text as NSString).substring(with: selection), suggestions: [], sentence: true)
                rewrite()
            }
            return
        }
        guard Date().timeIntervalSince(changedAt) > 0.65 else { return }
        if analyzedText != current.text && analysisTask == nil {
            analyze(current)
        } else if Date().timeIntervalSince(lastGeometryUpdate) > 0.5 {
            let updated = makeMarks(for: current)
            if updated.map(\.rect) != marks.map(\.rect) { overlay.popover.orderOut(nil); displayed = nil }
            marks = updated; overlay.draw(marks); lastGeometryUpdate = Date()
        }
        snapshot = current
        let mouse = NSEvent.mouseLocation
        if overlay.popover.isVisible && overlay.popover.frame.insetBy(dx: -12, dy: -12).contains(mouse) { return }
        let mark = marks.first { !$0.sentence && $0.rect.insetBy(dx: -3, dy: -4).contains(mouse) }
            ?? marks.first { $0.sentence && $0.rect.contains(mouse) }
        if mark?.range != hovered?.range || mark?.sentence != hovered?.sentence {
            hovered = mark; hoverBegan = Date()
        }
        guard let mark else {
            if Date().timeIntervalSince(hoverBegan) > 0.6 { overlay.popover.orderOut(nil); displayed = nil }
            return
        }
        if Date().timeIntervalSince(hoverBegan) > 0.2 && (displayed?.range != mark.range || displayed?.sentence != mark.sentence) {
            rewriteTask?.cancel(); displayed = mark; overlay.show(mark: mark)
        }
    }
    private func makeMarks(for editor: EditorSnapshot) -> [Mark] {
        var result: [Mark] = []
        for edit in currentEdits {
            for wordRange in HighlightRanges.words(in: edit.range, text: editor.text) {
                if let rect = bridge.bounds(wordRange, in: editor) {
                    result.append(Mark(range: edit.range, rect: rect, word: edit.original, suggestions: [edit.replacement], sentence: false, displayRange: wordRange, dictionaryWord: PreferenceStore.word(at: wordRange, in: editor.text)))
                }
            }
        }
        for range in SentenceRanges.inText(editor.text).prefix(80) where range.length <= 1000 {
            for wordRange in HighlightRanges.words(in: range, text: editor.text) {
                if let rect = bridge.bounds(wordRange, in: editor) {
                    result.append(Mark(range: range, rect: rect, word: (editor.text as NSString).substring(with: range), suggestions: [], sentence: true, displayRange: wordRange))
                }
            }
        }
        return result
    }
    func analyze(_ editor: EditorSnapshot) {
        snapshot = editor; feedback = "Checking spelling and grammar with Qwen3…"
        analyzedText = editor.text
        analysisTask = Task { [weak self] in
            do {
                let edits = try await LocalModel().analyze(editor.text)
                guard !Task.isCancelled, let self, let current = self.snapshot,
                      current.sameEditor(as: editor), current.text == editor.text else { return }
                self.currentEdits = edits
                self.marks = self.makeMarks(for: current)
                self.overlay.draw(self.marks); self.lastGeometryUpdate = Date()
                let visible = Set(self.marks.filter { !$0.sentence }.map { $0.range }).count
                self.feedback = edits.isEmpty ? "Qwen3 · No issues found" : visible == 0 ? "Qwen3 found \(edits.count) issues · Editor does not expose word positions" : "Qwen3 · \(visible) corrections · Hover an underline"
                self.analysisTask = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.feedback = error.localizedDescription
                self.analysisTask = nil
            }
        }
    }
    func apply(_ replacement: String) {
        guard !applying, let editor = snapshot, let mark = displayed else { return }
        if let selectedRange, bridge.selectedRange(in: editor) != selectedRange {
            clear(); feedback = "The selection changed. Select the phrase again."; return
        }
        let edit = TextEdit(range: mark.range, original: mark.word, replacement: replacement)
        applying = true
        overlay.show(mark: mark, message: "Applying correction…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.applying = false }
            if await self.bridge.applyVerified(edit, to: editor) { self.clear(); self.feedback = "Correction applied" }
            else { self.feedback = self.bridge.failure; self.overlay.show(mark: mark, message: self.bridge.failure) }
        }
    }
    func rewrite() {
        guard let mark = displayed, let editor = snapshot else { return }
        let expectedSelection = selectedRange
        rewriteResult = nil
        rewriteTask?.cancel(); overlay.show(mark: mark, message: "Generating locally…")
        rewriteTask = Task { [weak self] in
            do {
                let result = try await LocalModel().rewrite(mark.word)
                guard !Task.isCancelled, let self, self.snapshot?.text == editor.text,
                      self.snapshot?.sameEditor(as: editor) == true,
                      self.displayed?.range == mark.range,
                      self.selectedRange == expectedSelection,
                      expectedSelection == nil || self.bridge.selectedRange(in: editor) == expectedSelection else { return }
                self.rewriteResult = result
                self.overlay.show(mark: mark, replacement: result)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.overlay.show(mark: mark, message: error.localizedDescription)
            }
        }
    }
}

@main
struct LocalWriterApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--native-messaging") { NativeMessaging.run(); return }
        if CommandLine.arguments.contains("--render-popup") {
            _ = NSApplication.shared
            let overlay = Overlay()
            overlay.show(mark: Mark(range: NSRange(location: 0, length: 9), rect: CGRect(x: 300, y: 400, width: 100, height: 20), word: "She don't", suggestions: ["She doesn’t"], sentence: false))
            let content = overlay.popover.contentView!
            content.layoutSubtreeIfNeeded()
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/localwriter-popup.png"))
            overlay.hide()
            return
        }
        if CommandLine.arguments.contains("--check-clipboard") {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let item = NSPasteboardItem()
            item.setString("original", forType: .string)
            let custom = NSPasteboard.PasteboardType("localwriter.test.binary")
            item.setData(Data([0, 1, 255]), forType: custom)
            board.writeObjects([item])
            let lease = PasteboardLease(text: "replacement", pasteboard: board)!
            precondition(board.string(forType: .string) == "replacement")
            lease.restore()
            precondition(board.string(forType: .string) == "original")
            precondition(board.data(forType: custom) == Data([0, 1, 255]))
            let newer = PasteboardLease(text: "replacement", pasteboard: board)!
            board.clearContents(); board.setString("new copy", forType: .string)
            newer.restore()
            precondition(board.string(forType: .string) == "new copy")
            print("PASS: clipboard formats restored; newer clipboard copy preserved")
            return
        }
        if CommandLine.arguments.contains("--check-editor") {
            _ = NSApplication.shared
            Task { @MainActor in
                do {
                    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
                    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 250))
                    view.font = .systemFont(ofSize: 20); view.isContinuousSpellCheckingEnabled = false
                    view.string = "This is a speling mistake. She go to work yesterday."
                    window.contentView = view
                    let bridge = AccessibilityBridge(); bridge.practiceEditor = view
                    let snapshot = bridge.practiceSnapshot()!
                    let edits = try await LocalModel().analyze(snapshot.text)
                    guard let spelling = edits.first(where: { $0.original.contains("speling") && $0.replacement.contains("spelling") }),
                          edits.contains(where: { $0.original.contains("go") && $0.replacement.contains("went") }),
                          let rect = bridge.bounds(spelling.range, in: snapshot), rect.width > 0,
                          bridge.apply(spelling, to: snapshot), view.string.contains("spelling"),
                          !bridge.apply(spelling, to: snapshot) else {
                        print("FAIL: model detection, native geometry, correction or stale-edit guard; edits: \(edits)"); exit(1)
                    }
                    let overlay = Overlay()
                    overlay.draw([Mark(range: spelling.range, rect: rect, word: spelling.original, suggestions: [spelling.replacement], sentence: false)])
                    precondition(overlay.window.isVisible && overlay.view.marks.count == 1)
                    overlay.hide()
                    print("PASS: real model spelling + grammar, native word geometry, overlay visibility, correction and stale-edit rejection")
                    exit(0)
                } catch { print("FAIL: \(error)"); exit(1) }
            }
            NSApplication.shared.run()
            return
        }
        if CommandLine.arguments.contains("--probe-editor") {
            _ = NSApplication.shared
            Task { @MainActor in
                let bridge = AccessibilityBridge()
                var target: NSRunningApplication?
                if let i = CommandLine.arguments.firstIndex(of: "--app"), CommandLine.arguments.count > i + 1 {
                    target = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[i + 1]).first
                    guard target != nil else { print("Requested test app is not running"); exit(1) }
                }
                var lines = [bridge.diagnosticSummary(app: target)]
                let excluded = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
                lines.append("Excluded app IDs: \(excluded)")
                if let editor = bridge.snapshot(app: target) {
                    lines.append("Editor frame: \(editor.frame)")
                    do {
                        try await Task.sleep(nanoseconds: 800_000_000)
                        let next = bridge.snapshot(app: target)
                        lines.append("Stable editor: \(next.map { $0.sameEditor(as: editor) } ?? false), stable text: \(next?.text == editor.text)")
                        let edits = try await LocalModel().analyze(editor.text)
                        lines.append("Model issues: \(edits.count)")
                        for edit in edits {
                            lines.append("Issue range: \(edit.range), whitespace: \(edit.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), rect: \(String(describing: bridge.bounds(edit.range, in: editor)))")
                        }
                        for edit in edits { lines.append(bridge.rangeDiagnostic(edit.range, editor: editor)) }
                        let sample = NSRange(location: 0, length: min(1, editor.text.utf16.count))
                        lines.append(bridge.rangeDiagnostic(sample, editor: editor))
                        lines.append("First character rect: \(String(describing: bridge.bounds(sample, in: editor)))")
                    } catch { lines.append("Error: \(error.localizedDescription)") }
                } else { lines.append("Snapshot failed: \(bridge.failure)") }
                let report = lines.joined(separator: "\n")
                if let i = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > i + 1 {
                    try? report.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
                }
                print(report); exit(0)
            }
            NSApplication.shared.run(); return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let report = AccessibilityBridge().diagnosticSummary()
            print(report)
            if let i = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > i + 1 {
                try? report.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
            }
            return
        }
        if CommandLine.arguments.contains("--check-model") {
            Task {
                do {
                    let result = try await LocalModel().rewrite("She go to the office yesterday and forget her laptop.")
                    print("Local model rewrite: \(result)")
                    exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
