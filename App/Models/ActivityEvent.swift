import Foundation

/// Jedna položka **dění** (#414) — co se na pull requestech stalo, když jsem se nekoukal.
///
/// **Záznam, ne odvozený stav.** Notifikace proletí a nikde nezůstane (`DeliveredNotification`
/// drží schválně jen tu poslední, a jen v paměti — #138), takže tohle je to jediné místo, kde se
/// událost dá dohledat zpětně. Bydlí proto **na disku** (`ActivityLog`); je to opačná otázka než
/// u zvonku ve stavovém řádku, který odpovídá na „funguje mi to teď“.
///
/// **Text se ukládá složený, ne skládá při kreslení.** Vypadá to jako uložené UI, ale je to
/// jediná poctivá volba: řádek mluví o tom, jak review dopadlo **tehdy**, a nálezy z té chvíle na
/// disku být nemusí (zahodily se, uklidila je lhůta, přepsal je další běh). Přepočítaný řádek by
/// tvrdil něco o dnešku pod datem z minulého týdne. Skládá ho `Policy` — a **týmiž funkcemi, jaké
/// skládají banner**, takže se dění a notifikace nemají čím rozejít.
struct ActivityEvent: Codable, Hashable, Sendable, Identifiable {
    /// Který druh novinky to je. Rozhoduje o glyfu, barvě puntíku, cíli kliknutí i o tom, jestli
    /// se u řádku kreslí chip `bez banneru` — všechno v `Policy`, vyčerpávajícím výčtem.
    ///
    /// **Sedm druhů, devět případů**: `newPullRequest`/`reReview` a trojice výsledků review jsou
    /// v návrhu (sekce 27) jeden druh se dvěma, resp. třemi podobami, protože se liší glyf i to,
    /// kam řádek vede.
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        /// Ve frontě je PR, který tam nebyl (#85).
        case newPullRequest
        /// PR, který jsem už reviewoval, se ve frontě objevil znovu (#137).
        case reReview
        /// Review dodalo nálezy (#82).
        case findings
        /// Review doběhlo a nezbylo nic k řešení — čisto, nebo jen odmítnuté nálezy.
        case clean
        /// Review se nepovedlo, nedoběhlo, nebo z něj nejde nic tvrdit (#383).
        case failure
        /// Na **vlastním** PR se ozval někdo jiný (#335).
        case foreignActivity
        /// Hlava se posunula pod uloženými nálezy (tvrdá podmínka č. 5). **Dopočítané** — banner
        /// za to nechodí, protože zastaralé nálezy nemají vyrušovat; dohledat se ale mají.
        case staleFindings
        /// PR z fronty odešel. **Dopočítané** — doplněk k `newcomers(in:)` nad tímtéž snímkem.
        case leftQueue
        /// PR se vrátil z odložení (#512). **Dopočítané** — banner za něj nechodí: vrácení do
        /// fronty jsem si objednal já, takže vyrušit nemá, jen se má dát dohledat. Bez tohohle
        /// řádku by se PR ve frontě objevil odnikud.
        case returnedFromSnooze
    }

    /// Identita položky. **Deterministická, ne `UUID`**: skládá ji `Policy` z druhu, PR a toho, co
    /// tu příhodu odlišuje od stejné příhody jinde v čase — u zastaralých nálezů je to **hlava**,
    /// u zbytku okamžik. Na tom stojí odstranění duplikátů: `staleFindings` si aplikace všimne
    /// pokaždé, když dotáhne detail téhož PR, kdežto dvě doběhlá review v tomtéž okamžiku jsou
    /// jedna věc. `UUID` by z každého všimnutí udělalo řádek.
    let id: String
    let kind: Kind
    let pullRequest: PRIdentifier
    /// Kdy se to stalo. U dopočítaných druhů je to okamžik, kdy si toho aplikace všimla — dřív se
    /// o nich neví a vymýšlet datum zpětně by znamenalo tvrdit, co v datech není.
    let at: Date
    /// Tlustý začátek řádku — to, podle čeho se pozná, jestli jít k počítači.
    let headline: String
    /// Zbytek řádku za tečkou. `nil` = není co dodat; prázdný `·` by vypadal jako uříznutý text.
    let detail: String?
    /// Dorazil o tom banner?
    ///
    /// `false` u druhu, který banner umí, znamená chip **bez banneru** — a to je půlka hodnoty
    /// téhle obrazovky: „nepřišlo mi to“ má na ní odpověď. U dopočítaných druhů se chip nekreslí
    /// (banner za ně nechodí nikdy), rozhoduje `Policy.showsSilentChip(_:announced:)`.
    let wasAnnounced: Bool
    /// Hlava, na které PR stojí teď — jen u `staleFindings`, kde se kreslí jako pilulka se sha.
    var head: String?
    /// Autor PR — jen u příchodu do fronty (`newPullRequest`, `reReview`), jak to kreslí návrh.
    ///
    /// **Jen tam schválně**: u příchodu je autor půlka informace („kdo na mě čeká“), kdežto
    /// u výsledku review nebo u zastaralých nálezů o té události neříká nic a v řádku by jen
    /// ukrajoval místo textu, který ji popisuje.
    var author: String?

    init(
        id: String,
        kind: Kind,
        pullRequest: PRIdentifier,
        at: Date,
        headline: String,
        detail: String? = nil,
        wasAnnounced: Bool = false,
        head: String? = nil,
        author: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.pullRequest = pullRequest
        self.at = at
        self.headline = headline
        self.detail = detail
        self.wasAnnounced = wasAnnounced
        self.head = head
        self.author = author
    }
}

/// Kam řádek dění vede (#414).
///
/// **Cíl je napsaný v každém řádku**, ne šipka bez obsahu — a jde se **jednou** cestou, tou samou,
/// jakou musí jít i klik na notifikaci (#409). Novinka, která nikam nevede, je nakreslená chyba.
enum ActivityDestination: Hashable, Sendable {
    /// Otevřít záložku PR a v ní tenhle tab.
    case tab(PullRequestTab)
    /// Otevřít PR v prohlížeči. **Jediný řádek, který do okna nevede** — PR, který z fronty
    /// odešel, v seznamu není, takže zašedlá šipka `→ Nálezy` by lhala.
    case gitHub
}

/// Barva puntíku na ose dění. Návrh (sekce 27) jich kreslí pět a každá znamená něco jiného, takže
/// se nesmí slít — `čisté review` a `review se nepovedlo` je tentýž pár jako všude jinde v okně.
enum ActivityTone: Hashable, Sendable {
    case neutral
    case ok
    case critical
    case stale
    case accent
}
