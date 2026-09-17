import AppKit

/// Temporarily supplies plain text, restoring all prior formats unless the user copies something else.
@MainActor
final class PasteboardLease {
    private let pasteboard: NSPasteboard
    private let saved: [NSPasteboardItem]
    private let ownedChangeCount: Int

    init?(text: String, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        let before = pasteboard.changeCount
        var copies: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                copy.setData(data, forType: type)
            }
            copies.append(copy)
        }
        guard pasteboard.changeCount == before else { return nil }
        saved = copies
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            pasteboard.writeObjects(copies); return nil
        }
        ownedChangeCount = pasteboard.changeCount
    }

    func restore() {
        guard pasteboard.changeCount == ownedChangeCount else { return }
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
    }
}
