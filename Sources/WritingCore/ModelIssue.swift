import Foundation

public enum ModelEdits {
    /// The model corrects prose; we calculate exact UTF-16 edit ranges locally.
    public static func difference(from original: String, to corrected: String) -> [TextEdit] {
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}_]+|\s+|[^\p{L}\p{M}\p{N}_\s]"#)
        let old = original as NSString; let new = corrected as NSString
        let oldRanges = regex.matches(in: original, range: NSRange(location: 0, length: old.length)).map(\.range)
        let newRanges = regex.matches(in: corrected, range: NSRange(location: 0, length: new.length)).map(\.range)
        let oldTokens = oldRanges.map { old.substring(with: $0) }
        let newTokens = newRanges.map { new.substring(with: $0) }
        let difference = newTokens.difference(from: oldTokens)
        var removed = Set<Int>(); var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var i = 0; var j = 0; var edits: [TextEdit] = []
        while i < oldTokens.count || j < newTokens.count {
            if !removed.contains(i), !inserted.contains(j) {
                guard i < oldTokens.count, j < newTokens.count, oldTokens[i] == newTokens[j] else { return [] }
                i += 1; j += 1; continue
            }
            let startI = i; let startJ = j
            while removed.contains(i) { i += 1 }
            while inserted.contains(j) { j += 1 }
            var start = startI < oldRanges.count ? oldRanges[startI].location : old.length
            var end = i > startI ? NSMaxRange(oldRanges[i - 1]) : start
            var replacement = newTokens[startJ..<j].joined()
            // Attach insertions to a neighboring token so they have a visible underline.
            if start == end {
                if startI < oldTokens.count {
                    end = NSMaxRange(oldRanges[startI]); replacement += oldTokens[startI]
                } else if startI > 0 {
                    start = oldRanges[startI - 1].location; replacement = oldTokens[startI - 1] + replacement
                } else { return [] }
            }
            let range = NSRange(location: start, length: end - start)
            let edit = TextEdit(range: range, original: old.substring(with: range), replacement: replacement)
            guard edit.applying(to: original, snapshot: original) != nil else { return [] }
            edits.append(edit)
        }
        return edits
    }
}
