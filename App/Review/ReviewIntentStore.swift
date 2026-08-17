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
        let file = layout.intentFile(for: pr, at: headSha)
        // Tatáž kontrola, jakou si dělá razítko použití repa — jedno místo, ne vlastní kopie
        // (`CacheLayout.contains` rozbaluje symlinky v rodiči, protože zápis přes odkaz
        // v cestě by psal mimo cache). „Pracuje výhradně ve své cache“ je tvrdá podmínka.
        let checked = try CacheEviction.insideCache(file, of: layout)
        // **A odkaz na samotném souboru se odmítne výslovně** — `contains` ho nezachytí, protože
        // rozbaluje symlinky na obou stranách. Je to tatáž kontrola, jakou si u čtení dělají
        // `ReviewStore` a `ReviewDraftStore` (#106).
        //
        // Změřeno, že na zápisu **dnes** nestojí nic: `write(to:options: .atomic)` odkaz
        // **nahradí** souborem a cíl nechá být, kdežto tentýž zápis **bez** `.atomic` cíl
        // přepíše. Bezpečnost tedy visela na jednom příznaku u zápisu, což je slabší záruka než
        // vyjmenovaná kontrola — a u `existingFile` níž neplatilo ani to.
        guard !layout.isSymbolicLink(checked) else {
            throw CheckoutError.cacheUnavailable(
                "Na cestě \(checked.path(percentEncoded: false)) leží symbolický odkaz."
            )
        }
        try FileManager.default.createDirectory(
            at: checked.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomicky, ze stejného důvodu jako u nálezů: půlka souboru se od celého nedá odlišit
        // ničím jiným než tím, že v něm chybí sekce — a to by vypadalo jako nedotažené zadání.
        try Data(brief.utf8).write(to: checked, options: .atomic)
        return checked
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
        let file = layout.intentFile(for: pr, at: headSha)
        guard layout.contains(file),
              !layout.isSymbolicLink(file),
              FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        else { return nil }
        return file
    }
}
