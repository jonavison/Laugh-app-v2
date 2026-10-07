import Foundation

/// Ordered multi-select of sibling stills for batch develop actions (ADR 0006).
struct ImageBatchSelection: Equatable {
    private(set) var orderedURLs: [URL] = []
    /// Anchor for shift-range selection.
    private(set) var rangeAnchor: URL?

    var count: Int { orderedURLs.count }
    var isEmpty: Bool { orderedURLs.isEmpty }
    /// Batch chrome / catalog activate at 2+.
    var isActive: Bool { orderedURLs.count >= 2 }

    var pathSet: Set<String> {
        Set(orderedURLs.map { $0.standardizedFileURL.path })
    }

    mutating func clear() {
        orderedURLs = []
        rangeAnchor = nil
    }

    /// Plain click: drop multi-select (open image handled by caller).
    mutating func resetAfterOpen() {
        clear()
    }

    mutating func toggle(_ url: URL, siblings: [URL]) {
        let target = url.standardizedFileURL
        if let index = orderedURLs.firstIndex(where: { $0.standardizedFileURL == target }) {
            orderedURLs.remove(at: index)
            if rangeAnchor?.standardizedFileURL == target {
                rangeAnchor = orderedURLs.last
            }
        } else {
            orderedURLs.append(target)
            rangeAnchor = target
            reorder(using: siblings)
        }
    }

    mutating func selectRange(to url: URL, siblings: [URL]) {
        let target = url.standardizedFileURL
        let siblingURLs = siblings.map(\.standardizedFileURL)
        guard let targetIndex = siblingURLs.firstIndex(of: target) else { return }
        let anchor = rangeAnchor?.standardizedFileURL ?? orderedURLs.last?.standardizedFileURL ?? target
        guard let anchorIndex = siblingURLs.firstIndex(of: anchor) else {
            orderedURLs = [target]
            rangeAnchor = target
            return
        }
        let lo = min(anchorIndex, targetIndex)
        let hi = max(anchorIndex, targetIndex)
        orderedURLs = Array(siblingURLs[lo...hi])
        rangeAnchor = anchor
    }

    mutating func remove(_ url: URL) {
        let target = url.standardizedFileURL
        orderedURLs.removeAll { $0.standardizedFileURL == target }
        if rangeAnchor?.standardizedFileURL == target {
            rangeAnchor = orderedURLs.last
        }
    }

    /// Replace the set (library “Edit as Batch”). Filmstrip order first, then any extras.
    mutating func replace(with urls: [URL], preferredOrder siblings: [URL]) {
        var seen = Set<String>()
        var unique: [URL] = []
        for url in urls {
            let std = url.standardizedFileURL
            let key = std.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(std)
        }
        let selected = Set(unique.map(\.path))
        let siblingURLs = siblings.map(\.standardizedFileURL)
        let inFolder = siblingURLs.filter { selected.contains($0.path) }
        let extras = unique.filter { url in !siblingURLs.contains(where: { $0.path == url.path }) }
        orderedURLs = inFolder + extras
        rangeAnchor = orderedURLs.first
    }

    private mutating func reorder(using siblings: [URL]) {
        let order = siblings.map(\.standardizedFileURL)
        let selected = Set(orderedURLs.map(\.standardizedFileURL))
        orderedURLs = order.filter { selected.contains($0) }
    }
}
