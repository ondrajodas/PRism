import Foundation

/// Přírůstkové review, jak si ho aplikace pamatuje (#517).
///
/// Leží **u běhu, který nad přírůstkem běžel** (`StoredReviewRun.increment`), ne u nálezů starší
/// hlavy jako `StoredRecheck`. Je to rozdíl, ne nekonzistence: kontrola (#150) je tvrzení **o
/// nálezech ze staršího commitu** a nic nového nepřináší, kdežto tohle je běh review nad dnešní
/// hlavou — má nálezy, cenu, osu i session id, tedy všechno, co má běh. Verdikty o starých
/// nálezech jsou jeho druhý výstup.
///
/// Nálezy z minula se ukládají **jako nálezy toho běhu** (s `Finding.carriedFrom`), ne sem: jsou
/// to nálezy, které na dnešní hlavě platí, takže musí být tam, odkud je čte tab `Nálezy`, návrh
/// verdiktu i řádek seznamu. Tady zůstává jen to, co o nich ten běh **řekl**.
struct StoredIncrementalReview: Hashable, Codable, Sendable {
    /// Hlava, od které se přírůstek počítal — commit předchozího review.
    ///
    /// Druhá polovina rozsahu je `ReviewRecord.headSha`, tedy hlava, na které běh běžel. Držet ji
    /// i tady by znamenalo dvě kopie jedné pravdy: kdyby se rozešly, ukazoval by `Průběh` rozsah,
    /// který nikdy neběžel.
    let fromHeadSha: String
    /// Co běh řekl o nálezech z minula. Klíč skládá `Policy.key(of:)` — **nikde jinde**.
    ///
    /// Nálezy bez odpovědi tady **nejsou** a neukládá se ani jejich počet: spočítá se proti
    /// nálezům běhu (`Policy.incrementalTally`), a to je jediné číslo, které odpovídá tomu, co je
    /// v okně vidět — uložený počet by po odmítnutí nálezu (#113) přestal platit.
    let statuses: [FindingKey: RecheckStatus]
    /// Co stál **celý** běh z prvního kola, aby se cena přírůstku dala k něčemu srovnat (#517).
    ///
    /// `nil` znamená „nevíme“, ne nula — stejná úmluva jako u `RunUsage` samotné. Nese se s tímhle
    /// záznamem schválně: záznam předchozí hlavy z cache odejde (eviction, úklid po zavřeném PR)
    /// a věta o ceně by pak tiše ztratila druhou polovinu.
    let wholeUsage: RunUsage?
    /// Dostal běh nálezy z minula k posouzení? `false` = **nezeptali jsme se** (soubor
    /// s materiálem se nepodařilo uložit), ne „neodpověděl“ — viz `IncrementalReviewOutcome`.
    ///
    /// **Není to spočítatelné z `statuses`**: prázdná mapa vznikne i tak, že běh odpověď poslal
    /// v podobě, která se nepřečetla. Držet se to proto musí, ne odvozovat.
    let askedForVerdicts: Bool

    init(
        fromHeadSha: String,
        statuses: [FindingKey: RecheckStatus],
        wholeUsage: RunUsage? = nil,
        askedForVerdicts: Bool = true
    ) {
        self.fromHeadSha = fromHeadSha
        self.statuses = statuses
        self.wholeUsage = wholeUsage
        self.askedForVerdicts = askedForVerdicts
    }

    init(_ outcome: IncrementalReviewOutcome) {
        fromHeadSha = outcome.range.seen
        statuses = outcome.statuses
        wholeUsage = outcome.wholeUsage
        askedForVerdicts = outcome.askedForVerdicts
    }
}
