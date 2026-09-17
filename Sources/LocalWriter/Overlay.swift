import AppKit

struct Mark {
    let range: NSRange
    let rect: CGRect
    let word: String
    let suggestions: [String]
    let sentence: Bool
    var displayRange: NSRange? = nil
    var dictionaryWord: String? = nil
}

@MainActor
final class UnderlineView: NSView {
    var marks: [Mark] = []
    var highlightedSentence: NSRange?
    override func draw(_ dirtyRect: NSRect) {
        for mark in marks where !mark.sentence || mark.range == highlightedSentence {
            (mark.sentence ? NSColor.systemBlue : NSColor.systemRed).setStroke()
            let path = NSBezierPath(); path.lineWidth = 1.5
            var x = mark.rect.minX
            path.move(to: CGPoint(x: x, y: mark.rect.minY + 1))
            while x < mark.rect.maxX {
                x += 2
                path.line(to: CGPoint(x: x, y: mark.rect.minY + (Int(x - mark.rect.minX) % 4 == 0 ? 1 : 3)))
            }
            path.stroke()
        }
    }
}

@MainActor
final class SuggestionButton: NSButton {
    let caption: String
    private var hovering = false
    override var isFlipped: Bool { true }
    private var captionStyle: [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor] }
    private var replacementStyle: [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.systemIndigo] }
    init(caption: String, replacement: String, target: AnyObject, action: Selector) {
        self.caption = caption
        super.init(frame: .zero)
        title = replacement; self.target = target; self.action = action
        isBordered = false; setButtonType(.momentaryChange)
        setAccessibilityLabel(caption + ": " + replacement)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize {
        let height = (title as NSString).boundingRect(with: NSSize(width: 306, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: replacementStyle).height
        return NSSize(width: 334, height: max(76, ceil(height) + 46))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemIndigo.withAlphaComponent(isHighlighted ? 0.20 : hovering ? 0.14 : 0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        (caption as NSString).draw(in: NSRect(x: 14, y: 12, width: bounds.width - 28, height: 18), withAttributes: captionStyle)
        (title as NSString).draw(with: NSRect(x: 14, y: 34, width: bounds.width - 28, height: bounds.height - 44), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: replacementStyle)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
}

@MainActor
final class Overlay {
    let window: NSPanel
    let view = UnderlineView()
    let popover: NSPanel
    var action: ((String) -> Void)?
    var dictionaryAction: ((String) -> Void)?
    var rewriteAction: (() -> Void)?
    var dismissAction: (() -> Void)?
    private var anchorX: CGFloat?
    private var anchoredRange: NSRange?
    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.ignoresMouseEvents = true; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        popover = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        popover.level = .popUpMenu; popover.hasShadow = true
        popover.isOpaque = false; popover.backgroundColor = .clear
        popover.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popover.hidesOnDeactivate = false
    }
    func draw(_ marks: [Mark]) {
        if !popover.isVisible { view.highlightedSentence = nil }
        guard !marks.isEmpty else { window.orderOut(nil); return }
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        window.setFrame(union, display: false)
        view.frame = CGRect(origin: .zero, size: union.size)
        view.marks = marks.map { Mark(range: $0.range, rect: $0.rect.offsetBy(dx: -union.minX, dy: -union.minY), word: $0.word, suggestions: $0.suggestions, sentence: $0.sentence, displayRange: $0.displayRange) }
        view.needsDisplay = true; window.orderFrontRegardless()
    }
    func hide() { view.highlightedSentence = nil; window.orderOut(nil); popover.orderOut(nil) }
    func show(mark: Mark, message: String? = nil, replacement: String? = nil) {
        if !popover.isVisible || anchoredRange != mark.range {
            anchorX = NSEvent.mouseLocation.x - 20
            anchoredRange = mark.range
        }
        view.highlightedSentence = mark.sentence ? mark.range : nil
        view.needsDisplay = true
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        func addCard(_ text: String, caption: String, selector: Selector, replacement: String? = nil) {
            let button = SuggestionButton(caption: caption, replacement: text, target: self, action: selector)
            if let replacement { button.identifier = NSUserInterfaceItemIdentifier(replacement) }
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 334).isActive = true
        }
        if let message {
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 13); label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 306
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalToConstant: 334).isActive = true
        }
        if let replacement {
            addCard(replacement, caption: "Suggested rewrite", selector: #selector(choose(_:)), replacement: replacement)
        } else if mark.sentence && message == nil {
            addCard("Suggest a clearer sentence", caption: "Improve wording · Keep the meaning", selector: #selector(rewrite))
        } else if !mark.sentence && message == nil {
            for suggestion in mark.suggestions.prefix(5) {
                addCard(suggestion.isEmpty ? "Remove this text" : suggestion, caption: "Suggested correction", selector: #selector(choose(_:)), replacement: suggestion)
            }
            if mark.suggestions.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: "No corrections available.")) }
        }
        if !mark.sentence, let word = mark.dictionaryWord {
            let add = NSButton(title: "Add “\(word)” to dictionary", target: self, action: #selector(addWord(_:)))
            add.identifier = NSUserInterfaceItemIdentifier(word); add.isBordered = false
            stack.addArrangedSubview(add)
        }
        let close = NSButton(title: "  Dismiss", target: self, action: #selector(dismiss))
        close.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        close.imagePosition = .imageLeading; close.isBordered = false
        close.font = .systemFont(ofSize: 14); close.contentTintColor = .secondaryLabelColor
        close.alignment = .left; close.setAccessibilityLabel("Dismiss suggestion")
        stack.addArrangedSubview(close)
        close.widthAnchor.constraint(equalToConstant: 334).isActive = true
        close.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSBox(); content.boxType = .custom; content.borderWidth = 0
        content.cornerRadius = 12; content.fillColor = .windowBackgroundColor
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 350)
        ])
        popover.contentView = content
        let size = stack.fittingSize
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(mark.rect) })?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(anchorX ?? mark.rect.minX, screen.minX), screen.maxX - 350)
        let above = mark.rect.maxY + 4
        let preferredY = above + size.height <= screen.maxY ? above : mark.rect.minY - size.height - 4
        let y = max(screen.minY, min(preferredY, screen.maxY - size.height))
        popover.setFrame(CGRect(x: x, y: y, width: 350, height: size.height), display: true)
        popover.orderFrontRegardless()
    }
    @objc private func choose(_ sender: NSButton) { if let text = sender.identifier?.rawValue { action?(text) } }
    @objc private func addWord(_ sender: NSButton) { if let word = sender.identifier?.rawValue { dictionaryAction?(word) } }
    @objc private func rewrite() { rewriteAction?() }
    @objc private func dismiss() { view.highlightedSentence = nil; view.needsDisplay = true; popover.orderOut(nil); dismissAction?() }
}
