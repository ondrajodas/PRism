import Foundation

/// Texty sheetu s kódem a s logem (#417, sekce 28 návrhu).
///
/// Vlastní typ ze stejného důvodu jako `RawSessionText`: věty, které tvrdí něco o datech, se dají
/// vyčerpat testem jen tehdy, když nejsou schované v těle view.
enum CodeSheetText {
    // MARK: - Hlavička hunku

    static func hunkTitle(path: String) -> String { "Hunk — \(path)" }

    /// Hlavička hunku a **co se kreslí** — pull request, nebo commit v tabu `Commity`.
    ///
    /// Návrh tady kreslí krátkou sha commitu; `subject` je to samé o krok obecněji, protože sheet
    /// se otevírá i nad diffem pull requestu, kde žádný jeden commit není.
    static func hunkSlug(header: String, subject: String) -> String {
        guard !header.isEmpty else { return subject }
        guard !subject.isEmpty else { return header }
        return "\(header) · \(subject)"
    }

    /// Třetí řádka hlavičky hunku. **Že je to nová verze bez znaků změny, netvrdí UI nikde jinde** —
    /// a je to zrovna to, co se ze sheetu kopíruje, takže překvapení patří do hlavičky, ne do
    /// schránky.
    static func hunkNote(code: String) -> String {
        let count = Policy.codeSheetLines(of: code).count
        let lines = Plural.czech(count, one: "řádek", few: "řádky", many: "řádků")
        return "nová verze, \(lines) — bez znaků změny a bez čísel řádků, přesně tak, jak se zkopíruje"
    }

    // MARK: - Hlavička logu

    static func logTitle(check: String) -> String { "Celý log — \(check)" }

    /// `job.log · 24 918 řádků · 2,7 MB · keboola/vault#412`.
    ///
    /// Počet řádků i velikost se **spočítají při stažení** (`JobLog`), ne tady: scan megabajtů při
    /// každém překreslení hlavičky je zrovna to, co zakazuje #224.
    static func logSlug(_ log: JobLog, subject: String) -> String {
        let lines = Plural.czech(log.lineCount, one: "řádek", few: "řádky", many: "řádků")
        let size = log.byteCount.formatted(.byteCount(style: .file))
        return "job.log · \(lines) · \(size) · \(subject)"
    }

    /// Třetí řádka hlavičky logu — **dvě podoby**, a je to jediné, co se mezi stavem „běží“
    /// a „doběhl“ mění.
    ///
    /// **Doběhlému jobu se log neříká snímek**: slovo „snímek“ nese informaci jen tam, kde se text
    /// pod rukama mění, a u doběhlého jobu by varovalo před něčím, co se nemůže stát — takové věty
    /// se pak přehlíží i tam, kde platí.
    ///
    /// Za tím je věta o tom, **čím ten text je**, a ta platí v obou stavech: log v sheetu je surový,
    /// jen bez ANSI, takže s timestampy a bez ořezu, kterým se řídí konec logu v tabu.
    static func logNote(outcome: PullRequestCheck.Outcome, duration: TimeInterval?, at moment: Date?) -> String {
        "\(logState(outcome: outcome, duration: duration, at: moment)) \(logMaterial)"
    }

    /// Z čeho je log — platí v obou stavech, takže stojí zvlášť.
    static var logMaterial: String {
        let limit = Policy.logTailLines.formatted(.number.grouping(.automatic))
        return "Surový, jen bez ANSI: s timestampy a bez ořezu na \(limit) řádků."
    }

    private static func logState(
        outcome: PullRequestCheck.Outcome,
        duration: TimeInterval?,
        at moment: Date?
    ) -> String {
        let time = moment.map { " \($0.formatted(date: .omitted, time: .standard))" } ?? ""
        guard outcome != .running else {
            return "Snímek z\(time) — job pořád běží, takže log od té chvíle narostl."
        }
        let ran = duration.map { " po \(RunUsageText.duration(.seconds($0)))" } ?? ""
        return "\(verb(of: outcome))\(time)\(ran) — log je celý, nic už k němu nepřibude."
    }

    /// **Sloveso, ne „prošlo/selhalo“ ze seznamu checků** (`ChecksText.detail`): tam je to výčet za
    /// jménem jobu, tady začátek věty o něm.
    private static func verb(of outcome: PullRequestCheck.Outcome) -> String {
        switch outcome {
        case .passed: "Job prošel"
        case .failed: "Job selhal"
        case .cancelled: "Job byl zrušen"
        case .skipped: "Job se přeskočil"
        // Běžící job se sem nedostane, rozhoduje o něm `logState`; výčet je vyčerpaný schválně,
        // aby nový stav checku vyžadoval rozhodnutí, ne aby spadl do `default`u.
        case .running: "Job běží"
        }
    }

    // MARK: - Patička

    static let close = "Zavřít"
    static let openOnGitHub = "Otevřít celý log na GitHubu ↗"
    static let copyAll = "Zkopírovat vše"
    static let copied = "Zkopírováno"

    /// Kolik řádků se nevešlo na šířku. `nil` = vešly se všechny.
    ///
    /// **Bez téhle věty vypadá zalomený řádek jako dva** — a i nejširší rozumný sheet dlouhý řádek
    /// zalomí (nejdelší ze 128 měřených hunků měl 181 znaků, p99 149).
    static func overflow(_ overflow: CodeSheetOverflow?) -> String? {
        guard let overflow else { return nil }
        let lines = Plural.czech(
            overflow.wrapped,
            one: "řádek z \(overflow.total) se nevešel",
            few: "řádky z \(overflow.total) se nevešly",
            many: "řádků z \(overflow.total) se nevešlo"
        )
        return "\(lines) na šířku"
    }
}
