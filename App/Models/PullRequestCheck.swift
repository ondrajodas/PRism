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

/// Souhrn checků do hlavičky PR (#209).
struct ChecksSummary: Hashable, Sendable {
    let passed: Int
    let failed: Int
    let running: Int
    let skipped: Int

    /// Nejhorší stav, který v sadě je — **podle nejhoršího, ne podle většiny**. Dvanáct
    /// zelených a jeden červený je červený stav; většinové počítání by z rozbitého buildu
    /// udělalo „skoro hotovo“.
    var worst: PullRequestCheck.Outcome? {
        if failed > 0 { return .failed }
        if running > 0 { return .running }
        if passed > 0 { return .passed }
        if skipped > 0 { return .skipped }
        return nil
    }

    var isEmpty: Bool { passed + failed + running + skipped == 0 }
}

extension Policy {
    /// Souhrn checků. Zrušené se počítají k spadlým — z obojího plyne, že se PR nemá čím
    /// pochlubit, a vlastní číslo pro „někdo to zabil“ by v souhrnu nikoho nezajímalo.
    static func summary(of checks: [PullRequestCheck]) -> ChecksSummary {
        ChecksSummary(
            passed: checks.count { $0.outcome == .passed },
            failed: checks.count { $0.outcome == .failed || $0.outcome == .cancelled },
            running: checks.count { $0.outcome == .running },
            skipped: checks.count { $0.outcome == .skipped }
        )
    }

    /// Pořadí checků: **spadlé nahoru, přeskočené dolů**.
    ///
    /// Na skutečném PR jich bývá přes dvacet a většina přeskočená (změřeno na
    /// `keboola/platform-libraries#557`: 28 checků, 22 přeskočených). Bez pořadí by ten jeden
    /// spadlý ležel někde uprostřed a blok by byl k ničemu.
    static func sorted(_ checks: [PullRequestCheck]) -> [PullRequestCheck] {
        checks.sorted { left, right in
            let ranks = (rank(of: left.outcome), rank(of: right.outcome))
            if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
            // Při shodě podle jména, ať se pořadí mezi načteními nemění.
            return left.name < right.name
        }
    }

    private static func rank(of outcome: PullRequestCheck.Outcome) -> Int {
        switch outcome {
        case .failed: 0
        case .cancelled: 1
        case .running: 2
        case .passed: 3
        case .skipped: 4
        }
    }
}
