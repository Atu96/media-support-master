import Foundation

enum TimelineCueSelectionIntent {
    case replace
    case toggle
    case range
}

/// Selection thuần của Timeline; không phụ thuộc SwiftUI/AppKit nên có thể test riêng.
struct TimelineCueSelection: Equatable {
    private(set) var selectedIDs: Set<Int> = []
    private(set) var primaryID: Int?
    private(set) var anchorID: Int?

    var count: Int { selectedIDs.count }
    var isEmpty: Bool { selectedIDs.isEmpty }

    mutating func select(id: Int, intent: TimelineCueSelectionIntent, orderedIDs: [Int]) {
        guard let clickedIndex = orderedIDs.firstIndex(of: id) else { return }

        switch intent {
        case .replace:
            replace(with: id)
        case .toggle:
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
                if primaryID == id {
                    primaryID = orderedIDs.first(where: selectedIDs.contains)
                }
            } else {
                selectedIDs.insert(id)
                primaryID = id
            }
            anchorID = selectedIDs.isEmpty ? nil : id
        case .range:
            let rangeAnchorID = anchorID ?? primaryID ?? id
            let anchorIndex = orderedIDs.firstIndex(of: rangeAnchorID) ?? clickedIndex
            selectedIDs = Set(orderedIDs[min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)])
            primaryID = id
            anchorID = rangeAnchorID
        }
    }

    mutating func replace(with id: Int?) {
        guard let id else { clear(); return }
        selectedIDs = [id]
        primaryID = id
        anchorID = id
    }

    mutating func replace(with ids: Set<Int>, orderedIDs: [Int]) {
        let validIDs = ids.intersection(orderedIDs)
        guard !validIDs.isEmpty else { clear(); return }
        selectedIDs = validIDs
        primaryID = orderedIDs.first(where: validIDs.contains)
        anchorID = primaryID
    }

    mutating func selectAll(orderedIDs: [Int]) {
        selectedIDs = Set(orderedIDs)
        primaryID = orderedIDs.first
        anchorID = primaryID
    }

    mutating func reconcile(orderedIDs: [Int]) {
        let validIDs = Set(orderedIDs)
        selectedIDs.formIntersection(validIDs)
        if primaryID.map(validIDs.contains) != true {
            primaryID = orderedIDs.first(where: selectedIDs.contains)
        }
        if anchorID.map(validIDs.contains) != true {
            anchorID = primaryID
        }
        if selectedIDs.isEmpty { clear() }
    }

    mutating func clear() {
        selectedIDs = []
        primaryID = nil
        anchorID = nil
    }

    func selectedIndices(orderedIDs: [Int]) -> [Int] {
        orderedIDs.indices.filter { selectedIDs.contains(orderedIDs[$0]) }
    }

    func canMerge(orderedIDs: [Int]) -> Bool {
        let indices = selectedIndices(orderedIDs: orderedIDs)
        guard indices.count >= 2, let first = indices.first, let last = indices.last else { return false }
        return indices == Array(first...last)
    }

    func canDelete(totalCueCount: Int) -> Bool {
        totalCueCount > 0 && !selectedIDs.isEmpty
    }
}
