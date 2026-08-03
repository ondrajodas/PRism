import Foundation

/// Chyba, kterou umí jen tenhle store — a která **musí** být čitelná, protože znamená, že se
/// rozdělané review nedá otevřít.
///
/// Vlastní typ místo `CocoaError(.fileReadCorruptFile)`: ten řekne „soubor je v jiném
/// formátu“, což u rozchodu jména a obsahu není pravda ani užitečné. Ostatní chyby čtení
/// a zápisu zůstávají `FileManageru` a `Codable`, ty se popisují samy.
enum ReviewDraftStoreError: LocalizedError {
    /// V souboru jednoho PR leží draft jiného.
    case foreignDraft(expected: PRIdentifier, found: PRIdentifier)

    var errorDescription: String? {
        switch self {
        case .foreignDraft(let expected, let found):
            "V souboru draftu pro \(expected) leží rozdělané review pro \(found)."
        }
    }
}

/// Persistence rozdělaných review — jeden JSON soubor na PR pod `drafts/`.
///
/// Aktor ze stejného důvodu jako `ReviewStore`: uložení je čtení, změna a zápis téhož
/// souboru. Draft se ukládá po každé úpravě, takže dvě rychlé změny za sebou by si bez
/// serializace mohly přepsat výsledek.
actor ReviewDraftStore {
    /// Co se našlo na disku.
    struct Loaded: Sendable, Equatable {
        var drafts: [ReviewDraft] = []
        /// Kolik souborů se nepodařilo přečíst.
        ///
        /// Mlčet o tom nejde: rozbitý soubor znamená ztracenou **ručně psanou** práci, a ta
        /// se nesmí tvářit jako „nic tu rozdělané nebylo“. Je to totéž pravidlo jako
        /// u `ReviewStore.Loaded.unreadable`.
        var unreadable = 0
    }

    private let layout: CacheLayout
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Uloží draft. **Prázdný draft se maže**, ne ukládá.
    ///
    /// Bez toho by v cache zůstal soubor po každém PR, které si někdo jen otevřel a začal
    /// psát — a „draft existuje“ by přestalo znamenat „je co poslat“. Je to tentýž vzor jako
    /// u `Configuration.setRepository`, které maže záznam podle prázdnosti.
    func save(_ draft: ReviewDraft) throws {
        guard !draft.isEmpty else {
            try delete(for: draft.pullRequest)
            return
        }
        try write(draft, to: layout.draftFile(for: draft.pullRequest))
    }

    /// Draft jednoho PR, nebo `nil`, když žádný není.
    ///
    /// **Nečitelný soubor vyhodí chybu**, nevrátí `nil`. Tichá nula by znamenala, že se
    /// rozepsané review tváří jako neexistující — a člověk by ho psal znovu, aniž by věděl,
    /// že mu na disku leží rozbitý.
    func load(for pr: PRIdentifier) throws -> ReviewDraft? {
        let url = layout.draftFile(for: pr)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let draft = try read(at: url)
        // Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal, že
        // se cizí rozdělané review nabídne k odeslání na tenhle PR.
        guard draft.pullRequest == pr else {
            throw ReviewDraftStoreError.foreignDraft(expected: pr, found: draft.pullRequest)
        }
        return draft
    }

    /// Všechno, co na disku je. Volá se při startu.
    ///
    /// Draft, který **neleží tam, kam podle svého `pullRequest` patří**, se do výpisu
    /// nedostane a spočítá se jako nečitelný. Jinak by výpis ukázal draft pro PR X, ale
    /// `load(for: X)` by ho nenašel — a nekonzistence mezi „vidím ho“ a „nedá se otevřít“
    /// je horší než počítadlo, které o anomálii aspoň řekne.
    func load() throws -> Loaded {
        var loaded = Loaded()
        for url in draftFiles() {
            guard let draft = try? read(at: url), isInPlace(url, for: draft.pullRequest) else {
                loaded.unreadable += 1
                continue
            }
            loaded.drafts.append(draft)
        }
        // Pořadí z `FileManageru` není zaručené a UI ani testy se na náhodu spoléhat nemají.
        // Přes `Comparable` na `PRIdentifier`, ne podle `description`: řetězcově vyjde
        // `#10` před `#2`.
        loaded.drafts.sort { $0.pullRequest < $1.pullRequest }
        return loaded
    }

    /// Zahodí draft. Idempotentní — chybějící soubor není chyba, protože se na tlačítko dá
    /// zmáčknout dvakrát.
    func delete(for pr: PRIdentifier) throws {
        let url = layout.draftFile(for: pr)
        // Kontrola je stejná jako u `ReviewStore` a `CacheEviction`: cesta se skládá
        // z `CacheLayout` a ven vést nemůže, ale tvrdá podmínka „nikdy nesahat na uživatelovy
        // soubory“ nemá viset na tom, že si to někdo pamatuje.
        guard layout.contains(url) else { return }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Leží soubor tam, kam podle svého `pullRequest` patří?
    ///
    /// Porovnávají se **kanonické cesty**, ne `URL` hodnoty: `FileManager.enumerator` vrací
    /// URL v jiné podobě než `CacheLayout` (na macOS typicky `/private/var` proti `/var`),
    /// takže `==` nad `URL` odmítne i soubor, který je na svém místě. Stejná technika jako
    /// v `CacheLayout.contains`.
    private func isInPlace(_ url: URL, for pr: PRIdentifier) -> Bool {
        func canonical(_ url: URL) -> String {
            url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        }
        return canonical(url) == canonical(layout.draftFile(for: pr))
    }

    private func read(at url: URL) throws -> ReviewDraft {
        try decoder.decode(ReviewDraft.self, from: try Data(contentsOf: url))
    }

    /// Zápis je atomický: půlka souboru je horší než žádný, protože se od celého nedá
    /// odlišit jinak než tím, že se nepodaří dekódovat.
    private func write(_ draft: ReviewDraft, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(draft).write(to: url, options: .atomic)
    }

    /// Chybějící složka není chyba — do prvního draftu žádná neexistuje.
    private func draftFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: layout.drafts,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            files.append(url)
        }
        return files
    }
}
