import Foundation

/// Sdílí větev předchozí hlava s tou dnešní? (#517)
///
/// **Tři hodnoty, ne dvě.** `unknown` je tam schválně a je to tatáž úvaha jako u `RecheckStatus`:
/// „nedá se to zjistit“ je jiná odpověď než „nesdílí“. Vede sice na totéž rozhodnutí (celé
/// review), ale **jinou větou v okně** — a věta, která tvrdí přepsanou historii tam, kde se
/// jen nepodařilo spustit `git`, tvrdí víc, než data unesou.
enum BranchAncestry: Equatable, Sendable {
    /// Předchozí hlava je předkem té dnešní — přírůstek je přesně to, co se pushlo.
    case ancestor
    /// Není. Historie se přepsala (force push), takže „co přibylo“ by vyšlo na víc než celý
    /// diff PR — změřeno u #284 na `cli/cli#14062`: 102 kB ve 22 souborech proti 15 kB ve třech.
    case rewritten
    /// Nedalo se zjistit: commit už v cache není, nebo `git` neodpověděl.
    case unknown
}

extension Policy {
    /// Poběží tenhle reviewer nad přírůstkem, nebo nad celým diffem? (#517)
    ///
    /// **Rozhoduje se na skill, ne na review.** Dva reviewery nad jedním PR mohou být v jiném
    /// stavu: jeden minule doběhl, druhý spadl — a ten druhý musí projít celý diff, protože nad
    /// předchozí hlavou nic nepřečetl. Jedno rozhodnutí pro celý běh by tu ztrátu udělalo tiše.
    ///
    /// **Podmínky se zkoumají v tomhle pořadí schválně**: co se pozná z uloženého záznamu, se
    /// pozná bez `gitu`. Volající se proto na příbuznost větví ptá až tehdy, když má proti čemu —
    /// a když se neptal, dává `.unknown`, které se v téhle větvi nikdy nečte.
    ///
    /// - Parameters:
    ///   - record: záznam, který o PR máme. `nil` = nic uloženého není.
    ///   - head: hlava, na které PR stojí **teď**.
    ///   - skill: reviewer, o kterém se rozhoduje.
    ///   - ancestry: sdílí předchozí hlava historii s dnešní? Zjišťuje to `RepoCheckout`
    ///     v pracovní kopii, tedy `gitem`, ne z časové osy PR: cesta review konverzaci načtenou
    ///     nemá a `git merge-base --is-ancestor` je na tuhle otázku přímá odpověď.
    ///   - enabled: nastavení `Po pushi review jen přírůstku` (`ResolvedConfig`).
    static func reviewScope(
        record: ReviewRecord?,
        head: String,
        skill: String,
        ancestry: BranchAncestry,
        enabled: Bool
    ) -> ReviewScope {
        guard enabled else { return .whole(.disabled) }
        guard let record, !record.headSha.isEmpty else { return .whole(.firstReview) }
        guard record.headSha != head else { return .whole(.sameHead) }
        guard let run = record.runs.first(where: { $0.skillID == skill }),
              run.outcome == .finished
        else { return .whole(.noFinishedRun) }
        switch ancestry {
        case .rewritten: return .whole(.rewroteHistory)
        case .unknown: return .whole(.unknownAncestry)
        case .ancestor: break
        }
        return .increment(IncrementalDiffRange(seen: record.headSha, head: head))
    }

    /// Nálezy, které se přírůstkovému běhu pošlou jako materiál (#517).
    ///
    /// **Všech reviewerů, ne jen toho, kdo běží** — a je to vědomé: běh, který nevidí, co už na PR
    /// stojí, ohlásí cizí nález jako svůj nový. Posoudit má přesto jen ty své; drží to filtr při
    /// ukládání (`carriedFindings(of:)`), ne jen věta v promptu.
    ///
    /// Bere se `activeFindings`, takže **odmítnuté nálezy** (#113) se neposílají ani nepřenášejí:
    /// odmítnutí je jediné, co nález sundává, a poslat ho zpátky do dalšího kola by ho vzkřísilo.
    ///
    /// Pořadí je pořadí záznamu, protože **index je `id`** v otázce i v odpovědi.
    static func previousFindings(of record: ReviewRecord) -> [Finding] {
        record.activeFindings
    }

    /// Nálezy, které si přírůstkový běh **odnese na novou hlavu** — jen ty svoje (#517).
    ///
    /// Filtr podle revieweera je tu proto, aby jeden nález neskončil v záznamu dvakrát:
    /// `ReviewRecord.findings` je sjednocení běhů, takže kdyby si tutéž větu odnesly dva běhy,
    /// byly by v okně dvě.
    ///
    /// **Přenášejí se všechny, včetně vyřešených** (tvrdá podmínka č. 5 a #113): „vyřešeno“ je
    /// tvrzení modelu, tedy odznak, ne mazání. Nález, ke kterému se běh nevyjádřil, se přenese
    /// taky — nezodpovězený nález je pořád platný nález.
    static func carriedFindings(
        of previous: [Finding],
        by skill: String,
        to head: String
    ) -> [Finding] {
        previous.filter { $0.reviewer == skill }.map { $0.carried(to: head) }
    }

    /// Verdikty z odpovědi spárované na nálezy, na které se ptalo (#517).
    ///
    /// **Přes index, ne přes text**, jako u #150: `id` nese aplikace na obou stranách, takže se
    /// nemá čím rozejít — kdežto věta nálezu se mezi běhy přeformuluje.
    ///
    /// Odpovědi na **cizí** nálezy se zahazují: běh měl posoudit jen ty své a verdikt, který dal
    /// nálezu jiného revieweera, by se v okně objevil u nálezu, o kterém tenhle běh nic nevěděl.
    static func incrementalStatuses(
        _ answers: [Int: RecheckStatus],
        of previous: [Finding],
        by skill: String
    ) -> [FindingKey: RecheckStatus] {
        var statuses: [FindingKey: RecheckStatus] = [:]
        for (index, status) in answers {
            guard previous.indices.contains(index) else { continue }
            let finding = previous[index]
            guard finding.reviewer == skill else { continue }
            statuses[key(of: finding)] = status
        }
        return statuses
    }
}
