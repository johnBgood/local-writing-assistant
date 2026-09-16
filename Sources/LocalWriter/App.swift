import AppKit
import ApplicationServices
import WritingCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let bridge = AccessibilityBridge()
    private let overlay = Overlay()
    private var timer: Timer?
    private var snapshot: EditorSnapshot?
    private var marks: [Mark] = []
    private var paused = false
    private var pendingText = ""
    private var changedAt = Date()
    private var hovered: Mark?
    private var hoverBegan = Date()
    private var displayed: Mark?
    private var rewriteTask: Task<Void, Never>?
    private var demoWindow: NSWindow?
    private var lastGeometryUpdate = Date.distantPast
    private let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "✎"
        let menu = NSMenu(); menu.addItem(status)
        menu.addItem(.separator())
        add("Grant Accessibility Access…", #selector(permission), to: menu)
        add("Pause / Resume", #selector(toggle), to: menu)
        add("Exclude / Include Current App", #selector(exclude), to: menu)
        add("Open Practice Editor", #selector(demo), to: menu)
        add("Model Setup Instructions", #selector(modelHelp), to: menu)
        menu.addItem(.separator()); add("Quit LocalWriter", #selector(quit), to: menu)
        item.menu = menu
        overlay.action = { [weak self] replacement in self?.apply(replacement) }
        overlay.rewriteAction = { [weak self] in self?.rewrite() }
        overlay.dismissAction = { [weak self] in self?.displayed = nil; self?.hoverBegan = Date() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        status.title = AXIsProcessTrusted() ? "Ready · English · Local" : "Accessibility permission needed"
    }
    func add(_ title: String, _ selector: Selector, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
    }
    @objc func permission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    @objc func toggle() { paused.toggle(); clear(); item.button?.title = paused ? "✎Ⅱ" : "✎" }
    @objc func exclude() {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        var excluded = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
        if excluded.contains(id) { excluded.removeAll { $0 == id } } else { excluded.append(id) }
        UserDefaults.standard.set(excluded, forKey: "excludedApps"); clear()
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func modelHelp() {
        let alert = NSAlert(); alert.messageText = "Local sentence rewrites"
        alert.informativeText = "Install Ollama from ollama.com, then run:\n\nollama pull qwen3:4b\n\nKeep Ollama running. LocalWriter connects only to 127.0.0.1:11434. Spelling works without a model. The repository includes scripts/setup-model.sh."
        alert.runModal()
    }
    @objc func demo() {
        if demoWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 660, height: 350), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "LocalWriter Practice — macOS spelling preview"
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds); scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds); text.isRichText = false; text.font = .systemFont(ofSize: 20)
            text.textContainerInset = NSSize(width: 20, height: 20); text.autoresizingMask = [.width]
            text.isContinuousSpellCheckingEnabled = true; text.isGrammarCheckingEnabled = true
            text.string = "This is a sentnce with a speling mistake.\n\nFor cross-app hover suggestions, type a draft in Slack or TextEdit."
            scroll.documentView = text; window.contentView?.addSubview(scroll); demoWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); demoWindow?.makeKeyAndOrderFront(nil)
    }
    func clear() {
        rewriteTask?.cancel(); rewriteTask = nil
        snapshot = nil; marks = []; hovered = nil; displayed = nil; pendingText = ""; overlay.hide()
    }
    func tick() {
        guard !paused else { status.title = "Paused"; return }
        guard AXIsProcessTrusted() else { clear(); status.title = "Accessibility permission needed"; return }
        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !(UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []).contains(appID) else { clear(); status.title = "Current app excluded"; return }
        guard let current = bridge.snapshot() else { clear(); status.title = "No supported editor focused"; return }
        if let old = snapshot, old.pid != current.pid || !CFEqual(old.element, current.element) { clear() }
        if current.text != pendingText {
            clear(); pendingText = current.text; changedAt = Date(); snapshot = current
            status.title = "Waiting for typing pause…"; return
        }
        guard Date().timeIntervalSince(changedAt) > 0.65 else { return }
        if marks.isEmpty && snapshot?.text == current.text && Date().timeIntervalSince(lastGeometryUpdate) > 1 {
            analyze(current)
        } else if Date().timeIntervalSince(lastGeometryUpdate) > 0.5 {
            let updated = marks.compactMap { mark -> Mark? in
                guard let rect = bridge.bounds(mark.range, in: current) else { return nil }
                return Mark(range: mark.range, rect: rect, word: mark.word, suggestions: mark.suggestions, sentence: mark.sentence)
            }
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
        if Date().timeIntervalSince(hoverBegan) > 0.65 && (displayed?.range != mark.range || displayed?.sentence != mark.sentence) {
            rewriteTask?.cancel(); displayed = mark; overlay.show(mark: mark)
        }
    }
    func analyze(_ editor: EditorSnapshot) {
        snapshot = editor; marks = []
        let ns = editor.text as NSString
        var offset = 0
        while offset < ns.length && marks.count < 80 {
            let range = NSSpellChecker.shared.checkSpelling(of: editor.text, startingAt: offset, language: "en_US", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            guard range.location != NSNotFound, range.length > 0 else { break }
            offset = NSMaxRange(range)
            if let rect = bridge.bounds(range, in: editor) {
                let guesses = NSSpellChecker.shared.guesses(forWordRange: range, in: editor.text, language: "en_US", inSpellDocumentWithTag: 0) ?? []
                marks.append(Mark(range: range, rect: rect, word: ns.substring(with: range), suggestions: guesses, sentence: false))
            }
        }
        for range in SentenceRanges.inText(editor.text).prefix(80) where range.length <= 1000 {
            // Single-line sentences only: AX often returns a large enclosing box for wrapped text.
            if let rect = bridge.bounds(range, in: editor), rect.height < 40 {
                marks.append(Mark(range: range, rect: rect, word: ns.substring(with: range), suggestions: [], sentence: true))
            }
        }
        overlay.draw(marks); lastGeometryUpdate = Date()
        let count = marks.filter { !$0.sentence }.count
        status.title = "Local · \(count) spelling suggestions"
    }
    func apply(_ replacement: String) {
        guard let editor = snapshot, let mark = displayed else { return }
        let edit = TextEdit(range: mark.range, original: mark.word, replacement: replacement)
        if bridge.apply(edit, to: editor) { clear() }
        else { overlay.show(mark: mark, message: "This editor could not apply the change, or the text changed. You can select and replace the text manually.", replacement: nil) }
    }
    func rewrite() {
        guard let mark = displayed, let editor = snapshot else { return }
        rewriteTask?.cancel(); overlay.show(mark: mark, message: "Generating locally…")
        rewriteTask = Task { [weak self] in
            do {
                let result = try await LocalModel().rewrite(mark.word)
                guard !Task.isCancelled, let self, self.snapshot?.text == editor.text,
                      self.displayed?.range == mark.range else { return }
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
