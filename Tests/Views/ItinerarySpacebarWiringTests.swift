import Foundation
import Testing

@testable import PRism

/// Zapojení mezerníku (#507) — **co všechno musí platit, aby si aplikace směla vzít holou
/// klávesu**.
///
/// Rozhodnutí samo je v `Policy` a testuje ho `ItineraryWalkTests`; tady se tvrdí to druhé:
/// že se `Policy` ptá **na skutečné vstupy**. Obojí se rozbije potichu — pole, které přestane
/// hlásit fokus, se pozná tím, že uprostřed psaní odskočí obrazovka, a tab, který přestane
/// hlásit konec obsahu, tím, že „mezerník občas nefunguje“.
@Suite("Zapojení mezerníku po itineráři (#507)")
struct ItinerarySpacebarWiringTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Source {
        let path: String
        /// Jen kód — řádky, které začínají `//`, jsou pryč. O mezerníku se v dokumentaci mluví
        /// a vysvětlení nemá test zakazovat (tatáž konstrukce jako `EmojiFieldWiringTests`).
        let code: String
    }

    private func sources(under folder: String) throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw SourceError.unreadable(root.path) }

        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append(
                Source(path: url.path.replacingOccurrences(of: root.path + "/", with: ""), code: code)
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    // MARK: - Kde stojí výřez

    private let pr = PRIdentifier("keboola/vault#85")!
    private let other = PRIdentifier("keboola/vault#86")!

    /// Nezměřeno je **`nil`**, ne „není na konci“ — a `Policy` z toho dělá totéž rozhodnutí, jen
    /// z jiného důvodu. Rozdíl je vidět odsud: `nil` znamená, že se nikoho nemá cenu ptát.
    @Test("Bez hlášení se o konci obsahu netvrdí nic")
    func withoutAReportNothingIsClaimed() {
        let state = ContentEndState()

        #expect(state.isAtEnd(of: pr, in: .filesChanged) == nil)
    }

    @Test("Hlášení platí pro ten tab a ten pull request, ze kterého přišlo")
    func aReportOnlyCountsWhereItCameFrom() {
        let state = ContentEndState()
        state.note(true, of: pr, in: .filesChanged)

        #expect(state.isAtEnd(of: pr, in: .filesChanged) == true)
        // **Tohle je to tvrzení, že se něco NEstane**: hodnota z jiného tabu ani z jiného PR
        // se nepřebírá, protože obsah na obrazovce je jiný.
        #expect(state.isAtEnd(of: pr, in: .checks) == nil)
        #expect(state.isAtEnd(of: other, in: .filesChanged) == nil)

        state.note(false, of: pr, in: .filesChanged)
        #expect(state.isAtEnd(of: pr, in: .filesChanged) == false)
    }

    /// **Konec se měří přesně v těch tabech, do kterých itinerář ukazuje.** Kdyby jeden ubyl,
    /// mezerník by v něm mlčky přestal fungovat; kdyby přibyl tab bez zastávky, klávesa by se
    /// brala tam, kde dráha nic neříká.
    @Test("Konec obsahu hlásí právě ty taby, do kterých vedou zastávky")
    func exactlyTheStopTabsReportTheEnd() throws {
        let stops = Policy.itinerary(
            ItineraryFacts(
                hasVisitRecord: true,
                commitsSinceVisit: 2,
                descriptionKnown: true,
                hasDescription: true,
                fileCount: 3,
                checks: ChecksSummary(passed: 1, failed: 0, running: 0, skipped: 0)
            )
        )
        #expect(stops.count == 5)

        let detail = try #require(
            try sources(under: "App").first { $0.path == "Views/PullRequestDetailView.swift" }
        )
        var reported: Set<String> = []
        for line in TextLines.content(detail.code) where line.contains("contentEnd.note(") {
            guard let range = line.range(of: "in: \\.[a-zA-Z]+", options: .regularExpression)
            else { continue }
            reported.insert(String(line[range].dropFirst("in: .".count)))
        }

        #expect(reported == Set(stops.map(\.tab.rawValue)))
        #expect(reported == ["overview", "filesChanged", "checks"])
    }

    // MARK: - Kdo hlásí fokus

    @Test("Fokus dvou polí přežije pořadí, ve kterém se ohlásí")
    func focusSurvivesTheOrderOfTheTwoReports() {
        let focus = TextFieldFocus()
        let first = UUID()
        let second = UUID()

        #expect(!focus.isEditing)
        focus.note(first, isFocused: true)
        #expect(focus.isEditing)
        // Nové pole se ohlásí **dřív**, než staré ztratí fokus — a mezi tím se nesmí objevit
        // okamžik, ve kterém okno tvrdí, že se nikde nepíše.
        focus.note(second, isFocused: true)
        focus.note(first, isFocused: false)
        #expect(focus.isEditing)
        focus.note(second, isFocused: false)
        #expect(!focus.isEditing)
    }

    @Test("Druhé odhlášení téhož pole nic nerozbije")
    func releasingTheSameFieldTwiceIsHarmless() {
        let focus = TextFieldFocus()
        let field = UUID()

        focus.note(field, isFocused: true)
        focus.note(field, isFocused: false)
        focus.note(field, isFocused: false)
        #expect(!focus.isEditing)
    }

    /// **Jmenovitý výčet polí, ne počet.** Pole, které přestane hlásit fokus, si mezerník vezme
    /// uprostřed psaní — a je to přesně ta věc, kterou testovací host nezjistí, protože klávesnici
    /// nemá.
    ///
    /// `DraftTextField` je v seznamu **za čtyři composery naráz** (tělo review, komentář pod PR,
    /// odpověď do vlákna, prompt v `Zeptat se`): rámeček mají společný, takže hlášení je taky
    /// jedno.
    @Test("Fokus hlásí právě čtyři pole a jsou to ta čtyři")
    func exactlyFourFieldsReportFocus() throws {
        let reporting = try sources(under: "App")
            .filter { $0.code.contains(".reportsTextFieldFocus(") }
            .map(\.path)
            .sorted()

        #expect(reporting == [
            // Paleta ⌘K — leží nad detailem PR, jehož zkratky v hierarchii zůstávají.
            "Views/CommandPaletteView.swift",
            // Pruh hledání v diffu (#152).
            "Views/DiffSearchBar.swift",
            // Společný rámeček všech čtyř composerů.
            "Views/DraftTextField.swift",
            // Hledání v popoveru labelů a reviewerů (#392).
            "Views/PickerSearchField.swift",
        ])
    }

    /// Druhá půlka téže stráže: **pole, které fokus drží, ho musí i nasazovat**. Samotné
    /// `.focused($…)` bez hlášení je přesně ten stav, ve kterém mezerník sebere psaní.
    @Test("Každé pole s vlastním fokusem ho hlásí do okna")
    func everyFieldWithItsOwnFocusReportsIt() throws {
        let owners = try sources(under: "App")
            .filter { $0.code.contains("@FocusState") }
            .map(\.path)
            .sorted()

        #expect(owners == [
            "Views/CommandPaletteView.swift",
            "Views/DiffSearchBar.swift",
            "Views/DraftTextField.swift",
            "Views/PickerSearchField.swift",
            // Okno nastavení je **vlastní scéna**, ne tohle okno: zkratky detailu PR se s ním
            // nepotkají, takže nemá co hlásit.
            "Views/Settings/OrganizationListEditor.swift",
        ])
    }
}
