import Foundation
import Testing

@testable import PRism

/// Snímek transcriptu ze disku (#327) — proti **skutečným souborům** v dočasné složce, protože
/// právě o disk tu jde: okno se čte `seek`em od konce a rozdíl mezi „není“, „nedá se přečíst“
/// a „prázdný“ vzniká tady.
@Suite("Snímek transcriptu")
struct RawTranscriptSnapshotTests {
    private let directory: TemporaryDirectory
    private let worktree = URL(filePath: "/Users/ondra/cache/worktrees/o/r/3-abc")
    private let taken = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        directory = try TemporaryDirectory()
    }

    private var store: TranscriptStore { TranscriptStore(projects: directory.url) }

    private func url(_ sessionID: String) -> URL {
        TranscriptLocation.transcript(ofSession: sessionID, in: worktree, projects: directory.url)
    }

    private func write(_ data: Data, as sessionID: String) throws {
        let url = url(sessionID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private func snapshot(_ sessionID: String) async throws -> RawTranscript? {
        try await store.snapshot(ofSession: sessionID, in: worktree, at: taken)
    }

    /// Jeden řádek transcriptu s prózou modelu — tvar je z fixture `transcript/review-session.jsonl`.
    private func line(_ text: String) -> String {
        let head = "{\"type\":\"assistant\",\"timestamp\":\"2026-08-09T21:44:29.241Z\","
        return head + "\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"\(text)\"}]}}"
    }

    // MARK: - Tři různá „přepis tu není“

    /// Konečná odpověď: strom mohl sebrat úklid cache, takže už nebude.
    @Test("Chybějící transcript je nic, ne chyba")
    func missingIsNothing() async throws {
        #expect(try await snapshot("nikdy-nebyla") == nil)
    }

    /// **Ne `String(decoding:as:)`.** Ten by vadné bajty nahradil `U+FFFD`, takže by se ze stavu,
    /// který má nabídnout `Ukázat v Finderu`, stal přepis s otazníky uprostřed.
    @Test("Vadné UTF-8 je chyba s přečtitelným důvodem, ne přepis s otazníky")
    func invalidEncodingThrows() async throws {
        try write(Data([0xFF, 0xFE, 0x41, 0x0A]), as: "rozbita")

        await #expect(throws: TranscriptUnreadable.invalidEncoding) {
            try await snapshot("rozbita")
        }
    }

    /// Prázdný soubor se přečte v pořádku a vydá nic — a `TranscriptStore` ten stav sám nerozlišuje.
    /// Rozliší ho `Policy.rawSessionState`, tady se jen ověřuje, že se z něj nestane pád ani chyba.
    @Test("Prázdný soubor dá snímek bez událostí")
    func anEmptyFileGivesAnEmptySnapshot() async throws {
        try write(Data(), as: "prazdna")

        let snapshot = try #require(await snapshot("prazdna"))

        #expect(snapshot.events.isEmpty)
        #expect(snapshot.fileBytes == 0)
        #expect(Policy.rawSessionState(of: snapshot) == .empty(bytes: 0))
    }

    // MARK: - Okno

    @Test("Malý transcript se přečte celý a nic se nepřiznává")
    func aSmallTranscriptIsWholeAndAdmitsNothing() async throws {
        let text = (0..<5).map { line("krok \($0)") }.joined(separator: "\n") + "\n"
        try write(Data(text.utf8), as: "mala")

        let snapshot = try #require(await snapshot("mala"))

        #expect(snapshot.events.count == 5)
        #expect(!snapshot.isTruncated)
        #expect(snapshot.omittedBytes == 0)
        #expect(snapshot.takenAt == taken)
        #expect(RawSessionText.topCut(snapshot) == nil)
    }

    /// Okno je ocas souboru, takže první řádek je obvykle zbytek řádku, jehož začátek leží před
    /// oknem — a takový zbytek není JSON. Bez zarovnání by z něj byl nečitelný řádek u **každého**
    /// zkráceného transcriptu.
    @Test("Z velkého transcriptu se čte konec a zkrácení se přizná")
    func aBigTranscriptIsCutAndAdmitsIt() async throws {
        // Řádky o ~4 kB, dokud se soubor nepřehoupne přes strop okna o kus.
        let padding = String(repeating: "x", count: 4000)
        var text = ""
        var index = 0
        while text.utf8.count < Policy.rawSessionWindowBytes + 200_000 {
            text += line("\(index) \(padding)") + "\n"
            index += 1
        }
        try write(Data(text.utf8), as: "velka")

        let snapshot = try #require(await snapshot("velka"))

        #expect(snapshot.isTruncated)
        #expect(snapshot.omittedBytes > 200_000)
        #expect(snapshot.fileBytes == text.utf8.count)
        // Zarovnání zabralo: ani jeden řádek okna nebyl nečitelný.
        #expect(snapshot.unreadableLines == 0)
        // A přiznává se to — druhé ze tří přiznání zkrácení.
        #expect(RawSessionText.topCut(snapshot)?.hasPrefix("starších") == true)
        #expect(RawSessionText.subtitle(snapshot).contains("konec souboru"))
    }

    /// Ten změřený případ: nejdelší řádek transcriptu má 7,5 MB, tedy **víc než celé okno**. Prázdný
    /// sheet nad souborem, ve kterém něco je, by byl horší než jedna nečitelná událost.
    @Test("Řádek delší než celé okno dá jednu nečitelnou událost, ne prázdno")
    func aLineLongerThanTheWholeWindow() async throws {
        let huge = String(repeating: "q", count: Policy.rawSessionWindowBytes + 500_000)
        try write(Data("{\"type\":\"user\",\"payload\":\"\(huge)\"}\n".utf8), as: "obri")

        let snapshot = try #require(await snapshot("obri"))

        #expect(snapshot.isTruncated)
        #expect(snapshot.unreadableLines == 1)
        let event = try #require(snapshot.events.first)
        #expect(snapshot.events.count == 1)
        #expect(event.kind == .unreadable)
        // Tělo je ořezané na strop události, ne na celé okno.
        #expect(event.body?.utf8.count == Policy.rawSessionEventBytes)
        #expect(Policy.rawSessionState(of: snapshot) != .empty(bytes: snapshot.fileBytes))
    }

    /// **Okno, které začíná přesně na hranici řádku, o svou první událost nepřijde.** Zarovnání
    /// zahazuje zbytek řádku před oknem — jenže když `fileBytes − 4 MB` padne přesně na začátek
    /// řádku, není co zahazovat, a hledání „prvního zakončení v okně“ by sebralo celou první
    /// událost a `omittedBytes` by tvrdil větší zkrácení, než nastalo. Nálezem Copilota na #408.
    ///
    /// Zařídit ten stav jde spočítat: řádky **o 128 bajtech** (127 znaků JSONu a zakončení) padnou
    /// na hranici okna vždycky, protože 4 MB je 32 768 × 128.
    @Test("Okno zarovnané na hranici řádku o první událost nepřijde")
    func aWindowThatStartsOnALineBoundaryKeepsItsFirstEvent() async throws {
        let lineLength = 128
        let head = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\""
        let tail = "\"}]}}"
        let padding = lineLength - 1 - head.utf8.count - tail.utf8.count
        var text = ""
        // O tisíc řádků víc, než se do okna vejde — okno tedy začne na hranici řádku.
        for index in 0..<(Policy.rawSessionWindowBytes / lineLength + 1_000) {
            text += head + String(repeating: "\(index % 10)", count: padding) + tail + "\n"
        }
        try write(Data(text.utf8), as: "zarovnana")

        let snapshot = try #require(await snapshot("zarovnana"))

        #expect(snapshot.isTruncated)
        #expect(snapshot.unreadableLines == 0)
        // Okno je 4 MB řádků po 128 bajtech, celých — ani jedna událost se neztratila.
        #expect(snapshot.events.count == Policy.rawSessionWindowBytes / lineLength)
        #expect(snapshot.omittedBytes == 1_000 * lineLength)
    }

    // MARK: - Velikost pro patičku

    @Test("Velikost se čte bez druhého čtení okna")
    func sizeIsReadWithoutReadingTheWindow() async throws {
        try write(Data("abc\n".utf8), as: "velikost")

        #expect(await store.size(ofSession: "velikost", in: worktree) == 4)
    }

    /// Zmizelá velikost znamená „o přírůstku nic nevíme“, ne chybu, která by přebila přepis.
    @Test("Velikost chybějícího souboru je nic")
    func sizeOfAMissingFileIsNothing() async {
        #expect(await store.size(ofSession: "nikdy-nebyla", in: worktree) == nil)
    }
}
