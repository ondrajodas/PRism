import Foundation

/// Zúžení seznamu PR na vybraná repa a autory (#117).
///
/// **Není to `sources` v konfiguraci.** Zdroj je search dotaz — mění, co GitHub vrátí, stojí kolo po
/// síti a je to trvalé nastavení. Filtr je **pohled na výsledek**: lokální, okamžitý a dočasný.
/// Slít to do jednoho by znamenalo, že „ukaž mi teď jen tohle repo“ přepisuje konfiguraci.
///
/// **Není `Codable`** a nepřežije restart, stejně jako `ReviewVerdict` a `PullRequestTab` — viz
/// `AppStore.filter`.
struct PullRequestFilter: Equatable, Sendable {
    /// Repa, která se mají ukázat. **Prázdná množina = bez filtru**, ne „neukazuj nic“.
    ///
    /// Je to obráceně než u prázdného seznamu skillů, kde je prázdno vlastní odpověď
    /// („nereviewuj nic“) — a schválně: filtr, který po prvním spuštění neukazuje nic, je rozbitá
    /// aplikace.
    var repositories: Set<RepoID> = []
    /// Autoři, jejichž PR se mají ukázat. Login z `PullRequestSummary.author`.
    var authors: Set<String> = []

    var isActive: Bool { !repositories.isEmpty || !authors.isEmpty }

    /// Projde tenhle PR filtrem?
    ///
    /// **Uvnitř osy sjednocení, mezi osami průsečík.** Dvě repa znamenají „obojí“, repo + autor
    /// znamená „jeho PR v tomhle repu“ — tak se filtr chová všude jinde.
    func matches(_ pullRequest: PullRequestSummary) -> Bool {
        (repositories.isEmpty || repositories.contains(pullRequest.repo))
            && (authors.isEmpty || authors.contains(pullRequest.author))
    }
}

/// Jedna položka nabídky filtru: hodnota a počet PR, kterých se týká (#199).
///
/// **Počet patří k hodnotě, ne do vedlejší mapy.** Dvě pole, která se musí párovat indexem nebo
/// klíčem, se dřív nebo později rozejdou — a rozejdou se potichu, protože číslo u špatného repa
/// vypadá jako platné.
struct PullRequestFilterOption<Value: Hashable & Sendable>: Equatable, Sendable {
    let value: Value
    /// Kolik PR v **plném** seznamu tuhle hodnotu má. U hodnoty, která v nabídce zbyla jen po
    /// aktivním filtru (její PR zmizel), je to **nula** — a je to ta správná odpověď: říká, že
    /// zapnutí položky neukáže nic.
    let count: Int
}

/// Co nabídnout ve filtru — hodnoty z plného seznamu **sjednocené s aktivním filtrem**, každá
/// s počtem PR, kterých se týká.
struct PullRequestFilterOptions: Equatable, Sendable {
    let repositories: [PullRequestFilterOption<RepoID>]
    let authors: [PullRequestFilterOption<String>]

    var isEmpty: Bool { repositories.isEmpty && authors.isEmpty }
}

/// Proč je seznam prázdný, včetně důvodů, o kterých polling neví.
///
/// Vlastní typ vedle `PollEmptyReason`, ne nový případ v něm: **polling o stavu okna neví a vědět
/// nemá.** Skládá to `AppStore` nad tím, co polling řekl.
enum ListEmptyReason: Equatable, Sendable {
    /// Prázdno z pohledu pollingu — načítá se, nic nepřišlo, nebo se to nepovedlo.
    case poll(PollEmptyReason)
    /// Seznam prázdný **není**, jen ho celý schoval filtr.
    case filtered(hidden: Int)
}

extension Policy {
    /// Seznam zúžený filtrem. Čistá funkce — pořadí se nemění, jen se vybírá.
    ///
    /// **Nesahá na řazení.** Pořadí je od naposledy změněného a je to rozhodnutí z #5.
    static func filtered(
        _ pullRequests: [PullRequestSummary],
        by filter: PullRequestFilter
    ) -> [PullRequestSummary] {
        guard filter.isActive else { return pullRequests }
        return pullRequests.filter(filter.matches)
    }

    /// Co nabídnout ve filtru, včetně počtu PR u každé položky (#199).
    ///
    /// **Skládá se z plného seznamu, ne z vyfiltrovaného** — jinak vybraná hodnota z nabídky zmizí
    /// a filtr se nedá vypnout. Z plného seznamu se počítají i **počty**: ze zúženého by se měnily
    /// podle toho, co je zrovna odškrtané, takže by se z nich nedalo poznat, co zapnutí položky
    /// udělá. Volající to má zadarmo — `AppStore.filterOptions` sem posílá `pullRequests`, ne
    /// `visiblePullRequests`, a nic jiného tuhle funkci nevolá.
    ///
    /// **A sjednocuje se s hodnotami aktivního filtru**, přesně jako `knownRepositories` slučuje
    /// seznam PR s konfigurací: bez toho zmizí odškrtávátko u repa, jehož PR se zavřelo, a filtr
    /// zůstane aktivní bez cesty zpátky. Taková položka má počet **nula**.
    ///
    /// Řadí se podle jména bez ohledu na velikost písmen, se `description` jako druhým kritériem —
    /// množina pořadí nemá, takže bez řazení by nabídka mezi otevřeními poskakovala. **Ne podle
    /// počtu**: pořadí by pak přeskakovalo s každým tikem pollingu a hledalo by se v něm očima.
    static func filterOptions(
        in pullRequests: [PullRequestSummary],
        filter: PullRequestFilter
    ) -> PullRequestFilterOptions {
        PullRequestFilterOptions(
            repositories: options(
                counting: pullRequests.map(\.repo),
                keeping: filter.repositories,
                sortedBy: shouldPrecede
            ),
            authors: options(
                counting: pullRequests.map(\.author),
                keeping: filter.authors,
                sortedBy: shouldPrecede
            )
        )
    }

    /// Jedna osa nabídky: spočítat výskyty, doplnit hodnoty z aktivního filtru nulou a seřadit.
    ///
    /// `Hashable` kvůli tomu počítání ve slovníku, `Sendable` kvůli `PullRequestFilterOptions`.
    private static func options<Value: Hashable & Sendable>(
        counting values: [Value],
        keeping selected: Set<Value>,
        sortedBy shouldPrecede: (Value, Value) -> Bool
    ) -> [PullRequestFilterOption<Value>] {
        var counts: [Value: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        for value in selected where counts[value] == nil { counts[value] = 0 }

        return counts
            .map { PullRequestFilterOption(value: $0.key, count: $0.value) }
            .sorted { shouldPrecede($0.value, $1.value) }
    }

    /// Proč je seznam prázdný.
    ///
    /// **Důvod od pollingu má přednost.** Nad selhaným tikem se hlásí chyba načtení, ne filtr:
    /// „schoval jsem ti to filtrem“ nad daty, která nedorazila, je nepravda — a je to tatáž lekce
    /// jako u `PollEmptyReason`, který kvůli tomu vůbec existuje.
    static func listEmptyReason(
        poll: PollEmptyReason?,
        visible: Int,
        hidden: Int
    ) -> ListEmptyReason? {
        if let poll { return .poll(poll) }
        guard visible == 0, hidden > 0 else { return nil }
        return .filtered(hidden: hidden)
    }

    private static func shouldPrecede(_ left: RepoID, _ right: RepoID) -> Bool {
        shouldPrecede(left.description, right.description)
    }

    /// Řazení jmen: podle abecedy bez ohledu na velikost písmen, při shodě rozhodne přesná podoba,
    /// ať je pořadí úplné a dvě jména lišící se jen velikostí se neprohazují.
    private static func shouldPrecede(_ left: String, _ right: String) -> Bool {
        let byName = left.caseInsensitiveCompare(right)
        if byName != .orderedSame { return byName == .orderedAscending }
        return left < right
    }
}
