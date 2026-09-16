import Foundation

public enum TextLeafRanges {
    /// Rich editor leaves may omit paragraph separators. Only whitespace gaps are allowed.
    public static func align(_ leaves: [String], in text: String) -> [NSRange]? {
        let source = text as NSString
        var offset = 0
        var ranges: [NSRange] = []
        for leaf in leaves {
            guard !leaf.isEmpty else { ranges.append(NSRange(location: offset, length: 0)); continue }
            let range = source.range(of: leaf, options: .literal, range: NSRange(location: offset, length: source.length - offset))
            guard range.location != NSNotFound,
                  source.substring(with: NSRange(location: offset, length: range.location - offset)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            ranges.append(range); offset = NSMaxRange(range)
        }
        guard source.substring(from: offset).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ranges
    }
}

public enum HighlightRanges {
    /// Geometry belongs to visible words, never to whitespace or whole multiline boxes.
    public static func words(in range: NSRange, text: String) -> [NSRange] {
        guard Range(range, in: text) != nil else { return [] }
        let regex = try! NSRegularExpression(pattern: #"\S+"#)
        return regex.matches(in: text, range: range).map(\.range)
    }
}

public enum EditorSearch {
    /// A container can report focus instead of its editable child. Prefer explicit focus;
    /// use a unique textarea only when the container offers no focused editable child.
    public static func resolve<Node>(root: Node, children: (Node) -> [Node],
                                     isEditor: (Node) -> Bool, isTextArea: (Node) -> Bool,
                                     isFocused: (Node) -> Bool, isSecure: (Node) -> Bool) -> Node? {
        var queue: [(Node, Int)] = [(root, 0)]
        var index = 0
        var candidates: [Node] = []
        var focused: [Node] = []
        var truncated = false
        while index < queue.count && index < 256 {
            let (node, depth) = queue[index]; index += 1
            if isSecure(node) { continue }
            if isEditor(node) {
                if isFocused(node) { focused.append(node) }
                if isTextArea(node) { candidates.append(node) }
                continue
            }
            let descendants = children(node)
            let capacity = depth < 12 ? max(0, 256 - queue.count) : 0
            if descendants.count > capacity { truncated = true }
            queue.append(contentsOf: descendants.prefix(capacity).map { ($0, depth + 1) })
        }
        if focused.count == 1 { return focused[0] }
        return !truncated && focused.isEmpty && candidates.count == 1 ? candidates[0] : nil
    }
}
