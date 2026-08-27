import Foundation

/// Co GitHub říká o **slévatelnosti větve** (#465) — dvě pole, protože odpovídají na dvě různé
/// otázky.
///
/// `mergeable` je o **obsahu**: jdou ty dvě větve složit dohromady, nebo je v nich konflikt.
/// `mergeStateStatus` je o **pravidlech repozitáře**: jestli merge pustí ochrana větve, jestli je
/// PR pozadu, jestli je rozpracovaný. Slít je do jednoho booleanu by znamenalo, že se v panelu
/// nedá napsat proč — a zašedlé tlačítko bez věty je otázka, na kterou okno neodpoví (#392).
///
/// **Obojí je líné pole GitHubu.** Odpověď se počítá až na vyžádání, takže první dotaz po pushi
/// (a po založení PR) vrací `UNKNOWN` a teprve další už zná výsledek. Kdo se zeptá jednou, dostane
/// tlačítko zašedlé podle náhody; jak se to řeší, je u `GitHubGateway.fetchBranchStatus`.
struct BranchStatus: Hashable, Codable, Sendable {
    /// Jdou ty větve složit? (`mergeable` z GraphQL)
    ///
    /// **Tři hodnoty, ne `Bool?`.** `unknown` je odpověď „ještě jsem nepočítal“, a ta má v panelu
    /// vlastní větu — mlčení by v ní vypadalo jako konflikt.
    enum Mergeability: String, Codable, Sendable, CaseIterable {
        case mergeable
        case conflicting
        case unknown

        /// Z `MERGEABLE` / `CONFLICTING` / `UNKNOWN`. Cokoli jiného je `unknown`: hádat
        /// slévatelnost z hodnoty, kterou neznáme, je ta nejdražší strana omylu.
        init(raw: String?) {
            switch raw {
            case "MERGEABLE": self = .mergeable
            case "CONFLICTING": self = .conflicting
            default: self = .unknown
            }
        }
    }

    /// Co na merge říkají pravidla repozitáře (`mergeStateStatus` z GraphQL).
    ///
    /// **Vyjmenované celé, i to, co dnes nic nemění** — je to výčet GitHubu a `Policy` nad ním má
    /// vyčerpávající `switch`, takže se nová hodnota pozná při překladu, ne až v okně.
    ///
    /// **`blocked` neznamená jen „červený check“**: GitHub ho vrací i tehdy, když chybí schválení,
    /// a hlavně **i tomu, kdo do repozitáře nemá zápis** (změřeno na `cli/cli#14278`, kde vyšlo
    /// `BLOCKED` u `MERGEABLE`). Věta v panelu proto nesmí tvrdit důvod, který z tohohle pole
    /// neplyne.
    enum MergeState: String, Codable, Sendable, CaseIterable {
        case clean
        case blocked
        case behind
        case dirty
        case unstable
        case draft
        case hasHooks
        case unknown

        init(raw: String?) {
            switch raw {
            case "CLEAN": self = .clean
            case "BLOCKED": self = .blocked
            case "BEHIND": self = .behind
            case "DIRTY": self = .dirty
            case "UNSTABLE": self = .unstable
            case "DRAFT": self = .draft
            case "HAS_HOOKS": self = .hasHooks
            default: self = .unknown
            }
        }
    }

    let mergeability: Mergeability
    let mergeState: MergeState

    /// Ví už GitHub, jak to dopadne? Na tom stojí, jestli má smysl ptát se znovu.
    var isSettled: Bool { mergeability != .unknown }
}

/// Stav dotažení slévatelnosti jednoho PR (#465).
///
/// Stejný tvar jako `MetadataState` a ze stejného důvodu: **„nedá se mergnout“ a „nezjistil jsem,
/// jestli to jde“ se nesmí slít.** Podle prvního se tlačítko zašedne s důvodem, podle druhého se
/// nesmí tvrdit vůbec nic — merge je nevratný a tvrdit o něm něco z chybějících dat je ta nejhorší
/// možná odpověď.
enum BranchStatusState: Equatable, Sendable {
    case loading
    case loaded(BranchStatus, updatedAt: Date)
    case failed(String)

    /// Načtený stav, nebo `nil`. Pro volajícího, kterého nezajímá proč.
    var status: BranchStatus? {
        if case .loaded(let status, _) = self { status } else { nil }
    }

    var failure: String? {
        if case .failed(let reason) = self { reason } else { nil }
    }
}
