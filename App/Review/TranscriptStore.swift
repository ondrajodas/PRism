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
}

/// `TranscriptReading` nad skutečným `~/.claude/projects/`.
struct TranscriptStore: TranscriptReading {
    private let projects: URL
    private let parser = StreamParser()

    init(projects: URL = TranscriptLocation.defaultProjects) {
        self.projects = projects
    }

    func summary(ofSession sessionID: String, in worktree: URL) async throws -> StreamSummary? {
        let url = TranscriptLocation.transcript(ofSession: sessionID, in: worktree, projects: projects)
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
}
