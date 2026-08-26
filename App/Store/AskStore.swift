import Foundation

/// Chyba, kterou umí jen tenhle store — a která **musí** být čitelná, protože znamená, že se
/// rozhovor nedá otevřít.
enum AskStoreError: LocalizedError {
    /// V souboru jednoho PR leží rozhovor jiného.
    case foreignConversation(expected: PRIdentifier, found: PRIdentifier)
    /// Na místě rozhovoru je symbolický odkaz — čtení by šlo mimo cache.
    case symlinkedConversation(pullRequest: PRIdentifier)
    /// Cesta k rozhovoru vede po rozbalení symlinků **mimo cache aplikace**.
    case conversationOutsideCache(pullRequest: PRIdentifier)

    var errorDescription: String? {
        switch self {
        case .foreignConversation(let expected, let found):
            "V souboru rozhovoru pro \(expected) leží rozhovor pro \(found)."
        case .symlinkedConversation(let pullRequest):
            "Na místě rozhovoru pro \(pullRequest) je symbolický odkaz. Aplikace čte jen svoje soubory."
        case .conversationOutsideCache(let pullRequest):
            "Cesta k rozhovoru pro \(pullRequest) vede mimo cache aplikace. Aplikace sahá jen do ní."
        }
    }
}

/// Persistence rozhovorů z tabu `Zeptat se` — jeden JSON na PR pod `ask/` (#452).
///
/// Aktor ze stejného důvodu jako `ReviewDraftStore`: uložení je čtení, změna a zápis téhož
/// souboru, a otázka i odpověď se zapisují každá zvlášť.
///
/// **Načítá se až při otevření tabu, ne při startu** — na rozdíl od draftů. Draft se při startu
/// čte celý proto, že jeho indikátor svítí v seznamu u všech PR naráz; rozhovor v seznamu nic
/// nemá, takže by se při každém spuštění dekódovalo všechno, co si kdo kdy vyzkoušel, kvůli
/// obrazovce, na kterou se ten den nemusí přijít podívat.
actor AskStore {
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

    /// Rozhovor jednoho PR, nebo `nil`, když žádný není.
    ///
    /// **Nečitelný soubor vyhodí chybu**, nevrátí `nil`. Tichá nula by znamenala, že se zaplacený
    /// rozhovor tváří jako neexistující — a příští otázka by začala novou session a zaplatila
    /// kontext znovu, aniž by kdo věděl proč.
    func load(for pr: PRIdentifier) throws -> AskConversation? {
        // **Hranice cache napřed, existence až po ní.** Obráceně by se `fileExists` ptalo skrz
        // odkaz, tedy na soubor mimo cache — a odpověď „ano, je tam“ by o našem souboru neříkala
        // nic.
        let url = try ownFile(for: pr)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let conversation = try decoder.decode(AskConversation.self, from: try Data(contentsOf: url))
        // Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal, že se
        // v tabu jednoho PR ukáže rozhovor o jiném.
        guard conversation.pullRequest == pr else {
            throw AskStoreError.foreignConversation(expected: pr, found: conversation.pullRequest)
        }
        return conversation
    }

    /// Uloží rozhovor. **Prázdný se maže**, ne ukládá — tentýž vzor jako u draftu: bez toho by
    /// v cache zůstal soubor po každém PR, které si někdo jen otevřel.
    func save(_ conversation: AskConversation) throws {
        guard !conversation.isEmpty else {
            try delete(for: conversation.pullRequest)
            return
        }
        let url = try ownFile(for: conversation.pullRequest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomicky: půlka souboru se od celého nedá odlišit ničím jiným než tím, že se nepodaří
        // dekódovat — a to by vypadalo jako ztracený rozhovor.
        try encoder.encode(conversation).write(to: url, options: .atomic)
    }

    /// Zahodí rozhovor. Idempotentní — chybějící soubor není chyba, protože se na tlačítko dá
    /// zmáčknout dvakrát.
    ///
    /// **Odkaz na souboru se tady neodmítá**, na rozdíl od čtení a zápisu, a je to rozdíl, ne
    /// nedůslednost: `removeItem` smaže **odkaz**, ne jeho cíl, takže je to jediná cesta, jak
    /// takovou anomálii z cache dostat pryč. Kdyby ji `Nový rozhovor` odmítal uklidit, zůstal by
    /// odkaz v cache navždycky a rozhovor by se nedal ani otevřít, ani zahodit. Důvod bydlí
    /// v `CacheFile`.
    func delete(for pr: PRIdentifier) throws {
        let url = layout.askFile(for: pr)
        guard CacheFile.isInsideCache(url, in: layout) else { return }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Cesta k souboru rozhovoru **ověřená na hranici cache** — jediné místo, odkud si ji čtení
    /// a zápis berou.
    ///
    /// Do #458 tu kontrolu mělo jen mazání, takže `load` i `save` sahaly na cestu, kterou by
    /// symlink v rodičovské složce vyvedl ven (nález Copilota na #458). Pravidlo samo je
    /// v `CacheFile`; tady se jen překládá na chybu, která umí říct, o **který rozhovor** jde —
    /// obecné „cesta je mimo cache“ v panelu nikomu neřekne, co se stalo.
    private func ownFile(for pr: PRIdentifier) throws -> URL {
        let url = layout.askFile(for: pr)
        switch CacheFile.refusal(for: url, in: layout) {
        case .outsideCache: throw AskStoreError.conversationOutsideCache(pullRequest: pr)
        case .symbolicLink: throw AskStoreError.symlinkedConversation(pullRequest: pr)
        case nil: return url
        }
    }
}
