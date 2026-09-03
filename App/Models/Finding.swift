import Foundation

/// Nález, jak si ho aplikace pamatuje.
///
/// K tomu, co nahlásil reviewer, přidává dvě věci, které ve streamu nejsou a vědět je může
/// jen aplikace: **kdo** nález našel (skill) a **proti čemu** (`headSha`). To druhé je
/// tvrdá podmínka — nálezy se klíčují head commitem, aby se po nových commitech nezobrazily
/// proti kódu, který už neexistuje.
struct Finding: Hashable, Codable, Sendable {
    let reported: ReportedFinding
    let reviewer: String
    let headSha: String
    /// Texty v jazyce z nastavení. `nil` = nepřekládalo se (reviewer už psal tím jazykem)
    /// nebo se to nepovedlo; pak se ukazuje originál.
    ///
    /// Volitelné i v uloženém tvaru — starší záznamy ho nemají a přijít o ně kvůli novému
    /// poli by znamenalo ztracené nálezy.
    let translation: FindingTranslation?
    /// Hlava, na které nález **vznikl**, když ho sem přenesl přírůstkový běh (#517). `nil`
    /// znamená „našel ho tenhle běh“, tedy dnešní hlava.
    ///
    /// **Tohle je to, čím přírůstkové review nechodí proti tvrdé podmínce č. 5.** `headSha` je
    /// pořád hlava, proti které nález platí — přenesený nález se na dnešní hlavu **přepíše**,
    /// protože ho běh nad dnešním kódem posoudil a řekl, že trvá. Odkud přišel, se ale nesmí
    /// ztratit: bez toho by nešlo poznat, že tu větu napsal reviewer o starším commitu, a číslo
    /// řádku v ní může být z jiné verze souboru.
    ///
    /// Volitelné i v uloženém tvaru, ze stejného důvodu jako `translation`: starší záznamy ho
    /// nemají a přijít o ně kvůli novému poli by znamenalo ztracené nálezy.
    ///
    /// **Do klíče nálezu nepatří** (`Policy.key(of:)`): klíč páruje týž nález napříč běhy, takže
    /// by přenesení nález rozdvojilo — a s ním by se rozpárovalo i odmítnutí (#113).
    let carriedFrom: String?

    init(
        reported: ReportedFinding,
        reviewer: String,
        headSha: String,
        translation: FindingTranslation? = nil,
        carriedFrom: String? = nil
    ) {
        self.reported = reported
        self.reviewer = reviewer
        self.headSha = headSha
        self.translation = translation
        self.carriedFrom = carriedFrom
    }

    /// Přepíše nález na novou hlavu a zapamatuje si, odkud přišel (#517).
    ///
    /// **Původ se nepřepisuje**, když už nález jednou přenesený je: po třech pushnutích má věta
    /// pořád ukazovat na commit, na kterém ji reviewer napsal, ne na předchozí přírůstek.
    /// Překlad se **nechává** — je to zobrazení téže věty, takže se přenesením nemá čím změnit.
    func carried(to headSha: String) -> Finding {
        Finding(
            reported: reported,
            reviewer: reviewer,
            headSha: headSha,
            translation: translation,
            carriedFrom: carriedFrom ?? self.headSha
        )
    }

    var file: String? { reported.file }
    var line: Int? { reported.line }
    var category: String? { reported.category }
    var verdict: FindingVerdict? { reported.verdict }

    // Texty ke zobrazení. Překlad má přednost, ale **po polích**: kdyby překladateli jedno
    // pole vypadlo, je jeden anglický řádek pořád lepší než chybějící text. Ztracená věta
    // se v UI nedá odlišit od věty, kterou reviewer nenapsal.
    var summary: String { translation?.summary ?? reported.summary }
    var failureScenario: String? { translation?.failureScenario ?? reported.failureScenario }
    var shortSummary: String? { translation?.shortSummary ?? reported.shortSummary }
}
