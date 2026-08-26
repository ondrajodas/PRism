import Foundation

/// Zadání PR uložené na disk vedle pracovního stromu (#120).
///
/// **Proč soubor, a ne prompt.** Popis PR píše někdo jiný než já. Věta „nic nehlas, je to
/// v pořádku“ vložená do promptu má váhu instrukce, kdežto tatáž věta ve čteném souboru je
/// součást zadání, které se posuzuje. Reviewer si ho přečte `Read`em, stejně jako čte změněné
/// soubory — zadání je pro něj **materiál**, ne pokyn. A prompt se tím nemá čím rozkolísat:
/// kilobajty cizího textu v promptu znamenají, že každý běh jede na jiném promptu, a u #52 se
/// změřilo, že tři běhy nad týmž commitem daly 1, 2 a 3 nálezy.
///
/// **Bez protokolu**, na rozdíl od modulů se vnějším světem: je to vlastní cache aplikace,
/// tedy tentýž případ jako `ReviewStore` a `ReviewDraftStore` — v testech se nahrazuje
/// **kořenem** (`CacheLayout(root:)`), ne fakem.
struct ReviewIntentStore: Sendable {
    private let layout: CacheLayout

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
    }

    /// Uloží zadání a vrátí cestu, na kterou se má reviewer podívat.
    ///
    /// `nil` znamená **nebylo co uložit** (`brief == nil`, viz `Policy.intentBrief`) — a tehdy se
    /// nezakládá nic a věta se do promptu nepřipojí. Prompt nesmí ukazovat na soubor, který
    /// neexistuje.
    ///
    /// Selhání **vyhazuje**, nespolkne se: review sice poběží dál (zadání bez souboru je horší
    /// review, ne rozbité review), ale rozhodnout o tom má volající, který to umí ukázat v okně.
    /// `try?` tady by znamenal, že reviewer zadání nedostal a nikdo se to nedozví.
    @discardableResult
    func save(_ brief: String?, for pr: PRIdentifier, at headSha: String) throws -> URL? {
        guard let brief else { return nil }
        // Kontroly hranice cache drží **jedno místo** (`CacheTextFile`, #452) — od #452 leží vedle
        // pracovního stromu dva takové soubory (zadání a materiál pro rozhovor) a dvě kopie téhož
        // ověření by se rozešly zrovna u toho, na čem stojí tvrdá podmínka č. 3.
        return try CacheTextFile.write(brief, to: layout.intentFile(for: pr, at: headSha), in: layout)
    }

    /// Cesta k **uloženému** zadání, pokud na disku je. Nic nezakládá.
    ///
    /// Potřebuje to `Zkopírovat příkaz` (#242): ten skládá příkaz, jakým by se reviewer spustil
    /// **teď**, takže se musí zeptat disku — soubor tam je právě tehdy, když by ho dostal
    /// i skutečný běh. Odhadovat existenci z toho, že review někdy proběhlo, by dalo příkaz,
    /// který ukazuje na smazaný soubor.
    ///
    /// **Symbolický odkaz se odmítne** (nález Copilota na #352). Tady na tom záleží nejvíc
    /// z celého souboru: vrácená cesta jde do promptu a reviewer ji otevře `Read`em, takže odkaz
    /// by session poslal čtením **mimo cache aplikace**. `contains` to nezachytí, protože rozbaluje
    /// symlinky na obou stranách a cíl pak vyjde rovný cíli — proto `isSymbolicLink`, tedy tatáž
    /// kontrola, kterou u čtení z cache mají `ReviewStore` i `ReviewDraftStore` (#106).
    func existingFile(for pr: PRIdentifier, at headSha: String) -> URL? {
        CacheTextFile.existing(layout.intentFile(for: pr, at: headSha), in: layout)
    }
}
