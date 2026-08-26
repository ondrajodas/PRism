import Foundation

/// Chyba, kterou umí jen tenhle store — a která **musí** být čitelná, protože znamená, že se
/// rozhovor nedá otevřít.
enum AskStoreError: LocalizedError {
    /// V souboru jednoho PR leží rozhovor jiného.
    case foreignConversation(expected: PRIdentifier, found: PRIdentifier)
    /// Na místě rozhovoru je symbolický odkaz — čtení by šlo mimo cache.
    case symlinkedConversation(pullRequest: PRIdentifier)

    var errorDescription: String? {
        switch self {
        case .foreignConversation(let expected, let found):
            "V souboru rozhovoru pro \(expected) leží rozhovor pro \(found)."
        case .symlinkedConversation(let pullRequest):
            "Na místě rozhovoru pro \(pullRequest) je symbolický odkaz. Aplikace čte jen svoje soubory."
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
        let url = layout.askFile(for: pr)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        // Symlink by přečetl soubor **mimo cache**. Aplikace si ho sama nevyrobí, ale „nikdy
        // nesahat na uživatelovy soubory“ je tvrdá podmínka a nemá viset na tom, že si to někdo
        // pamatuje — tatáž kontrola má `ReviewDraftStore` (#106).
        guard !layout.isSymbolicLink(url) else {
            throw AskStoreError.symlinkedConversation(pullRequest: pr)
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
        let url = layout.askFile(for: conversation.pullRequest)
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
    func delete(for pr: PRIdentifier) throws {
        let url = layout.askFile(for: pr)
        // Kontrola je stejná jako u `ReviewDraftStore` a `CacheEviction`: cesta se skládá
        // z `CacheLayout` a ven vést nemůže, ale tvrdá podmínka „nikdy nesahat na uživatelovy
        // soubory“ nemá viset na tom, že si to někdo pamatuje.
        guard layout.contains(url) else { return }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
