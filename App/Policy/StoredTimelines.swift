import Foundation

extension Policy {
    /// Osy poskládané z uloženého záznamu (#203).
    ///
    /// Prázdné pole u záznamu, který osu neuložil (soubory z doby před #203) — tab `Průběh` pak
    /// řekne totéž co dneska, tedy že se nic nedělo. **Vynechávají se běhy s prázdnou osou**:
    /// hlavička revieweera bez jediné události by tvrdila, že běh proběhl bez toho, aby cokoli
    /// udělal, a to z uloženého `nil` neplyne.
    ///
    /// Pořadí je **pořadí běhů v záznamu**, tedy stejné, v jakém je poskládal běh sám.
    static func timelines(of record: ReviewRecord?) -> [ReviewerTimeline] {
        guard let record else { return [] }
        return record.runs
            .filter { $0.timeline?.entries.isEmpty == false }
            .map(ReviewerTimeline.init)
    }
}
