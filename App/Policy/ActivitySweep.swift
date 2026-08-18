import Foundation

extension Policy {
    /// Na které vlastní PR se **v tomhle tiku** zeptáme na konverzaci (#335).
    ///
    /// Tik pollingu je jeden search dotaz na zdroj. Konverzace pro všechna vlastní PR by z něj
    /// udělala `1 + N` dotazů každou minutu, a to je tatáž `N+1` past, kvůli které se pollingem
    /// netahá ani detail PR. Cena se proto drží třemi věcmi naráz:
    ///
    /// 1. **`updatedAt` ze searche je předfiltr a je zadarmo.** Konverzace se tahá jedině pro PR,
    ///    jehož `updatedAt` se posunul za ten, se kterým je konverzace v paměti (`loadedAt`) —
    ///    tedy jedině tam, kde se na PR **doopravdy něco stalo**. Na klidný den to je **nula
    ///    dotazů**. `updatedAt` sám o sobě na odznak nestačí: řekne, že se něco stalo, ne co
    ///    a kolik — a hýbe se i po vlastním pushi.
    /// 2. **Vlastní, řádově pomalejší interval** (`activitySweepInterval`). Seznam se obnovuje po
    ///    minutách, protože se z něj pozná nová práce; diskuze na vlastním PR takovou setrvačnost
    ///    nemá — pět minut zpoždění u odpovědi kolegy nikomu nic nezkazí.
    /// 3. **Strop na jednu rozhlídku** (`activitySweepLimit`). I kdyby se naráz pohnulo šest PR,
    ///    jeden průchod dotáhne tři a zbytek dojde na příští — takže nejvyšší cena je shora
    ///    omezená (tři dotazy za pět minut) i v bouři.
    ///
    /// **Rate limit se nedědí druhou cestou, ale tou stejnou:** rozhlídka běží uvnitř
    /// `afterSuccessfulTick`, takže při rate limitu, kdy `PollingService` čeká backoff a netiká,
    /// se nespustí vůbec. Vlastní časovač by tu ochranu obešel.
    ///
    /// - Parameters:
    ///   - loadedAt: `updatedAt`, se kterým je konverzace toho PR v paměti. `nil` = žádná není
    ///     (nebo se nepovedla načíst), takže se o ni má požádat.
    ///   - lastSweep: kdy proběhla **poslední rozhlídka, která se doopravdy ptala**. `nil` = ještě
    ///     žádná. Klidná chvíle okno nespotřebuje: kdyby se razítko posouvalo i po průchodu, který
    ///     nic nenašel, čekalo by se pět minut zrovna na komentář, který přišel vteřinu po tiku.
    ///   - mine: loginy, které se počítají za moje. **Bez výchozí hodnoty** — prázdná množina
    ///     znamená „nikdo nejsem“, takže by zapomenutý parametr rozhlídku tiše vypnul (tatáž úvaha
    ///     jako u `Policy.automaticallyReviewable`, #332).
    static func activitySweep(
        of pullRequests: [PullRequestSummary],
        mine: Set<String>,
        loadedAt: (PRIdentifier) -> Date?,
        now: Date,
        lastSweep: Date?,
        interval: TimeInterval = activitySweepInterval,
        limit: Int = activitySweepLimit
    ) -> [PRIdentifier] {
        if let lastSweep, now.timeIntervalSince(lastSweep) < interval { return [] }
        return self.pullRequests(pullRequests, ownedBy: .mine, mine: mine)
            // Pořadí se bere ze **vstupu**, ne z data: seznam je řazený `Policy.sorted`, tedy od
            // naposledy změněného, takže strop uřízne to nejstarší — a to je zrovna to, co snese
            // čekat na příští rozhlídku.
            .filter { loadedAt($0.id) != $0.updatedAt }
            .prefix(limit)
            .map(\.id)
    }

    /// Jak často se aplikace ptá na diskuzi vlastních PR (#335).
    ///
    /// **Pět minut, ne minuta jako seznam**, a je to konstanta, ne klíč v konfiguraci: je to
    /// pojistka proti ceně, ne předvolba. Nastavitelná by přinesla hlavně způsob, jak si rozpočet
    /// dotazů rozbít ručně — a kdyby se ukázalo, že se ladit potřebuje, patří k tomu mockup
    /// nastavení a vlastní issue.
    ///
    /// **Nezávisí na `pollIntervalSeconds`** schválně: interval seznamu je o tom, jak rychle chci
    /// vidět novou práci, tohle je strop na dotazy do GraphQL. Kdo si seznam zpomalí na deset minut,
    /// dostane rozhlídku při každém tiku — a je to pořád jedna za deset minut.
    static let activitySweepInterval: TimeInterval = 300

    /// Kolik PR nejvíc se jedna rozhlídka zeptá.
    ///
    /// Tři, protože strop je tu kvůli **bouři**, ne kvůli běžnému dni: v tom se pohne jedno nebo
    /// dvě PR a rozhlídka je stihne celá. Zbytek dojde na příští, takže se nic neztrácí — jen se to
    /// o pět minut opozdí.
    static let activitySweepLimit = 3
}
