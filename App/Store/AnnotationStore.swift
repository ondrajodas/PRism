import Foundation

/// Chyba, kterou umí jen tenhle store. **Musí být čitelná**: bez ní by nepřečtené anotace
/// vypadaly jako „diff nikdo nepopsal“ a session by se zaplatila znovu.
enum AnnotationStoreError: LocalizedError {
    /// V souboru jednoho PR leží anotace jiného.
    case foreignAnnotations(expected: PRIdentifier, found: PRIdentifier)
    /// Na místě anotací je symbolický odkaz — čtení by šlo mimo cache.
    case symlinkedAnnotations(pullRequest: PRIdentifier)
    /// Cesta k anotacím vede po rozbalení symlinků **mimo cache aplikace**.
    case annotationsOutsideCache(pullRequest: PRIdentifier)

    var errorDescription: String? {
        switch self {
        case .foreignAnnotations(let expected, let found):
            "V souboru anotací pro \(expected) leží anotace pro \(found)."
        case .symlinkedAnnotations(let pullRequest):
            "Na místě anotací pro \(pullRequest) je symbolický odkaz. Aplikace čte jen svoje soubory."
        case .annotationsOutsideCache(let pullRequest):
            "Cesta k anotacím pro \(pullRequest) vede mimo cache aplikace. Aplikace sahá jen do ní."
        }
    }
}

/// Persistence anotací hunků — jeden JSON na PR pod `annotations/` (#524).
///
/// **Vlastní store, ne pole v `ReviewRecord`u**, a je to rozhodnutí, ne úspora. Tři důvody:
///
/// - **Anotace není nález.** Kdyby bydlela v záznamu s nálezy, byla by jeden `if` od toho, aby se
///   počítala do odznaků, do souhrnu nebo do návrhu verdiktu. Takhle je oddělení **kontrolovatelné
///   grepem**: `HunkAnnotation` se v `App/Store/ReviewRecord.swift` nevyskytuje.
/// - **Anotace se pouští i bez review.** Ručně z lišty nad diffem se dá popsat PR, na kterém
///   žádný reviewer neběžel — a `ReviewRecord` bez jediného běhu je přesně ten záznam, který
///   v `Policy.currentRecords` **vyhraje** nad zastaralým záznamem s nálezy (protože není
///   zastaralý). Nálezy z minula by tím z okna zmizely ve chvíli, kdy si člověk řekne o popis
///   změn. Je to tatáž past, kvůli které nemá vlastní záznam ani kontrola nálezů (#150).
/// - **Store si drží jeden záznam na PR v paměti.** `AppStore.reviewRecords[pr]` je ten *současný*
///   záznam, tedy klidně ten pro starší hlavu — anotace pro tu dnešní by v něm neměly kde být.
///
/// Aktor ze stejného důvodu jako `ReadMarkStore` a `AskStore`: uložení je čtení, změna a zápis
/// téhož souboru.
actor AnnotationStore {
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

    /// Anotace jednoho PR, nebo `nil`, když žádné nejsou.
    ///
    /// **Vrací je i tehdy, když patří jiné hlavě** — o platnosti rozhoduje
    /// `Policy.annotations(of:head:)`, ne store. Je to tatáž dělba jako u kontroly nálezů:
    /// store čte soubor, `Policy` říká, co se z něj smí ukázat.
    ///
    /// **Nečitelný soubor vyhodí chybu**, nevrátí `nil`: tichá nula by znamenala, že se zaplacená
    /// session tváří jako neproběhlá — a příští běh by ji zaplatil znovu.
    func load(for pr: PRIdentifier) throws -> StoredAnnotations? {
        // **Hranice cache napřed, existence až po ní** — jako u `AskStore` a `ReadMarkStore`.
        // Obráceně by se `fileExists` ptalo skrz odkaz, tedy na soubor mimo cache.
        let url = try ownFile(for: pr)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let stored = try decoder.decode(StoredAnnotations.self, from: try Data(contentsOf: url))
        // Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal větu nad
        // hunkem, která mluví o cizím PR.
        guard stored.pullRequest == pr else {
            throw AnnotationStoreError.foreignAnnotations(expected: pr, found: stored.pullRequest)
        }
        return stored
    }

    /// Uloží anotace. **Přepisuje, nedopisuje**: užitečná je vždycky jen ta sada pro dnešní hlavu,
    /// viz `StoredAnnotations`.
    ///
    /// **Běh, ze kterého nevypadlo nic, se ukládá taky** — na rozdíl od prázdných značek `Prošlo`.
    /// „Session doběhla a nic nepopsala“ je odpověď, za kterou se zaplatilo, a bez souboru by se
    /// v okně nedala odlišit od „nikdy neběželo“; právě to je ten stav, který by si vyžádal běh
    /// druhý.
    func save(_ annotations: StoredAnnotations) throws {
        let url = try ownFile(for: annotations.pullRequest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomicky: půlka souboru se od celého nedá odlišit ničím jiným než tím, že se nepodaří
        // dekódovat — a to by vypadalo jako ztracená session.
        try encoder.encode(annotations).write(to: url, options: .atomic)
    }

    /// Zahodí anotace PR. Idempotentní — chybějící soubor není chyba.
    ///
    /// **Odkaz na souboru se tady neodmítá**, na rozdíl od čtení a zápisu, a je to tentýž rozdíl
    /// jako u `AskStore`: `removeItem` smaže **odkaz**, ne jeho cíl, takže je to jediná cesta, jak
    /// takovou anomálii z cache dostat pryč.
    func delete(for pr: PRIdentifier) throws {
        let url = layout.annotationFile(for: pr)
        guard CacheFile.isInsideCache(url, in: layout) else { return }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Cesta k anotacím **ověřená na hranici cache** — jediné místo, odkud si ji čtení a zápis
    /// berou. Pravidlo samo je v `CacheFile`; tady se překládá na chybu, která umí říct, o které
    /// PR jde.
    private func ownFile(for pr: PRIdentifier) throws -> URL {
        let url = layout.annotationFile(for: pr)
        switch CacheFile.refusal(for: url, in: layout) {
        case .outsideCache: throw AnnotationStoreError.annotationsOutsideCache(pullRequest: pr)
        case .symbolicLink: throw AnnotationStoreError.symlinkedAnnotations(pullRequest: pr)
        case nil: return url
        }
    }
}
