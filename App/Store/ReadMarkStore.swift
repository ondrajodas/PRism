import Foundation

/// Chyba, kterou umí jen tenhle store. **Musí být čitelná**: bez ní by nepřečtené značky
/// vypadaly jako „nic jsem nepřečetl“ a padesátisouborový diff by se procházel znovu.
enum ReadMarkStoreError: LocalizedError {
    /// V souboru jednoho PR leží značky jiného.
    case foreignMarks(expected: PRIdentifier, found: PRIdentifier)
    /// Na místě značek je symbolický odkaz — čtení by šlo mimo cache.
    case symlinkedMarks(pullRequest: PRIdentifier)
    /// Cesta ke značkám vede po rozbalení symlinků **mimo cache aplikace**.
    case marksOutsideCache(pullRequest: PRIdentifier)

    var errorDescription: String? {
        switch self {
        case .foreignMarks(let expected, let found):
            "V souboru značek pro \(expected) leží značky pro \(found)."
        case .symlinkedMarks(let pullRequest):
            "Na místě značek pro \(pullRequest) je symbolický odkaz. Aplikace čte jen svoje soubory."
        case .marksOutsideCache(let pullRequest):
            "Cesta ke značkám pro \(pullRequest) vede mimo cache aplikace. Aplikace sahá jen do ní."
        }
    }
}

/// Persistence značek `Prošlo` — jeden JSON na PR pod `read-marks/` (#500).
///
/// Aktor ze stejného důvodu jako `AskStore` a `ReviewDraftStore`: uložení je čtení, změna
/// a zápis téhož souboru, a zaškrtává se po jednom souboru.
///
/// **Načítá se až při otevření PR, ne při startu** — jako rozhovor (#452) a na rozdíl od draftů.
/// Draft svítí v seznamu u všech PR naráz, kdežto značky jsou vidět jedině v diffu, takže by se
/// při každém spuštění dekódovalo všechno, co kdy někdo prošel, kvůli obrazovce, na kterou se ten
/// den nemusí přijít podívat.
actor ReadMarkStore {
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

    /// Značky jednoho PR, nebo `nil`, když žádné nejsou.
    ///
    /// **Nečitelný soubor vyhodí chybu**, nevrátí `nil`: tichá nula znamená v okně nezaškrtnutý
    /// diff, tedy tvrzení „tohle jsi nečetl“ nad souborem, který na disku je.
    func load(for pr: PRIdentifier) throws -> ReadMarks? {
        // **Hranice cache napřed, existence až po ní** — jako u `AskStore`. Obráceně by se
        // `fileExists` ptalo skrz odkaz, tedy na soubor mimo cache.
        let url = try ownFile(for: pr)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let marks = try decoder.decode(ReadMarks.self, from: try Data(contentsOf: url))
        // Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal, že se
        // v diffu jednoho PR zaškrtnou soubory jiného.
        guard marks.pullRequest == pr else {
            throw ReadMarkStoreError.foreignMarks(expected: pr, found: marks.pullRequest)
        }
        return marks
    }

    /// Uloží značky. **Prázdné se mažou**, ne ukládají — jinak by v cache zůstal soubor po
    /// každém PR, u kterého si někdo něco zaškrtl a zase odškrtl.
    func save(_ marks: ReadMarks) throws {
        guard !marks.isEmpty else {
            try delete(for: marks.pullRequest)
            return
        }
        let url = try ownFile(for: marks.pullRequest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomicky: půlka souboru se od celého nedá odlišit ničím jiným než tím, že se nepodaří
        // dekódovat — a to by vypadalo jako ztracená práce.
        try encoder.encode(marks).write(to: url, options: .atomic)
    }

    /// Zahodí značky PR. Idempotentní — chybějící soubor není chyba.
    ///
    /// **Odkaz na souboru se tady neodmítá**, na rozdíl od čtení a zápisu, a je to tentýž rozdíl
    /// jako u `AskStore`: `removeItem` smaže **odkaz**, ne jeho cíl, takže je to jediná cesta, jak
    /// takovou anomálii z cache dostat pryč.
    func delete(for pr: PRIdentifier) throws {
        let url = layout.readMarkFile(for: pr)
        guard CacheFile.isInsideCache(url, in: layout) else { return }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Cesta ke značkám **ověřená na hranici cache** — jediné místo, odkud si ji čtení a zápis
    /// berou. Pravidlo samo je v `CacheFile`; tady se překládá na chybu, která umí říct, o které
    /// PR jde.
    private func ownFile(for pr: PRIdentifier) throws -> URL {
        let url = layout.readMarkFile(for: pr)
        switch CacheFile.refusal(for: url, in: layout) {
        case .outsideCache: throw ReadMarkStoreError.marksOutsideCache(pullRequest: pr)
        case .symbolicLink: throw ReadMarkStoreError.symlinkedMarks(pullRequest: pr)
        case nil: return url
        }
    }
}
