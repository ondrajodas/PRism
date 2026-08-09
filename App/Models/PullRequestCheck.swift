import Foundation

/// Jeden check na PR (#209) — job z GitHub Actions nebo jiný status.
struct PullRequestCheck: Hashable, Sendable, Identifiable {
    /// Jak dopadl. **Tři stavy, ne dva**: běžící check není prošlý ani spadlý.
    ///
    /// `skipped` je vlastní případ, ne úspěch — jinak by hlavička svítila zeleně nad
    /// přeskočeným testem. `cancelled` taky ne: zrušený běh o kódu nevypovídá.
    enum Outcome: Hashable, Sendable {
        case passed
        case failed
        case running
        case skipped
        case cancelled

        /// Z `bucket` v `gh pr checks`. Neznámý kbelík je `running` — je to jediný stav, který
        /// nic netvrdí o výsledku, a hádat úspěch nebo selhání by lhalo oběma směry.
        init(bucket: String) {
            switch bucket {
            case "pass": self = .passed
            case "fail": self = .failed
            case "skipping": self = .skipped
            case "cancel": self = .cancelled
            default: self = .running
            }
        }
    }

    let name: String
    let outcome: Outcome
    /// Odkaz na běh na GitHubu. Log se **nestahuje** — jsou to megabajty a čte se jednou.
    let link: URL?
    let startedAt: Date?
    let completedAt: Date?

    var id: String { name }

    /// Jak dlouho běžel. `nil`, dokud neskončil nebo když čas nedorazil.
    var duration: TimeInterval? {
        guard let startedAt, let completedAt, completedAt > startedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}
