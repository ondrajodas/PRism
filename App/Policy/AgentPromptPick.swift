import Foundation

/// Grupa v seznamu položek (#377) — **čtyři druhy obsahu, ne sedm voleb panelu.**
///
/// Vyřešené vlákno leží mezi vlákny a odmítnutý nález mezi nálezy, jen vypnuté a s důvodem:
/// vlastní grupa `Vyřešená vlákna` by tvrdila, že je to jiný druh materiálu, a přitom je to totéž
/// vlákno v jiném stavu. Sedm grup by navíc znamenalo sedm hlaviček s počty nad seznamem, ve
/// kterém jsou tři položky.
///
/// Pořadí je z návrhu (sekce 23): nálezy, vlákna u řádků, souhrny review, komentáře pod PR. Vede
/// od toho, co má místo v kódu, k tomu, co platí pro celé PR — tedy obráceně než sekce v textu,
/// kde obecné stojí první (`Policy.agentPromptSections`). Je to schválně: v textu se čte odshora
/// a obecné rozhodnutí je kontext pro to ostatní, kdežto v seznamu se **vybírá** a začíná se od
/// toho, co po mně někdo chce nejkonkrétněji.
enum AgentPromptKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case findings
    case threads
    case reviews
    case comments

    var id: String { rawValue }

    /// Hlavička grupy (`.pickgroup` z návrhu).
    var title: String {
        switch self {
        case .findings: "Nálezy"
        case .threads: "Vlákna u řádků"
        case .reviews: "Souhrny review"
        case .comments: "Komentáře pod PR"
        }
    }
}

/// Jeden řádek seznamu položek (#377) — položka, jestli je v textu, a proč ne.
///
/// Nese **položku, ne opsané řetězce** (tatáž úvaha jako u `AgentPromptItem`): popisky jsou
/// počítané vlastnosti, takže se sazba řádku dá změnit bez zásahu do výběru a hodnota zůstane
/// levná na porovnání.
struct AgentPromptPick: Hashable, Sendable, Identifiable {
    let item: AgentPromptItem
    /// Je položka v textu zadání? Rozhoduje `Policy.agentPromptIncludes(_:options:conversation:toggled:)`.
    let isIncluded: Bool
    /// Proč není. `nil` u zapnuté položky **i u té, kterou jsem odškrtnul rukou** — na ruční
    /// odškrtnutí se nepíše důvod, protože ho znám: byl jsem to já.
    let exclusion: AgentPromptExclusion?
    /// Blokuje (`Policy.isBlockingItem`)? Drží se jako hodnota, protože kategorie zná jen ten, kdo
    /// seznam skládá — řádek by si je neměl kde vzít.
    let isBlocking: Bool
    /// Autor do sloupce `.who` — u nálezu **zkrácené jméno revieweera** (#182), jinak ten, kdo to
    /// napsal.
    ///
    /// Jediná hodnota, kterou si pick nese opsanou, a je to schválně: zkrácení se rozhoduje nad
    /// **celou sadou** reviewerů (`Policy.shortReviewerNames(of:)`), protože zkrátit se smí jen to,
    /// co po zkrácení zůstane jednoznačné — a to jedna položka o sobě nepozná.
    let author: String

    var id: String { item.id }

    /// Titulek řádku (`.t1`) — text položky **na jeden řádek**, u blokujícího nálezu s `— BLOKUJE`.
    ///
    /// Krátí se sazbou (`lineLimit(1)`), ne tady: co se do řádku nevejde, se ukáže celé v rozkliku.
    var title: String {
        switch item {
        case .finding(let finding, _):
            return finding.summary.singleLine + (isBlocking ? " — BLOKUJE" : "")
        case .thread(let thread):
            return (thread.comments.items.first?.body ?? "(text vlákna nedorazil)").singleLine
        case .comment(let comment):
            return comment.body.singleLine
        // Souhrn bez prózy má v seznamu **stav místo textu**: prázdný řádek by vypadal jako
        // ztracená položka, a schválení bez komentáře je čtvrtina vzorku (`cli/cli#11451`).
        case .review(let review):
            let body = review.body.singleLine
            return body.isEmpty ? (review.state?.czechLabel ?? "souhrn review bez stavu") : body
        }
    }

    /// `soubor:řádek` (`.t2`). `nil` u položky, která místo v kódu **nemá** — komentář pod PR
    /// a souhrn review. Psát u nich `bez řádku` by bylo tvrzení o něčem, co mít nemají.
    var place: String? {
        guard let file = item.file else { return nil }
        guard let line = item.line else { return file }
        return "\(file):\(line)"
    }

    /// Druh do hlavičky rozkliku — u souhrnu review i se stavem, protože ten je jeho obsah.
    var kindLabel: String {
        switch item {
        case .finding: "nález"
        case .thread(let thread): thread.isResolved ? "vyřešené vlákno u řádku" : "vlákno u řádku"
        case .comment: "komentář pod PR"
        case .review(let review): review.state.map { "souhrn review — \($0.czechLabel)" } ?? "souhrn review"
        }
    }

    /// Celý text položky — **tentýž, jaký jde do zadání** (`Policy.agentPromptItemText`).
    ///
    /// Ne zkrácený náhled: rozklik je tu proto, aby se dalo posoudit, co se předává, a druhý
    /// zkrácený pohled na tentýž problém by k tomu nepomohl. Dlouhý text se v sazbě **roluje**.
    var text: String { Policy.agentPromptItemText(of: item) }

    /// Hlavička rozbaleného textu — `druh · autor · čas · velikost`.
    ///
    /// Čas se vynechá, když ho položka nemá: nález datum nenese (klíčuje se `headSha`, tvrdá
    /// podmínka č. 5) a rozdělané review datum odeslání nemá. `dnes 14:20` by u nálezu byla
    /// vymyšlená hodnota.
    var meta: String {
        var parts = [kindLabel, author]
        if let date = item.date {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(text.utf8.count.formatted(.byteCount(style: .file)))
        return parts.joined(separator: " · ")
    }
}

/// Grupa seznamu s počtem vybraných (#377).
struct AgentPromptGroup: Hashable, Sendable, Identifiable {
    let kind: AgentPromptKind
    let picks: [AgentPromptPick]

    var id: String { kind.rawValue }

    /// Kolik z nich je v textu.
    var selected: Int { picks.count { $0.isIncluded } }

    /// `2 z 3` do hlavičky grupy. **Vždycky obojí**, i když jde všechno: `3` samo o sobě neřekne,
    /// jestli je to počet vybraných, nebo počet položek — a zrovna tenhle rozdíl je celé issue.
    var countLabel: String { "\(selected) z \(picks.count)" }
}

/// Jak je položka v seznamu rozbalená (#377).
enum AgentPromptPickDisclosure: Hashable, Sendable {
    /// Celý text i s hlavičkou.
    case expanded
    /// Jeden řádek se šipkou.
    case collapsed
    /// **Rozbalit není co** — položka žádný text nenese (schválení s prázdným tělem). Šipka se
    /// u ní nekreslí: kliknutí, po kterém se nic nestane, je k nerozeznání od rozbité aplikace.
    case none
}

/// Zadání a **seznam, ze kterého vzniklo** (#377).
///
/// Jedna hodnota z jednoho volání schválně: text i seznam se musí ptát téže funkce, jinak by
/// hlavička tvrdila „vybráno 6 z 11“ nad textem, ve kterém je položek pět. Přesně na to je
/// v testech tvrzení, které se dá pokazit potichu.
struct AgentPromptSelection: Hashable, Sendable, Identifiable {
    let prompt: AgentPrompt
    let groups: [AgentPromptGroup]
    /// Zúžení materiálu, se kterým sheet vznikl (`Sestavit i tak (jen nové vlákno)`, #334).
    /// `nil` = celé zadání.
    ///
    /// Drží se tady, protože se podle něj **přeskládává** po kliknutí v seznamu: bez toho by se
    /// zúžený sheet po prvním odškrtnutí rozrostl na celé zadání.
    let only: Set<String>?

    /// Identita sheetu — pull request a hlava, proti které zadání vzniklo. Ne obsah: sheet je
    /// snímek, který se otevře jedním kliknutím a zavře druhým.
    var id: String { prompt.id }

    /// Kolik položek je vybraných a kolik jich je k dispozici — obojí z **jednoho** seznamu.
    var selected: Int { groups.reduce(0) { $0 + $1.selected } }
    var available: Int { groups.reduce(0) { $0 + $1.picks.count } }
}

extension Policy {
    /// Jak je položka v seznamu rozbalená (#377).
    ///
    /// Rozhodnutí patří sem, ne do `@State` view — tatáž úvaha jako u `Policy.disclosure`
    /// u bublin (#185): je to odpověď na „co se z položky ukáže“, a ta se dá pokazit potichu
    /// (šipka nad prázdným textem, rozbalená položka bez hlavičky). Množinu rozbalených si drží
    /// sheet, protože **zaniká s ním**: výběr ani rozbalení nemají přežít zavření (viz
    /// `AgentPromptSheet`).
    static func pickDisclosure(of pick: AgentPromptPick, toggled: Set<String>) -> AgentPromptPickDisclosure {
        guard !pick.text.isEmpty else { return .none }
        return toggled.contains(pick.id) ? .expanded : .collapsed
    }

    /// Položky rozdělené do grup po druzích (#377) — s tím, které jsou v textu a proč ne.
    ///
    /// Prázdná grupa se **nekreslí**: hlavička `Souhrny review 0 z 0` slibuje seznam, ve kterém
    /// nic není.
    static func agentPromptGroups(
        _ items: [AgentPromptItem],
        options: AgentPromptOptions,
        conversation: Conversation?,
        toggled: Set<String> = [],
        blocking: Set<String> = defaultBlockingCategories
    ) -> [AgentPromptGroup] {
        // Zkrácená jména reviewerů se rozhodují nad **celou** sadou (#182): `code-review:code-review`
        // se v sloupci autora zkrátí jedině tehdy, když se tím nesrazí s jiným skillem.
        let reviewers = shortReviewerNames(of: items.compactMap(\.reviewer))
        let picks = items.map { item in
            AgentPromptPick(
                item: item,
                isIncluded: agentPromptIncludes(
                    item,
                    options: options,
                    conversation: conversation,
                    toggled: toggled
                ),
                exclusion: toggled.contains(item.id)
                    ? nil
                    : agentPromptExclusion(of: item, options: options, conversation: conversation),
                isBlocking: isBlockingItem(item, categories: blocking),
                author: author(of: item, reviewers: reviewers)
            )
        }
        let grouped = Dictionary(grouping: picks) { $0.item.kind }
        return AgentPromptKind.allCases.compactMap { kind in
            guard let picks = grouped[kind], !picks.isEmpty else { return nil }
            return AgentPromptGroup(kind: kind, picks: sortedPicks(picks))
        }
    }

    /// Kdo za položkou stojí. Podle toho se v seznamu pozná, co je signál: „Copilot“ a jméno
    /// kolegy vedle sebe se čtou jinak než dva stejné řádky bez jména.
    private static func author(of item: AgentPromptItem, reviewers: [String: String]) -> String {
        switch item {
        case .finding(let finding, _): reviewers[finding.reviewer] ?? finding.reviewer
        case .thread(let thread): thread.comments.items.first?.author ?? "neznámý autor"
        case .comment(let comment): comment.author
        case .review(let review): review.author
        }
    }

    /// Uvnitř grupy se řadí **stejně jako v textu**: podle souboru a řádku, položky bez místa
    /// první, při shodě podle identity. Dvě pořadí týchž položek by znamenala, že se seznam
    /// v sheetu čte jinak než text pod ním.
    private static func sortedPicks(_ picks: [AgentPromptPick]) -> [AgentPromptPick] {
        picks.sorted { left, right in
            let leftFile = left.item.file ?? "", rightFile = right.item.file ?? ""
            guard leftFile == rightFile else { return leftFile < rightFile }
            switch (left.item.line, right.item.line) {
            case (let leftLine?, let rightLine?) where leftLine != rightLine: return leftLine < rightLine
            case (nil, .some): return true
            case (.some, nil): return false
            default: return left.id < right.id
            }
        }
    }
}
