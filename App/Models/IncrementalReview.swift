import Foundation

/// Nad čím tenhle běh review poběží (#517).
///
/// **Model, ne typ v `Policy`**, a je to tentýž důvod jako u `IntentGap` (#345): rozhodnutí jde do
/// **osy běhu** (`ReviewerTimeline.Entry`), takže musí být `Codable` a přežít restart — kapsle
/// `přírůstek` i věta o tom, proč se šlo na celý diff, mají v `Průběhu` stát i po startu aplikace.
/// Skládá ho `Policy.reviewScope`, a nikdo jiný.
///
/// **Přírůstek není sleva, je to jiná otázka.** Celé review se ptá „je tenhle PR v pořádku“,
/// přírůstkové „je v pořádku to, co se od minula pushlo, a co ze starých nálezů trvá“.
/// Rozhoduje o tom `Policy`, protože je to rozhodnutí nad daty, ne skládání věty — a protože
/// se za každou odpověď platí session.
enum ReviewScope: Hashable, Codable, Sendable {
    /// Celý diff PR, jako do #517. Nese **proč**, aby se to dalo napsat do okna.
    case whole(WholeReason)
    /// Jen to, co od minula přibylo.
    case increment(IncrementalDiffRange)

    /// Proč se jde na celé review.
    ///
    /// Vyjmenované schválně: „přírůstek se nedal ohraničit“ a „nikdo o něj nestojí“ vedou na
    /// tentýž běh, ale znamenají něco jiného, a v `Průběhu` se od sebe musí poznat. Zvlášť
    /// `rewroteHistory` — od #466 umí aplikace přetlačit vlastní větev, takže se to bude dít.
    enum WholeReason: String, Hashable, Codable, Sendable, CaseIterable {
        /// Nastavení `Po pushi review jen přírůstku` je vypnuté.
        case disabled
        /// Na téhle hlavě ještě nic neproběhlo, takže není od čeho odpočítávat.
        case firstReview
        /// Uložený běh je z **téhle** hlavy — nic se nepushlo, takže by přírůstek byl prázdný.
        case sameHead
        /// Tenhle reviewer nad předchozí hlavou **nedoběhl** (spadl, vytimeoutoval, nebo tam
        /// nikdy nebyl). Přírůstek by přeskočil kód, který nikdo nečetl — a potichu.
        case noFinishedRun
        /// Historie se přepsala (force push), takže společná část není.
        case rewroteHistory
        /// Nepodařilo se zjistit, jestli je společná historie. Bezpečná strana je celé review.
        case unknownAncestry
    }

    /// Rozsah, když je to přírůstek. `nil` u celého review — a je to jediné místo, kde se
    /// z rozhodnutí čte rozsah, takže se nemůže vzít u běhu, který jede nad celým diffem.
    var increment: IncrementalDiffRange? {
        guard case .increment(let range) = self else { return nil }
        return range
    }

    /// Proč se šlo na celý diff. `nil` u přírůstku.
    var wholeReason: WholeReason? {
        guard case .whole(let reason) = self else { return nil }
        return reason
    }

    /// Má se v `Průběhu` říct, **proč** se šlo na celý diff?
    ///
    /// Jen u těch tří důvodů, kde by člověk přírůstek čekat mohl a nedostal ho: reviewer bez
    /// doběhlého běhu, přepsaná historie a nezjištěná příbuznost. U vypnutého nastavení, prvního
    /// kola a téže hlavy není co vysvětlovat — a věta *celý diff, protože je to první kolo* u každé
    /// dráhy prvního review je jen šum, ve kterém by se ty tři důležité ztratily.
    var saysWhyWhole: Bool {
        switch self {
        case .increment: false
        case .whole(let reason):
            switch reason {
            case .disabled, .firstReview, .sameHead: false
            case .noFinishedRun, .rewroteHistory, .unknownAncestry: true
            }
        }
    }

    /// Patří tohle rozhodnutí do osy běhu?
    ///
    /// Přírůstek ano (nese kapsli a rozsah) a k tomu ty tři vysvětlované důvody. Zbytek do osy
    /// **nepatří**: „celý diff, protože je to první kolo“ je stav, ve kterém aplikace běžela do
    /// #517, a událost o něm by přidala řádek do každé osy každého prvního review.
    var belongsInTimeline: Bool { increment != nil || saysWhyWhole }
}

/// Co přineslo review **jen přírůstku** (#517) — vedle nálezů, které reviewer nahlásil sám.
///
/// Po pushi se reviewer neptá znovu na celý diff: dostane rozsah `<minulá hlava>…<hlava>`
/// a k němu nálezy z minula jako materiál v souboru (#120). Z jednoho běhu tak vypadnou dvě
/// věci — **nové** nálezy v přírůstku (přes `ReportFindings`, jako u každého review) a **verdikty
/// o starých** (posledním sdělením, jako u kontroly nálezů, #150).
///
/// **Není to `StreamSummary` ani nález.** Verdikt o nálezu není nález a nálezy z minula nejsou
/// tvrzení tohohle běhu o kódu — jsou to věty z minulého kola, které tenhle běh jen posoudil.
/// Proto to sedí vedle `summary` a ne v ní.
struct IncrementalReviewOutcome: Hashable, Sendable {
    /// Rozsah, nad kterým běh běžel. `seen` je hlava předchozího review, `head` hlava dnešní.
    let range: IncrementalDiffRange
    /// Nálezy z minula **přepsané na dnešní hlavu** (tvrdá podmínka č. 5) i s odkazem na původ
    /// (`Finding.carriedFrom`).
    ///
    /// **V pořadí, ve kterém se na ně prompt ptal**: index je `id` v otázce i v odpovědi, takže
    /// se párování nemá čím rozejít s tím, co se posílalo — tatáž úvaha jako u #150.
    ///
    /// Jsou tu **všechny**, i ty, které běh označil za vyřešené: sundat nález smí jedině
    /// odmítnutí člověkem (#113), takže „vyřešeno“ je odznak, ne mazání.
    let carried: [Finding]
    /// Verdikty o nálezech z minula. Klíč skládá `Policy.key(of:)` — **nikde jinde**.
    ///
    /// Co v mapě není, je nález, ke kterému se běh nevyjádřil. Nedopočítává se: „nevyjádřil se“
    /// je vlastní odpověď a v okně je vidět jako `bez odpovědi`.
    let statuses: [FindingKey: RecheckStatus]
    /// Co stál **celý** běh, ze kterého tenhle přírůstek vychází (1. kolo). `nil` = nevíme —
    /// starý záznam cenu nenesl, nebo ji session nenahlásila.
    ///
    /// Nese se **s přírůstkem**, ne dohledává z minulého záznamu: záznam předchozí hlavy z cache
    /// odejde (eviction, úklid po zavřeném PR) a věta „přírůstek stál 0,12 $ proti 0,82 $“ by pak
    /// tiše ztratila druhou polovinu.
    let wholeUsage: RunUsage?
    /// Dostal běh nálezy z minula doopravdy k posouzení?
    ///
    /// **`false` znamená „nezeptali jsme se“, ne „neodpověděl“**, a je to jediné, čím se ty dva
    /// stavy dají rozeznat: soubor s materiálem se nepodařilo uložit (`CacheTextFile.write`
    /// selhal), takže verdikty nechyběly modelu, ale otázce. Bez toho by v okně stálo
    /// `N bez odpovědi` nad během, kterému nikdo nic nedal — tedy text, který tvrdí něco o modelu.
    ///
    /// U kola, ve kterém z minula nebylo co nést, je `false` **beze následku**: přenesených nálezů
    /// je nula, takže se o nich nic netvrdí.
    let askedForVerdicts: Bool

    init(
        range: IncrementalDiffRange,
        carried: [Finding],
        statuses: [FindingKey: RecheckStatus],
        wholeUsage: RunUsage? = nil,
        askedForVerdicts: Bool
    ) {
        self.range = range
        self.carried = carried
        self.statuses = statuses
        self.wholeUsage = wholeUsage
        self.askedForVerdicts = askedForVerdicts
    }
}
