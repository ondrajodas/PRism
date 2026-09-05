import Foundation

extension Policy {
    /// Na které vlastní PR se má tik zeptat, aby deska uměla říct `K merge` (#572).
    ///
    /// **Rozhodování o mergi se tím nemění ani o písmeno.** `Policy.mergeOffer`, `isMergeReady`
    /// i `lane` zůstávají, jak byly — tahle funkce odpovídá na jinou otázku: **kdy** mají ta
    /// rozhodnutí data. Do #572 je měla teprve po otevření záložky, takže byl pruh `K merge` po
    /// startu prázdný, i když měl člověk vlastních PR k mergnutí několik.
    ///
    /// Tři pravidla, každé je vidět v podpisu:
    ///
    /// 1. **Jen vlastní PR.** Na cizím se sekce `Větev` nekreslí a mergnout cizí frontu se odsud
    ///    nedělá nikdy — dotaz na ně by byl dotaz za odpověď, kterou nikdo nepřečte.
    /// 2. **Jen otevřený a rozpracovaný.** Mergnutý a zavřený PR vrací `mergeable: UNKNOWN`
    ///    **navždycky** (změřeno na `PRism#470`), takže by se na něm nedopočítaná odpověď
    ///    zahazovala tik co tik a ptalo by se na něj do skonání světa. Stav se bere ze **shrnutí**,
    ///    tedy z toho, co vyhledávání vydá už dneska — právě proto, že načtený detail v tu chvíli
    ///    ještě není.
    /// 3. **Jen na to, co nevíme, nebo co zestaralo.** `isFresh` je razítko `updatedAt` u obou
    ///    map, které se z odpovědi plní (`detailStates` a `branchStatuses`) — tedy tatáž cache,
    ///    jakou má otevřená záložka. Na klidný tik z toho vyjde **prázdno, a to se nespouští**.
    ///
    /// **Strop na jeden dotaz** (`mergeReadinessProbeLimit`) ohraničuje **velikost dokumentu**, ne
    /// počet volání: co se do něj nevejde, se zeptá příští tik, protože do map se zapíše jedině to,
    /// na co se ptalo. Pořadí se bere ze **vstupu** (seznam je řazený `Policy.sorted`, tedy od
    /// naposledy změněného), takže strop uřízne to nejstarší.
    ///
    /// - Parameters:
    ///   - mine: loginy, které se počítají za moje. **Bez výchozí hodnoty** — prázdná množina
    ///     znamená „nikdo nejsem“, takže by zapomenutý parametr znamenal nula dotazů a pruh
    ///     `K merge` navždycky prázdný (tatáž úvaha jako u `Policy.staleHeadProbe`, jen z opačného
    ///     konce).
    ///   - isFresh: má už PR hlavičku i slévatelnost k **tomuhle** `updatedAt`?
    static func mergeReadinessProbe(
        of pullRequests: [PullRequestSummary],
        mine: Set<String>,
        isFresh: (PullRequestSummary) -> Bool,
        limit: Int = mergeReadinessProbeLimit
    ) -> [PRIdentifier] {
        self.pullRequests(pullRequests, ownedBy: .mine, mine: mine)
            .filter { ($0.state == .open || $0.state == .draft) && !isFresh($0) }
            .prefix(limit)
            .map(\.id)
    }

    /// Kolik vlastních PR nejvíc se vejde do jednoho dotazu na slévatelnost (#572).
    ///
    /// **Třicet, a je to strop na velikost dokumentu, ne na cenu.** Změřeno na živém API, že
    /// 23 aliasů z 16 repozitářů stojí **1 bod z 5000/h**, odpověď má 39,6 kB a doběhne za
    /// 2,60–3,64 s — víc PR tedy nestojí víc volání ani víc bodů, roste jen text dotazu
    /// (~230 B na alias) a odpověď (~1,7 kB na PR). Třicet je nad vlastní frontou téhle instalace
    /// (23 otevřených PR) s rezervou a zbytek se dozvíme za minutu.
    ///
    /// Konstanta, ne klíč v konfiguraci, ze stejného důvodu jako `staleHeadProbeLimit`: je to
    /// pojistka proti velikosti dotazu, ne předvolba, kterou by měl kdo ladit.
    static let mergeReadinessProbeLimit = 30
}
