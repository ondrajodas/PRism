import Foundation

extension Policy {
    /// Osy poskládané z uloženého záznamu (#203).
    ///
    /// **Chybějící osa (`timeline == nil`) není prázdná osa.** `nil` znamená „neuložila se“ — tak
    /// vypadají soubory z doby před #203 — kdežto `entries: []` by znamenalo „uložila se a nic
    /// v ní nebylo“. Ani jedno se v tabu `Průběh` nekreslí: hlavička revieweera bez jediné
    /// události tvrdí, že běh proběhl, aniž by cokoli udělal, a to z chybějícího klíče neplyne.
    ///
    /// Pořadí je **pořadí běhů v záznamu**, tedy stejné, v jakém je poskládal běh sám.
    static func timelines(of record: ReviewRecord?) -> [ReviewerTimeline] {
        guard let record else { return [] }
        return record.runs
            .filter { $0.timeline?.entries.isEmpty == false }
            .map(ReviewerTimeline.init)
    }
}
