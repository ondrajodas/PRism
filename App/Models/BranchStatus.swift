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

    /// O kolik je větev vedle základu (#466). `nil` = **nevím**.
    ///
    /// **Vlastní pole, protože `mergeStateStatus` na tuhle otázku neodpovídá** — a je to změřené:
    /// větev o commit pozadu za `master` vrátila na `prism-review-sandbox#9` `mergeStateStatus:
    /// CLEAN`, ne `BEHIND`. `BEHIND` GitHub vydá jedině tam, kde to vyžaduje ochrana větve
    /// („Require branches to be up to date“); jinde je „pozadu“ stav, o kterém `mergeStateStatus`
    /// mlčí, protože mergi nebrání. Odpověď proto přináší `compare` z GraphQL.
    var divergence: BranchDivergence?

    init(mergeability: Mergeability, mergeState: MergeState, divergence: BranchDivergence? = nil) {
        self.mergeability = mergeability
        self.mergeState = mergeState
        self.divergence = divergence
    }

    /// Ví už GitHub, jak to dopadne? Na tom stojí, jestli má smysl ptát se znovu.
    var isSettled: Bool { mergeability != .unknown }
}

/// O kolik je hlava pull requestu vedle svého základu (#466).
///
/// **Z pohledu hlavy, ne základu** — `behind` je „kolik commitů základu ve větvi chybí“, `ahead`
/// „kolik commitů větev nese navíc“. Změřeno na GraphQL `Ref.compare(headRef:)`: base `master`
/// proti commitu o jeden zpátky vrátilo `aheadBy: 0, behindBy: 1, status: BEHIND`, kdežto proti
/// větvi s vlastním commitem `aheadBy: 1, behindBy: 1, status: DIVERGED`.
struct BranchDivergence: Hashable, Codable, Sendable {
    /// Kolik commitů větev nese nad základem — tedy kolik se jich při srovnání přehraje.
    let ahead: Int
    /// O kolik commitů je větev pozadu. `0` = srovnaná.
    let behind: Int

    var isBehind: Bool { behind > 0 }
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
