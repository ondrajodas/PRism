import Foundation

extension Policy {
    /// Rozešly se nálezy s hlavou PR? (#284, #420) `nil` = nerozešly, nebo se to nedá říct.
    ///
    /// **Jediné místo, kde se ty dvě sha porovnávají.** Do #420 to porovnání bydlelo v
    /// `AppStore.staleFindings(for:)`, tedy jedině nad **načteným detailem**; dávkový dotaz na
    /// hlavy (#420) je druhý zdroj té dnešní sha, ne druhá pravda o tom, co je zastaralé — proto se
    /// z toho stala čistá funkce a oba volající ji berou odsud. Dvě porovnání by znamenala dvě
    /// odpovědi na jednu otázku, a to tvrdá podmínka č. 5 zakazuje.
    ///
    /// - Parameters:
    ///   - record: záznam review. `nil` (na PR se nikdy nereviewovalo) znamená, že není co zastarat.
    ///   - head: hlava, na které PR stojí **teď**. `nil` (detail se nenačetl, dotaz na ni nedorazil)
    ///     dá `nil`, ne „zastaralo“: dokud dnešní hlavu neznáme, nevíme o rozchodu nic.
    static func staleFindings(of record: ReviewRecord?, head: String?) -> StaleFindings? {
        guard let record, let head, record.headSha != head else { return nil }
        return StaleFindings(
            head: head,
            findingsHead: record.headSha,
            // Odmítnuté nálezy se počítají: odmítnutí nález nesundá (#113), takže je pořád na
            // obrazovce a pořád patří ke staršímu commitu.
            hasFindings: !record.findings.isEmpty
        )
    }

    /// Na hlavy kterých PR se **v tomhle tiku** zeptáme (#420).
    ///
    /// Zastaralé nálezy jsou ta událost, po které je práce k zahození, takže se o nich má vědět bez
    /// otevírání PR — a to bez `headSha`, kterou search nedává, jinak než dotazem nejde. Cena se
    /// drží třemi věcmi naráz, ze stejné školy jako `Policy.activitySweep` (#335):
    ///
    /// 1. **Jedno dávkové volání, ne jedno na PR.** Odpověď na celou frontu se skládá jedním
    ///    GraphQL dokumentem (`PullRequestHeadsQuery`), takže z počtu PR neroste počet volání.
    ///    Tohle je ta polovina, na které stojí zadání: `N+1` na tik je zakázané.
    /// 2. **`updatedAt` ze searche je předfiltr a je zadarmo.** Ptáme se jedině na PR, jehož
    ///    `updatedAt` se posunul od té chvíle, kdy jsme se na jeho hlavu ptali naposledy — hlava se
    ///    bez posunu `updatedAt` změnit nemá čím. Na klidný den to je **nula volání**, protože
    ///    prázdný seznam se nespouští.
    /// 3. **Strop na jeden dotaz** (`staleHeadProbeLimit`). Ohraničuje **velikost dokumentu**, ne
    ///    počet volání: co se do stropu nevejde, se zeptá příští tik, protože razítko dostanou
    ///    jedině PR, na které se ptalo.
    ///
    /// **Jen cizí PR, a je to brána, ne úspora.** O zastaralých nálezech na vlastním PR se nehlásí
    /// (`Policy.isReported(.staleFindings, on:)`, #332), takže dotaz na ně by byl dotaz na řádek,
    /// který nikdy nevznikne — a kdyby se to pravidlo zúžením obešlo, byl by z dění obchvat #332.
    ///
    /// **Jen PR s uloženými nálezy.** Bez nálezů není co zastarat (`StaleFindings.hasFindings`), a
    /// je to zároveň ten předfiltr, který ze fronty vybere hrstku: čisté review ani nedotčené PR do
    /// dotazu nejdou. Zadání upozorňuje, že u téhle instalace je to většina fronty — proto to samo
    /// nestačí a nese to bod 1.
    ///
    /// - Parameters:
    ///   - mine: loginy, které se počítají za moje. **Bez výchozí hodnoty** — prázdná množina
    ///     znamená „nikdo nejsem“, takže by zapomenutý parametr znamenal dotazy na vlastní PR
    ///     (tatáž úvaha jako u `Policy.activitySweep`).
    ///   - hasFindings: leží na PR uložené nálezy?
    ///   - probedAt: `updatedAt`, se kterým se na hlavu toho PR ptalo naposledy. `nil` = nikdy —
    ///     tedy i po startu aplikace, což je zrovna ta chvíle, kdy se má dohnat, co se stalo,
    ///     když aplikace neběžela.
    static func staleHeadProbe(
        of pullRequests: [PullRequestSummary],
        mine: Set<String>,
        hasFindings: (PRIdentifier) -> Bool,
        probedAt: (PRIdentifier) -> Date?,
        limit: Int = staleHeadProbeLimit
    ) -> [PRIdentifier] {
        self.pullRequests(pullRequests, ownedBy: .theirs, mine: mine)
            // Pořadí se bere ze **vstupu**, ne z data: seznam je řazený `Policy.sorted`, tedy od
            // naposledy změněného, takže strop uřízne to nejstarší — a to je zrovna to, co snese
            // čekat na příští tik.
            .filter { hasFindings($0.id) && probedAt($0.id) != $0.updatedAt }
            .prefix(limit)
            .map(\.id)
    }

    /// Kolik PR nejvíc se vejde do jednoho dotazu na hlavy (#420).
    ///
    /// **Dvacet, a je to strop na velikost dokumentu, ne na cenu.** Změřeno na živém API, že 24
    /// aliasů stojí pořád **1 bod z 5000/h** a odpověď má 4,9 kB, takže víc PR nestojí víc volání
    /// ani víc bodů — roste jen text dotazu (~190 B na alias). Dvacet je nad frontou téhle
    /// instalace (dvanáct PR z deseti repozitářů) s rezervou a zbytek se dozvíme za minutu.
    ///
    /// Konstanta, ne klíč v konfiguraci, ze stejného důvodu jako `activitySweepLimit`: je to
    /// pojistka proti velikosti dotazu, ne předvolba, kterou by měl kdo ladit.
    static let staleHeadProbeLimit = 20

    /// Na větve kterých PR se **v tomhle tiku** zeptáme (#513) — protějšek `staleHeadProbe`
    /// nad **týmž** dotazem.
    ///
    /// Série PR se z dnešních dat poznat nedá: `gh search prs` větve nevrací vůbec, takže je
    /// `PullRequestSummary` nemá ani jako pole a cizí PR ve frontě načtený detail nemají (#572 ho
    /// tahá jen u vlastních). Dávkový dotaz na hlavy je nese od #513 s sebou — jsou to tři pole na
    /// témže uzlu, tedy **žádné volání navíc**, a tahle funkce říká, koho do něj přibrat.
    ///
    /// Předfiltr je **stejnou školou jako `snoozeProbe`** (#512), jen bez jeho výjimky:
    ///
    /// 1. **`updatedAt` je zadarmo.** Ptáme se jedině na PR, jehož `updatedAt` se posunul od chvíle,
    ///    kdy jsme se ptali naposledy — base větev se bez posunu `updatedAt` změnit nemá čím.
    ///    Na klidný tik z toho vyjde **prázdno, a to se nespouští**.
    /// 2. **„Ještě jsme se neptali“ nese totéž razítko**, takže se na PR bez razítka zeptáme i bez
    ///    posunu — a právě tím se série po startu vůbec dozví, na čem co stojí. Razítko dostane
    ///    jedině PR, na které odpověď **dorazila** (`AppStore.refreshHeads`), takže chybějící alias
    ///    znamená zeptat se příště znovu.
    ///
    ///    **Odpověď bez větví se za neznalost nepočítá, a je to rozhodnutí** (změna proti prvnímu
    ///    návrhu, kde předfiltr četl mapu větví): GitHub je na otevřeném PR vrací vždycky, takže PR,
    ///    u kterého by v odpovědi chyběly, by se ptal **každou minutu donekonečna** — a fixtury
    ///    z #420 (odpověď bez větví) to dokládají. „Nevíme“ je proto stav, se kterým se čeká na
    ///    další pohyb, ne důvod k dotazu navíc.
    ///
    /// **Jen cizí PR, a je to úspora, ne brána.** Větve **vlastních** PR dotahuje každý tik
    /// rozhlídka po slévatelnosti (#572, `MergeReadinessQuery` je nese v hlavičce), takže ptát se
    /// na ně i tudy by znamenalo platit dvakrát za tutéž hodnotu. Sérii to nebrání: kdo se ptá na
    /// větve, ptá se `AppStore.branchRefs(for:)`, a ten obě cesty spojuje.
    ///
    /// - Parameters:
    ///   - mine: loginy, které se počítají za moje. **Bez výchozí hodnoty**, jako u `staleHeadProbe`.
    ///   - probedAt: `updatedAt`, se kterým se na to PR ptalo naposledy. `nil` = nikdy, a to je
    ///     zrovna ta chvíle po startu, kdy se série musí dozvědět, na čem co stojí.
    static func seriesRefsProbe(
        of pullRequests: [PullRequestSummary],
        mine: Set<String>,
        probedAt: (PRIdentifier) -> Date?,
        limit: Int = staleHeadProbeLimit
    ) -> [PRIdentifier] {
        self.pullRequests(pullRequests, ownedBy: .theirs, mine: mine)
            // Zavřené a mergnuté se neptáme: v sérii nejsou (`Policy.series`) a jejich větve už
            // nemají jak vzniknout — byl by to dotaz za odpověď, kterou nikdo nepřečte.
            .filter { $0.state == .open || $0.state == .draft }
            .filter { probedAt($0.id) != $0.updatedAt }
            // Pořadí ze **vstupu**, jako u obou sousedů: seznam je od naposledy změněného, takže
            // strop uřízne to nejstarší — a to je zrovna to, co snese počkat na příští tik.
            .prefix(limit)
            .map(\.id)
    }

    /// Koho se dávkový dotaz na hlavy zeptá v tomhle tiku (#513) — **sjednocení obou předfiltrů**.
    ///
    /// Existuje proto, aby z dvou rozhlídek bylo **jedno volání**: obě se ptají na týž uzel téhož
    /// dotazu (`PullRequestHeadsQuery`), takže dva seznamy by znamenaly dva dotazy za data, která
    /// jeden z nich nese celá. Je to rozdíl proti `SnoozeProbeQuery` (#512), a schválně: tam se
    /// dotazy liší **poli**, tady ne.
    ///
    /// **Zastaralé nálezy jdou první.** Strop je na velikost dokumentu, takže když se do něj obojí
    /// nevejde, ustoupí rozhlídka po větvích — série se dozví za minutu, kdežto zastaralé nálezy
    /// jsou ta událost, po které je práce k zahození.
    static func headProbe(
        stale: [PRIdentifier],
        refs: [PRIdentifier],
        limit: Int = staleHeadProbeLimit
    ) -> [PRIdentifier] {
        var seen: Set<PRIdentifier> = []
        return Array((stale + refs).filter { seen.insert($0).inserted }.prefix(limit))
    }
}
