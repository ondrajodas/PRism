import Foundation

/// Výsledky review jednoho PR na jednom commitu — přesně to, co leží v jednom souboru.
///
/// Klíčem je `(PR, headSha)`, ne PR samotné. Nálezy visí na commitu, takže záznam pro
/// starší commit se nesmí tvářit jako aktuální — od toho je `isStale`.
struct ReviewRecord: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    let headSha: String
    /// Jeden běh na skill. Opakované review stejným skillem předchozí přepíše.
    var runs: [StoredReviewRun]
    /// Nálezy patří staršímu commitu, než jaký PR má teď.
    ///
    /// Uložené, ne odvozené: odvodit by to šlo jen porovnáním s aktuálním `headSha`, jenže
    /// ten aplikace z vyhledávání **nedostane** (`gh search prs` ho neumí, viz #4). Zjistí
    /// ho teprve ve chvíli, kdy si dotáhne detail — a to je právě chvíle, kdy se tenhle
    /// příznak nastaví.
    var isStale: Bool
    /// Kdy PR poprvé zmizel ze sledovaného seznamu. `nil` znamená, že ho pořád vidíme.
    ///
    /// Od toho okamžiku běží lhůta, po které záznam zmizí. Kdyby se místo něj počítalo
    /// stáří záznamu, PR otevřený půl roku by o historii přišel hned, jak se zavře.
    var closedAt: Date?
    /// Nálezy, které jsem posoudil jako falešně pozitivní (#113). Klíčem je
    /// `Policy.key(of:)`.
    ///
    /// Bydlí to **na záznamu, ne na `Finding`u**, kvůli `replace(_:)`: opakované review týmž
    /// skillem celý `StoredReviewRun` přepíše, takže označení uvnitř nálezu by zmizelo právě
    /// v tu chvíli, kdy se stejný falešný nález vrátí. Vedle toho `Finding.reported` je věta
    /// revieweera — můj názor na ni je jiná vrstva.
    ///
    /// Čte a mění se přes `activeFindings` a `setDismissal(_:of:)`, viz
    /// `App/Policy/FindingDismissalPolicy.swift`.
    var dismissals: [FindingKey: FindingDismissal]

    init(
        pullRequest: PRIdentifier,
        headSha: String,
        runs: [StoredReviewRun] = [],
        isStale: Bool = false,
        closedAt: Date? = nil,
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) {
        self.pullRequest = pullRequest
        self.headSha = headSha
        self.runs = runs
        self.isStale = isStale
        self.closedAt = closedAt
        self.dismissals = dismissals
    }

    /// Dekóduje se ručně **jen kvůli `dismissals`**: syntetizovaný `init(from:)` sahá na
    /// každý neoptional klíč bez ohledu na výchozí hodnotu, takže by starší soubor (a je
    /// jich na disku plno) skončil `keyNotFound` — tedy ztracenými nálezy kvůli poli, které
    /// v něm být nemůže. Tatáž úvaha jako u `Finding.translation`, jen tam to obstará
    /// optional.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pullRequest = try container.decode(PRIdentifier.self, forKey: .pullRequest)
        headSha = try container.decode(String.self, forKey: .headSha)
        runs = try container.decode([StoredReviewRun].self, forKey: .runs)
        isStale = try container.decode(Bool.self, forKey: .isStale)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        dismissals = try container.decodeIfPresent(
            [FindingKey: FindingDismissal].self,
            forKey: .dismissals
        ) ?? [:]
    }

    /// Nálezy ze všech reviewerů dohromady. Neslučují se — každý si nese, kdo ho našel.
    var findings: [Finding] { runs.flatMap(\.findings) }

    /// Kdy doběhl poslední z reviewerů. `nil`, dokud žádný nedoběhl.
    var finishedAt: Date? { runs.map(\.finishedAt).max() }

    /// Nový výsledek téhož skillu ten předchozí nahradí, jiný se přidá na konec.
    mutating func replace(_ run: StoredReviewRun) {
        guard let index = runs.firstIndex(where: { $0.skillID == run.skillID }) else {
            runs.append(run)
            return
        }
        runs[index] = run
    }
}

/// Jeden doběhlý běh, jak si ho aplikace pamatuje.
struct StoredReviewRun: Codable, Hashable, Sendable {
    let skillID: String
    /// Jak běh skončil. U `failed` nese `detail` stderr, na kterém stojí vysvětlení v UI.
    let outcome: ReviewRunOutcome
    /// Cesta k `claude --resume <id>`, i když v1 terminál nemáme.
    let sessionID: String?
    let findings: [Finding]
    /// Kolik nálezů se nepodařilo přečíst. **Musí být vidět:** bez toho je „nález bez
    /// povinného pole“ k nerozeznání od čistého review, tedy od schváleného PR s chybou.
    let droppedFindings: Int
    /// Zavolal reviewer `ReportFindings`? „Nic jsem nenašel“ a „nereportoval jsem“ jsou
    /// různé věci.
    let calledReportFindings: Bool
    /// Kdy se výsledek zapsal.
    ///
    /// Jedno razítko, ne dvě: začátek běhu `ReviewRun` nenese a dotahovat ho jen kvůli
    /// tomu by znamenalo protáhnout čas přes celý runner. Co UI potřebuje, je „jak staré
    /// je tohle review“.
    let finishedAt: Date
    /// Co běh stál (#148). **Volitelné**, protože starší soubory ten klíč nemají — tatáž
    /// úvaha jako u `Finding.translation`, a stejně jako tam to obstará optional: syntetizovaný
    /// `init(from:)` u něj sáhne po `decodeIfPresent`, takže se chybějící klíč nedekóduje jako
    /// chyba. `nil` navíc znamená totéž co ve `StreamSummary` — nevíme, ne nula.
    let usage: RunUsage?

    init(_ run: ReviewRun, finishedAt: Date) {
        skillID = run.key.skillID
        outcome = run.outcome
        sessionID = run.sessionID
        findings = run.findings
        droppedFindings = run.summary.droppedFindings
        calledReportFindings = run.summary.calledReportFindings
        self.finishedAt = finishedAt
        usage = run.summary.usage
    }
}
