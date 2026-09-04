import Foundation

/// Jakou metodou se merguje vlastní PR (#556).
///
/// **Do #556 to byla konstanta `MergeRequest.method`** a u ní stálo zdůvodnění, že volba mezi
/// metodami by byla „třetí věc na potvrzení, kterou člověk projde jednou za rok, a přepnout ji jde
/// na GitHubu“. **Praxe to vyvrátila**: odejít z okna kvůli jedné hodnotě je dražší než ta hodnota,
/// a squash není to, co se hodí ve všech repech — firemní repo s prořezanou historií chce merge
/// commit. Zdůvodnění se tedy **přepsalo, ne smazalo**: záznam rozhodnutí je to, co dovoluje
/// pozdější korekci, takže je z něj poznat, že tohle je korekce, ne opomenutí.
///
/// `rawValue` je **doslova to, co bere GitHub** v `merge_method` — a je to tatáž hodnota, která
/// leží v `config.json`. Dvě tabulky (jedna pro API, druhá pro soubor) by se rozešly a rozdíl by
/// se poznal až z odmítnutého merge.
enum MergeMethod: String, Codable, Hashable, Sendable, CaseIterable {
    /// Slije commity do jednoho. **Výchozí hodnota**, protože tak se aplikace chovala do #556 —
    /// po zavedení pole se nesmí začít chovat jinak.
    case squash
    /// Vytvoří merge commit a historii větve zachová.
    case mergeCommit = "merge"
    /// Přehraje commity nad základem. **Žádný commit nevzniká**, takže se u ní neposílá titulek.
    case rebase

    /// Jak se jmenuje v okně. `merge commit` je **dvě slova schválně** — `merge` samo by se
    /// v nabídce vedle `squash` a `rebase` čtlo jako „mergnout“, tedy jako akce, ne jako metoda.
    var displayName: String {
        switch self {
        case .squash: "squash"
        case .mergeCommit: "merge commit"
        case .rebase: "rebase"
        }
    }

    /// Vzniká z téhle metody commit, kterému se dá nastavit titulek?
    ///
    /// **U rebase ne**, a z toho plyne, že se `commit_title` neposílá: bylo by to pole, které
    /// GitHub zahodí, a potvrzení by slibovalo titulek, který se nikde neobjeví.
    var makesCommit: Bool { self != .rebase }
}

/// Odkud GitHub skládá **tělo** commitu, když ho aplikace neposílá.
///
/// Hodnoty jsou z `squash_merge_commit_message` a `merge_commit_message` v odpovědi
/// `GET /repos/{owner}/{repo}`. Aplikace `commit_message` **neposílá u žádné metody** (v tomhle
/// repu je v tělech slévaných commitů zdůvodnění změny a prázdné tělo by ho zahodilo), takže je
/// tohle jediné, z čeho se dá říct, co v tom těle doopravdy bude.
///
/// **Do #556 to potvrzení hádalo**: stála v něm věta „Tělo squash commitu složí GitHub ze zpráv
/// N commitů“, což je pravda jedině v repu s `COMMIT_MESSAGES`. Tenhle repo ho má (změřeno), ale
/// záruka to není — v repu s `PR_BODY` ta věta lhala.
enum MergeBodySource: String, Codable, Hashable, Sendable {
    /// Popis pull requestu.
    case pullRequestBody = "PR_BODY"
    /// Titulek pull requestu.
    case pullRequestTitle = "PR_TITLE"
    /// Zprávy slévaných commitů. **Jen u squashe** — `merge_commit_message` tuhle hodnotu nemá.
    case commitMessages = "COMMIT_MESSAGES"
    /// Prázdno.
    case blank = "BLANK"
}

/// Co repozitář o mergi říká (#556) — **čtení, ne nastavení aplikace**.
///
/// Přijde **jedním voláním** `GET /repos/{owner}/{repo}` (změřeno 0,62 s), takže se povolené
/// metody i zdroje těla dozvíme naráz. Kdyby to byla dvě volání, mohla by se rozejít: nabídka by
/// pustila metodu, o jejímž těle by věta pod výpisem tvrdila něco z druhé odpovědi.
///
/// **`nil` u příznaku znamená „nevím“, ne „nepovoluje“**, a je to změřené: nad repem bez práva
/// zápisu (`cli/cli`) GitHub **všech pět polí vůbec nepošle** — klíče v odpovědi nejsou. Tvrdit
/// z chybějících dat, že něco nejde, je u nevratné akce tatáž chyba jako tvrdit, že jde — takže se
/// v tom stavu nabízejí všechny tři a věta o těle se přizná.
struct RepositoryMergeSettings: Hashable, Sendable {
    /// `allow_merge_commit`.
    let allowsMergeCommit: Bool?
    /// `allow_squash_merge`.
    let allowsSquash: Bool?
    /// `allow_rebase_merge`.
    let allowsRebase: Bool?
    /// `squash_merge_commit_message`.
    let squashBody: MergeBodySource?
    /// `merge_commit_message`.
    let mergeCommitBody: MergeBodySource?

    init(
        allowsMergeCommit: Bool? = nil,
        allowsSquash: Bool? = nil,
        allowsRebase: Bool? = nil,
        squashBody: MergeBodySource? = nil,
        mergeCommitBody: MergeBodySource? = nil
    ) {
        self.allowsMergeCommit = allowsMergeCommit
        self.allowsSquash = allowsSquash
        self.allowsRebase = allowsRebase
        self.squashBody = squashBody
        self.mergeCommitBody = mergeCommitBody
    }

    /// Pustí repozitář tuhle metodu? `nil` = nevím.
    ///
    /// **Odpověď se nesráží na `Bool`** — kdo se ptá, musí ten třetí stav vidět, protože „nevím“
    /// vede v nabídce jinam než „nepovoluje“ (nabídne se, jen se nic netvrdí).
    func allows(_ method: MergeMethod) -> Bool? {
        switch method {
        case .squash: allowsSquash
        case .mergeCommit: allowsMergeCommit
        case .rebase: allowsRebase
        }
    }

    /// Odkud se u téhle metody vezme tělo. `nil` = nevím, u rebase **žádné tělo není**.
    func bodySource(for method: MergeMethod) -> MergeBodySource? {
        switch method {
        case .squash: squashBody
        case .mergeCommit: mergeCommitBody
        case .rebase: nil
        }
    }
}
