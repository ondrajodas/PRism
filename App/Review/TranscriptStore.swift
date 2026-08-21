import Foundation

/// Čte transcripty session `claude` (#97).
///
/// Nálezy zabitého běhu **nejsou pryč**: `claude` si vede transcript na disku a `ReportFindings`
/// v něm leží ve stejném tvaru jako ve `stream-json`, takže mu rozumí tentýž `StreamParser`.
/// Ověřeno na skutečném transcriptu z `keboola/job-queue#725`.
///
/// **Čte se transcript, nespouští se `--resume`.** Nálezy už na disku jsou; nová session by
/// stála peníze za práci, která je hotová, a dala by jiné nálezy než ty, které se ztratily.
///
/// **Id session se z transcriptu nevytáhne**: řádky nesou `sessionId`, kdežto `stream-json`
/// `session_id`, a parser čte to druhé. Doplní ho volající ze značky, kde je autoritativně —
/// hledat v transcriptu druhý zápis téhož údaje by byla druhá cesta k tomu, co už víme.
///
/// Za protokolem jako ostatní přístup ke stroji — testy si podstrčí fake a nesahají do
/// `~/.claude/`.
protocol TranscriptReading: Sendable {
    /// Co ze session zbylo.
    ///
    /// `nil` = transcript **není** (strom mohla sebrat eviction), a to je konečná odpověď.
    /// Chyba = transcript tam je, ale nedal se přečíst — a to je něco jiného: značka se má
    /// nechat, ať to příští start zkusí znovu. Tiché sloučení obojího do `nil` by při chybě
    /// čtení zahodilo značku i s nálezy, které v transcriptu pořád leží.
    func summary(ofSession sessionID: String, in worktree: URL) async throws -> StreamSummary?

    /// Přepis transcriptu k okamžiku otevření (#327) — **okno posledních 4 MB**, ne celý soubor.
    ///
    /// Odpovědi jsou tři a rozlišují se **týmž způsobem** jako u `summary`: `nil` = transcript
    /// není (konečná odpověď), vyhozená chyba = je, ale nedá se přečíst. Třetí stav — je, ale není
    /// v něm co ukázat — vyleze jako snímek bez událostí; rozhodne o něm `Policy.rawSessionState`.
    ///
    /// `at` je čas snímku zvenčí, ať se dá v testu vyčerpat: hlavička sheetu ho ukazuje a patička
    /// z něj počítá přírůstek.
    func snapshot(ofSession sessionID: String, in worktree: URL, at time: Date) async throws -> RawTranscript?

    /// Jak velký je transcript **teď**. `nil` = není, nebo se velikost nedala zjistit.
    ///
    /// Vlastní metoda, ne druhý snímek: patička hlásí přírůstek od otevření, a přečíst kvůli
    /// jednomu číslu znovu 4 MB by bylo to nejdražší v celém sheetu. Nevyhazuje — zmizelá velikost
    /// znamená „není co říct“ (`Policy.rawSessionGrowth` z ní pilulku nevydá), ne chybu, která by
    /// přebila přepis, který je vidět.
    func size(ofSession sessionID: String, in worktree: URL) async -> Int?
}

/// Transcript je na disku, ale nedal se přečíst (#327).
///
/// Vlastní typ proto, že se ta věta **ukazuje v okně**: u chybějícího UTF-8 nedává `NSError`
/// z Foundationu nic, co by šlo přečíst, a hláška „nedá se přečíst“ bez důvodu je stav, ze kterého
/// se nedá poznat další krok.
struct TranscriptUnreadable: LocalizedError, Equatable, Sendable {
    let reason: String

    var errorDescription: String? { reason }

    static let invalidEncoding = Self(reason: "Soubor nemá platné UTF-8 kódování.")
}

/// `TranscriptReading` nad skutečným `~/.claude/projects/`.
struct TranscriptStore: TranscriptReading {
    private let projects: URL
    private let parser = StreamParser()

    init(projects: URL = TranscriptLocation.defaultProjects) {
        self.projects = projects
    }

    func summary(ofSession sessionID: String, in worktree: URL) async throws -> StreamSummary? {
        let url = transcript(ofSession: sessionID, in: worktree)
        // Chybějící transcript není chyba: strom mohla mezitím sebrat eviction, nebo se session
        // nestihla ani založit. Volající z toho udělá „nedotáhlo se nic“, ne pád startu.
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        // Existující a nečitelný transcript už **chyba je** — nálezy v něm pořád leží, takže
        // se značka nemá zahodit. Proto se nečte přes `try?`.
        let text = try String(contentsOf: url, encoding: .utf8)

        // `TextLines`, ne `components(separatedBy: .newlines)` (#295) — jedno místo, kde se
        // rozhoduje, co je řádek. Ta druhá cesta dělí po skalárech, takže na `CRLF` prostříká mezi
        // záznamy prázdné řetězce.
        let summary = parser.summarize(TextLines.all(text).map(String.init))
        // Prázdný souhrn se nevydává za výsledek. Transcript bez jediného `ReportFindings`
        // znamená, že session nálezy nikdy nenahlásila — uložit z toho běh by v řádku vypadalo
        // jako „reviewer nic nenašel“, což je přesně to tvrzení, kterému se #97 vyhýbá.
        guard summary.calledReportFindings || !summary.findings.isEmpty else { return nil }
        return summary
    }

    func snapshot(ofSession sessionID: String, in worktree: URL, at time: Date) async throws -> RawTranscript? {
        let url = transcript(ofSession: sessionID, in: worktree)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        let handle = try FileHandle(forReadingFrom: url)
        // Zavření je `try?` **schválně**: soubor se jen čte, takže na něm není co ztratit — a chyba
        // ze zavírání by přebila obsah, kvůli kterému se sheet otevřel. Jediné, co se tím riskuje,
        // je deskriptor, a ten `FileHandle` uvolní i sám.
        defer { try? handle.close() }

        // **Čte se od konce, protože je to lokální soubor** — u logu checku to nešlo (`Range` přes
        // `gh` se na redirect nepřenese, změřeno u #214), takže tam musel být strop na velikost.
        // Tady žádný není: 53MB transcript se otevře stejně jako ten o 200 kB.
        let total = Int(try handle.seekToEnd())
        let window = Policy.rawSessionWindow(fileBytes: total)
        try handle.seek(toOffset: UInt64(window.offset))
        let raw = try handle.read(upToCount: window.length) ?? Data()

        let dropped = Policy.rawSessionPrefixDrop(raw, isTail: window.offset > 0)
        let body = raw.dropFirst(dropped)
        // **Ne `String(decoding:as:)`.** Ten nikdy neselže — nahradí vadné bajty `U+FFFD` —, takže
        // by se z „soubor nemá platné UTF-8“ stal přepis s otazníky uprostřed a stav, který má
        // nabídnout `Ukázat v Finderu`, by v okně nebyl vidět vůbec.
        guard let text = String(data: body, encoding: .utf8) else {
            throw TranscriptUnreadable.invalidEncoding
        }

        let transcribed = TranscriptTranscriber(worktree: worktree).transcribe(TextLines.content(text))
        return RawTranscript(
            events: transcribed.events,
            omittedBytes: window.offset + dropped,
            fileBytes: total,
            takenAt: time,
            unreadableLines: transcribed.unreadableLines
        )
    }

    func size(ofSession sessionID: String, in worktree: URL) async -> Int? {
        let url = transcript(ofSession: sessionID, in: worktree)
        // `try?` je tady ta správná odpověď: velikost, kterou se nepovedlo zjistit, znamená
        // „o přírůstku nic nevíme“ — a to je stav, který se v patičce **nekreslí**, ne stav, který
        // by se ztratil (viz `Policy.rawSessionGrowth`).
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.intValue
    }

    private func transcript(ofSession sessionID: String, in worktree: URL) -> URL {
        TranscriptLocation.transcript(ofSession: sessionID, in: worktree, projects: projects)
    }
}
