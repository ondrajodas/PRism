import Foundation

/// Které PR už aplikace ohlásila jako nové (#85).
///
/// **Na disku, ne v paměti.** Bez toho by po každém spuštění vyšla všechna otevřená PR jako
/// nová a přišlo by jich deset naráz — a to je zrovna ta lavina, kvůli které si uživatel
/// notifikace vypne.
///
/// **Snímek, ne rostoucí seznam.** Drží se, co bylo v posledním úspěšném tiku; příště se
/// ohlásí to, co v něm není, a snímek se přepíše. Nic se nehromadí a nemusí se nic uklízet —
/// velikost je vždycky velikost fronty. Log ohlášených by naopak potřeboval vlastní lhůtu
/// a vlastní úklid, tedy další místo, kde se dá zapomenout mazat.
///
/// Vypadává z toho i odpověď na otázku, co s PR, které ze seznamu zmizí a vrátí se:
/// **ohlásí se znovu**, protože ve snímku není. Vrátilo se do fronty a je to informace.
///
/// Aktor ze stejného důvodu jako `AutoRunLedger`: čtení, porovnání a zápis jsou tři kroky
/// nad jedním souborem.
actor AnnouncedPullRequests {
    private let layout: CacheLayout
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Snímek, se kterým se pracuje. `nil` = ještě se nečetl z disku.
    private var cached: Set<PRIdentifier>?
    /// Byl snímek už někdy zapsaný? Odlišuje **první spuštění** od prázdné fronty.
    private var known = false

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Co je z předaného seznamu nové, a zapamatuje si ho.
    ///
    /// **Při prvním spuštění vrací prázdno** a jen si seznam zapamatuje: dokud snímek nikdy
    /// neexistoval, není proti čemu porovnávat a „všechno je nové“ by byla ta lavina. Prázdný
    /// **zapsaný** snímek je něco jiného — to znamená, že fronta byla prázdná, takže se nové
    /// PR ohlásit mají.
    ///
    /// Volá se **jen po úspěšném tiku**. Po výpadku sítě je seznam prázdný, takže by se snímek
    /// vyprázdnil a při zotavení by se ohlásilo úplně všechno — tatáž past jako
    /// u `CacheEviction` a `ReviewStore.cleanUp`.
    func newcomers(in current: [PRIdentifier]) -> [PRIdentifier] {
        let previous = load()
        // První spuštění: zapamatovat **hned** a mlčet. Zapsat se to tady musí, protože
        // volající nemá co doručovat, takže by `remember(_:)` nikdy nepřišlo — a snímek by se
        // nezaložil ani při dalších ticích. U ostatních tiků se naopak nezapisuje nic:
        // o pořadí „nejdřív doručit, pak zapsat“ rozhoduje volající.
        guard known else {
            write(Set(current))
            return []
        }
        // Pořadí se bere ze **vstupu**, ne z množiny — ta ho nemá, takže by notifikace mezi
        // tiky poskakovaly. Vstup je řazený `Policy.sorted`, tedy od naposledy změněného.
        return current.filter { !previous.contains($0) }
    }

    /// Zapíše snímek — **až po tom, co se notifikace doručily**.
    ///
    /// Opačné pořadí by znamenalo, že se PR zapíše jako ohlášené, notifikace se nepovede
    /// a už se nikdy nepošle (ve snímku bude). Proto je zápis vlastní volání, ne součást
    /// `newcomers(in:)`.
    ///
    /// **Změna proti první podobě**, kde `newcomers` zapisovalo samo v `defer` — to je
    /// pohodlnější, ale ztrácí přesně tu notifikaci, o kterou jde.
    func remember(_ pullRequests: [PRIdentifier]) {
        write(Set(pullRequests))
    }

    private func load() -> Set<PRIdentifier> {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: layout.announcedFile),
              let stored = try? decoder.decode([PRIdentifier].self, from: data)
        else {
            // Nečitelný nebo chybějící soubor se bere jako **první spuštění**, tedy mlčení.
            // Je to opačná volba než u nálezů, kde se rozbitý soubor hlásí: nejhorší následek
            // je jedno neohlášené kolo, kdežto lavina deseti notifikací je to, čemu se celé
            // tohle issue vyhýbá.
            return []
        }
        cached = Set(stored)
        known = true
        return Set(stored)
    }

    /// Zapíše snímek — **nejdřív do paměti, pak na disk**, jako `AutoRunLedger`.
    ///
    /// Selhání zápisu se spolkne, a je to bezpečný směr: za běhu platí paměť, a po restartu se
    /// nepřečte žádný snímek, takže se bere jako **první spuštění** a aplikace mlčí. Rozbitý
    /// disk tedy stojí neohlášená PR, ne lavinu — a to je ta chyba, kterou si tohle issue může
    /// dovolit. Hlásit se to nemusí: příští zápis to zkusí znovu a nic se neztrácí, protože
    /// snímek není historie, ale stav fronty.
    private func write(_ pullRequests: Set<PRIdentifier>) {
        cached = pullRequests
        known = true
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        // Řazené pole, ne množina: JSON má být stabilní, ať se soubor nemění bez důvodu.
        // `PRIdentifier` je `Comparable` a řadí čísla číselně (viz pravidla v `CLAUDE.md`).
        try? encoder.encode(pullRequests.sorted()).write(to: layout.announcedFile, options: .atomic)
    }
}
