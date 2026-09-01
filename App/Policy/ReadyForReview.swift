import Foundation

/// Třetí akce sekce `Větev` — **`Připravit k review`** (#482, návrh sekce 37).
///
/// Je to čistá funkce ze stejného důvodu jako `mergeOffer` a `branchSyncOffer`: přepnutí z draftu
/// vyžádá review od vlastníků kódu, tedy odešle upozornění, které se odebráním nevezme zpět —
/// takže otázka „smí se to nabídnout, a když ne, proč“ má mít **jednu** odpověď, vyjmenovanou
/// a testovanou výčtem.
///
/// **Nekreslí se jako zašedlé nad nedraftem, ale vůbec.** Je to jediná akce sekce, která má
/// smysl jen v jednom stavu pull requestu: nad otevřeným, zavřeným i mergnutým není co přepínat,
/// takže by zašedlé tlačítko s větou „PR není rozpracovaný“ jen zabíralo řádek v panelu, který
/// má 300 bodů. Tatáž úvaha jako u cizího PR — zašedlé s důvodem patří jedině tam, kde se stav
/// **mění** (vypnutá brána, běžící odeslání).
extension Policy {
    /// Proč `Připravit k review` teď nejde.
    ///
    /// **Vlastní výčet, ne `MergeObstacle`.** Přepnutí z draftu nebrání nic z toho, co brání
    /// mergi: červený check, konflikt ani blokující nález s ním nemají co dělat — vyžádat review
    /// nad rozbitou větví je legitimní, právě proto se o review žádá.
    enum ReadyObstacle: Hashable, Sendable {
        /// Odesílání není povolené, nebo chybí `gh`. Věta je ta, na které skončí publisher —
        /// tatáž jako u labelů (`Policy.MetadataEditing.blocked`).
        case notAllowed(String)
        /// Nad tímhle PR se právě odesílá něco jiného (label, reviewer, nebo tohle samo).
        case running

        /// Věta do nápovědy pod kurzorem. **Ke každé patří i další krok** tam, kde nějaký je.
        var sentence: String {
            switch self {
            case .notAllowed(let reason): reason
            case .running: "Právě se odesílá něco jiného. Počkej, až to dojde."
            }
        }
    }

    /// Smí se odsud přepnout draft na *ready for review*? Tvarem totéž co `MergeOffer`
    /// a `SyncOffer`, a ze stejného důvodu: na cizím PR (a tady i nad nedraftem) se akce
    /// **nekreslí vůbec**, zašedlá s důvodem patří tam, kde se stav **mění**.
    enum ReadyOffer: Hashable, Sendable {
        case absent
        case blocked([ReadyObstacle])
        case allowed

        var isVisible: Bool { self != .absent }

        var isAllowed: Bool { self == .allowed }

        var obstacles: [ReadyObstacle] {
            if case .blocked(let obstacles) = self { obstacles } else { [] }
        }
    }

    /// Smí se přepnout, a když ne, proč.
    ///
    /// **Stav pull requestu rozhoduje o viditelnosti, ne o zašednutí**, a `nil` (nenačtený
    /// detail) je zákaz: bez hlavičky se neví, jestli je PR draft, a tlačítko, které se objeví
    /// a hned zmizí, je horší než tlačítko, které přijde o průchod později.
    ///
    /// **Běžící odeslání je překážka, ne jen zakázané tlačítko ve view** — tatáž konstrukce jako
    /// `SyncObstacle.running` (#466). Sada labelů i tohle přepnutí jdou touž branou a `AppStore`
    /// druhé odeslání nepustí, takže se to má poznat z nabídky, ne až z kliknutí, které nic
    /// neudělá.
    static func readyForReviewOffer(
        editing: MetadataEditing,
        state: PullRequestState?,
        action: MetadataActionState?
    ) -> ReadyOffer {
        guard editing.isVisible else { return .absent }
        guard state == .draft else { return .absent }

        var obstacles: [ReadyObstacle] = []
        if let reason = editing.reason { obstacles.append(.notAllowed(reason)) }
        if action?.isBusy == true { obstacles.append(.running) }
        return obstacles.isEmpty ? .allowed : .blocked(obstacles)
    }

    /// Které překážky přepnutí si žádají **vlastní větu ve výstraze v panelu**.
    ///
    /// Pravidlo z #392 a #465 říká, že zašedlé tlačítko musí mít důvod **napsaný v panelu**, ne
    /// jen v nápovědě pod kurzorem. Tady vychází výčet **prázdný**, a je to odpověď, ne
    /// opomenutí — rozhoduje se to na jednom místě a `switch` je vyčerpávající schválně, takže
    /// nová překážka si vynutí rozhodnutí při překladu:
    ///
    /// - `notAllowed` je v panelu napsaná **už jednou**, výstrahou mergnutí: vypnutá brána brání
    ///   obojímu, takže `MergeObstacle.notAllowed` nese tutéž větu. Druhá by byla totéž dvakrát
    ///   pod sebou a věta, která se opakuje, se přestane číst.
    /// - `running` je **stav na zlomek sekundy**, který se odklidí sám. Věta v panelu, která
    ///   zmizí bez zásahu, je věta, kterou nikdo nepřečte — a zašednutí je u ní celý vzkaz.
    static func readyWarnings(_ offer: ReadyOffer) -> [ReadyObstacle] {
        offer.obstacles.filter { obstacle in
            switch obstacle {
            case .notAllowed, .running: false
            }
        }
    }

    /// Věta **pod** tlačítkem — a není to dekorace (#482, návrh sekce 37).
    ///
    /// Přepnutí na *ready for review* **vyžádá review od vlastníků kódu**, tedy odešle upozornění,
    /// které se odebráním nevezme zpět. Je to tatáž situace, kterou #392 vyřešilo u `+ reviewer`,
    /// a odpověď zůstává tatáž: **ne sheet, ale sloveso tam, kde se kliká**, plus tahle věta.
    /// Proto je v `Policy` a ne ve view — je součástí rozhodnutí nepotvrzovat sheetem.
    ///
    /// **Je pravdivá i v repu bez `CODEOWNERS`**: když v souboru nikdo nesedí, nikdo se
    /// nevyžádá — věta neslibuje, že se někdo vyžádá, říká, komu to přijde.
    static let readyForReviewNote =
        "Kdo je v CODEOWNERS, dostane vyžádání review. Zpátky do draftu se chodí na GitHub."
}
