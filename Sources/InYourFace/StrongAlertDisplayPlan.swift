struct StrongAlertDisplayPlan: Equatable, Sendable {
    let primaryIndex: Int
    let additionalIndices: [Int]

    var allDisplayIndices: [Int] {
        [primaryIndex] + additionalIndices
    }

    init?(displayCount: Int, primaryIndex: Int?) {
        guard displayCount > 0 else { return nil }

        let resolvedPrimaryIndex = primaryIndex.flatMap { index in
            (0..<displayCount).contains(index) ? index : nil
        } ?? 0
        self.primaryIndex = resolvedPrimaryIndex
        self.additionalIndices = (0..<displayCount).filter { $0 != resolvedPrimaryIndex }
    }
}
