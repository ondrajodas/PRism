import Foundation
import Testing

@testable import PRism

/// Stav značky `Prošlo` (#500) — **vyčerpávající výčet**, protože je to čistá funkce a je to
/// jediné místo, kde se rozhoduje, jestli přečtený soubor pořád platí.
@Suite("Policy — stav značky Prošlo")
struct FileReviewStateTests {
    private let at = Date(timeIntervalSince1970: 1_000)

    private func mark(_ blobs: String?) -> ReadMark { ReadMark(blobs: blobs, markedAt: at) }

    /// Devět kombinací: **záznam** (není / s otiskem / bez otisku) × **otisk dnes** (týž / jiný /
    /// žádný). Bez záznamu je odpověď vždycky `unread`, se záznamem rozhoduje jediná rovnost —
    /// zbylých šest je v testech pod tímhle.
    @Test("Bez záznamu je soubor nepřečtený, ať je otisk jakýkoli")
    func unmarkedFilesAreAlwaysUnread() {
        for blobs in ["aaa..bbb", "ccc..ddd", nil] {
            #expect(Policy.fileReviewState(mark: nil, blobs: blobs) == .unread)
        }
    }

    @Test("Týž otisk znamená prošlo")
    func sameBlobsStayRead() {
        #expect(Policy.fileReviewState(mark: mark("aaa..bbb"), blobs: "aaa..bbb") == .read(at: at))
    }

    @Test("Jiný otisk znamená změněno od prošlého")
    func differentBlobsGoStale() {
        #expect(
            Policy.fileReviewState(mark: mark("aaa..bbb"), blobs: "aaa..ccc") == .changed(readAt: at)
        )
    }

    /// Otisk **zmizel** — soubor, který se změnil na přejmenování beze změny obsahu. Přečtené
    /// řádky v něm už nejsou, takže je to změna.
    @Test("Otisk zmizel — změněno od prošlého")
    func vanishedBlobsGoStale() {
        #expect(Policy.fileReviewState(mark: mark("aaa..bbb"), blobs: nil) == .changed(readAt: at))
    }

    /// Otisk **přibyl** — zaškrtávalo se nad přejmenováním beze změny obsahu a dnes už soubor
    /// obsah mění. Taky změna.
    @Test("Otisk přibyl — změněno od prošlého")
    func appearedBlobsGoStale() {
        #expect(Policy.fileReviewState(mark: mark(nil), blobs: "aaa..bbb") == .changed(readAt: at))
    }

    /// **Dvakrát „nevím“ je prošlo, ne změna.** Kdyby se `nil == nil` počítalo jako změna, značka
    /// nad přejmenováním beze změny obsahu by po zaškrtnutí hned zhasla na `změněno od prošlého`
    /// a nešla by udržet ani na vteřinu.
    @Test("Chybějící otisk na obou stranách znamená prošlo")
    func missingBlobsOnBothSidesStayRead() {
        #expect(Policy.fileReviewState(mark: mark(nil), blobs: nil) == .read(at: at))
    }

    /// Do počtu `3 prošlé` se počítá **jen `read`**: `changed` je pobídka, ne hotová práce.
    @Test("Do počtu prošlých se změněné nepočítá")
    func changedDoesNotCount() {
        let states: [String: FileReviewState] = [
            "a": .read(at: at),
            "b": .changed(readAt: at),
            "c": .read(at: at),
            "d": .unread,
        ]

        #expect(Policy.readFileCount(in: states) == 2)
    }

    @Test("Mapa stavů nese jen soubory se značkou")
    func statesCarryOnlyMarkedFiles() {
        let files = [file("src/Cart.swift", blobs: "aaa..bbb"), file("src/Order.swift", blobs: "x..y")]
        let marks = ReadMarks(pullRequest: pr, marks: ["src/Cart.swift": mark("aaa..bbb")])

        let states = Policy.fileReviewStates(of: files, marks: marks)

        #expect(states == ["src/Cart.swift": .read(at: at)])
    }

    /// Značka na soubor, který v diffu **není** (vypadl z PR), se do mapy nedostane — mapa
    /// popisuje diff, ne obsah souboru se značkami.
    @Test("Značka bez souboru v diffu se do mapy nedostane")
    func marksWithoutFilesAreDropped() {
        let marks = ReadMarks(pullRequest: pr, marks: ["zmizel.swift": mark("a..b")])

        #expect(Policy.fileReviewStates(of: [file("src/Cart.swift", blobs: "x..y")], marks: marks).isEmpty)
    }

    @Test("Bez značek je mapa prázdná")
    func noMarksMeansNoStates() {
        #expect(Policy.fileReviewStates(of: [file("a.swift", blobs: "x..y")], marks: nil).isEmpty)
    }

    // MARK: - Sbalení

    /// **Sbalení se řídí značkou, ne stavem view**: bez odchylky je prošlý soubor sbalený
    /// a změněný rozbalený — přesně ta úspora, kvůli které značka existuje.
    @Test("Bez odchylky rozhoduje značka")
    func foldingFollowsTheMark() {
        let cases: [(FileReviewState, Bool)] = [
            (.unread, false),
            (.read(at: at), true),
            (.changed(readAt: at), false),
        ]
        for (state, folded) in cases {
            #expect(Policy.isFileFolded(state: state, override: nil) == folded)
        }
    }

    /// **Odchylka přebíjí značku v obou směrech.** `Rozbalit vše` je výslovný pokyn, takže rozbalí
    /// i prošlé; ruční sbalení nepřečteného souboru drží.
    @Test("Odchylka přebíjí značku")
    func overrideWins() {
        let cases: [(FileReviewState, Bool)] = [
            (.read(at: at), false),
            (.unread, true),
            (.changed(readAt: at), true),
        ]
        for (state, override) in cases {
            #expect(Policy.isFileFolded(state: state, override: override) == override)
        }
    }

    // MARK: - Popisky

    @Test("Hlavička stromu mlčí, dokud není zaškrtnuté nic")
    func summaryWithoutMarks() {
        #expect(Policy.fileTreeSummary(files: 7, read: 0) == "7 souborů")
    }

    @Test("Hlavička stromu skloňuje obě poloviny")
    func summaryDeclinesBothHalves() {
        #expect(Policy.fileTreeSummary(files: 7, read: 3) == "7 souborů · 3 prošlé")
        #expect(Policy.fileTreeSummary(files: 1, read: 1) == "1 soubor · 1 prošlý")
        #expect(Policy.fileTreeSummary(files: 9, read: 5) == "9 souborů · 5 prošlých")
    }

    /// Proužek nad nezapočatým PR **není** — prázdná linka je stálý prvek bez informace.
    @Test("Podíl se nekreslí, dokud není co ukázat")
    func shareIsNilWithoutProgress() {
        #expect(Policy.readFileShare(read: 0, of: 7) == nil)
        #expect(Policy.readFileShare(read: 0, of: 0) == nil)
        #expect(Policy.readFileShare(read: 3, of: 0) == nil)
    }

    @Test("Podíl se počítá z počtu souborů a nepřeteče")
    func shareIsBounded() {
        #expect(Policy.readFileShare(read: 3, of: 6) == 0.5)
        #expect(Policy.readFileShare(read: 9, of: 7) == 1)
    }

    /// U změněného souboru tlačítko neříká stav, ale co udělá.
    @Test("Popisek zaškrtávátka")
    func toggleTitles() {
        #expect(Policy.readToggleTitle(of: .unread) == "Prošlo")
        #expect(Policy.readToggleTitle(of: .read(at: at)) == "Prošlo")
        #expect(Policy.readToggleTitle(of: .changed(readAt: at)) == "Prošlo znovu")
    }

    @Test("Kapsli `změněno od prošlého` dostane jedině změněný soubor")
    func changedPillOnlyWhenChanged() {
        #expect(Policy.changedSinceReadLabel(of: .unread) == nil)
        #expect(Policy.changedSinceReadLabel(of: .read(at: at)) == nil)
        #expect(Policy.changedSinceReadLabel(of: .changed(readAt: at)) == "změněno od prošlého")
    }

    /// Nápověda se skládá na jednom místě i s klávesou z katalogu (#441) — kombinace se nikde
    /// neopisuje vedle té skutečné.
    @Test("Nápověda nese klávesu z katalogu")
    func helpCarriesTheShortcut() {
        #expect(Policy.readToggleHelp(of: .unread).hasSuffix("(⌥V)"))
        #expect(Policy.readToggleHelp(of: .changed(readAt: at)).hasSuffix("(⌥V)"))
    }

    // MARK: - Pomůcky

    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 1)

    private func file(_ path: String, blobs: String?) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: [],
            blobs: blobs
        )
    }
}
