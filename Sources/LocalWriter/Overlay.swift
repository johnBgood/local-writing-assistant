import AppKit

struct Mark {
    let range: NSRange
    let rect: CGRect
    let word: String
    let suggestions: [String]
    let sentence: Bool
}

@MainActor
final class UnderlineView: NSView {
    var marks: [Mark] = []
    override func draw(_ dirtyRect: NSRect) {
        for mark in marks where !mark.sentence {
            NSColor.systemRed.setStroke()
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
final class Overlay {
    let window: NSPanel
    let view = UnderlineView()
    let popover: NSPanel
    var action: ((String) -> Void)?
    var rewriteAction: (() -> Void)?
    var dismissAction: (() -> Void)?
    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.ignoresMouseEvents = true; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        popover = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        popover.level = .popUpMenu; popover.hasShadow = true
        popover.backgroundColor = .windowBackgroundColor
        popover.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popover.hidesOnDeactivate = false
    }
    func draw(_ marks: [Mark]) {
        guard !marks.isEmpty else { window.orderOut(nil); return }
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        window.setFrame(union, display: false)
        view.frame = CGRect(origin: .zero, size: union.size)
        view.marks = marks.map { Mark(range: $0.range, rect: $0.rect.offsetBy(dx: -union.minX, dy: -union.minY), word: $0.word, suggestions: $0.suggestions, sentence: $0.sentence) }
        view.needsDisplay = true; window.orderFrontRegardless()
    }
    func hide() { window.orderOut(nil); popover.orderOut(nil) }
    func show(mark: Mark, message: String? = nil, replacement: String? = nil) {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        let title = NSTextField(labelWithString: mark.sentence ? "Improve sentence · On-device" : "Spelling · \(mark.word)")
        title.font = .boldSystemFont(ofSize: 13); stack.addArrangedSubview(title)
        if let message {
            let label = NSTextField(wrappingLabelWithString: message)
            label.preferredMaxLayoutWidth = 320; stack.addArrangedSubview(label)
        }
        if let replacement {
            let label = NSTextField(wrappingLabelWithString: replacement)
            label.preferredMaxLayoutWidth = 320; stack.addArrangedSubview(label)
            let button = NSButton(title: "Apply rewrite", target: self, action: #selector(choose(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(replacement); stack.addArrangedSubview(button)
        } else if mark.sentence && message == nil {
            let button = NSButton(title: "Suggest a clearer sentence", target: self, action: #selector(rewrite))
            stack.addArrangedSubview(button)
        } else if !mark.sentence && message == nil {
            for suggestion in mark.suggestions.prefix(5) {
                let button = NSButton(title: suggestion, target: self, action: #selector(choose(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(suggestion); stack.addArrangedSubview(button)
            }
            if mark.suggestions.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: "No spelling suggestions available.")) }
        }
        let close = NSButton(title: "Dismiss", target: self, action: #selector(dismiss))
        stack.addArrangedSubview(close)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 350)
        ])
        popover.contentView = content
        let size = stack.fittingSize
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(mark.rect) })?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(mark.rect.minX, screen.minX), screen.maxX - 350)
        let y = max(screen.minY, min(mark.rect.minY - size.height - 6, screen.maxY - size.height))
        popover.setFrame(CGRect(x: x, y: y, width: 350, height: size.height), display: true)
        popover.orderFrontRegardless()
    }
    @objc private func choose(_ sender: NSButton) { if let text = sender.identifier?.rawValue { action?(text) } }
    @objc private func rewrite() { rewriteAction?() }
    @objc private func dismiss() { popover.orderOut(nil); dismissAction?() }
}
