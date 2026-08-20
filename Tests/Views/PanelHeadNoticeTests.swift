import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Panel u staršího commitu nekreslí nálezy jako platné** (#392).
///
/// Je to tvrdá podmínka č. 5 přepsaná do věty, takže se testuje ze tří stran:
///
/// 1. **Text** — věta jmenuje obě sha a u neshody říká, že o kódu na obrazovce nemluví. Bere se
///    z `Policy`, tedy ten, který uvidí člověk.
/// 2. **Že panel na notici reaguje** — tři stavy dají tři různé obrázky. Kdyby se `headNotice`
///    zapomněl předat, byly by dva z nich shodné, a právě to je ta regrese, která se nepozná jinak
///    než pohledem na okno.
/// 3. **Že ztlumení je jen u neshody** — rozhoduje `dimsFindings`, ne kresba.
@MainActor
@Suite("Nálezy u staršího commitu (#392)")
struct PanelHeadNoticeTests {
    private static let head = "e8d4a60f1c2d3e4f5061728394a5b6c7d8e9f012"
    private static let older = "5e2b1aa31f6c0a2a7f2f0a1b3c4d5e6f70819293"

    // MARK: - Věta

    @Test("Klidná věta jmenuje hlavu, ke které nálezy patří")
    func theCalmSentenceNamesTheHead() throws {
        let sentence = try #require(Policy.FindingsHeadNotice.head(Self.head).czechSentence)

        #expect(sentence.contains("e8d4a60"))
        #expect(!sentence.contains("nemluví"), "nad seznamem nálezy platí, takže se nevaruje")
    }

    /// **Výstraha musí jmenovat obojí** — hlavu i commit na obrazovce. Bez druhé sha by z věty
    /// nebylo poznat, proti čemu se to porovnává.
    @Test("Výstraha jmenuje hlavu i commit na obrazovce")
    func theWarningNamesBoth() throws {
        let sentence = try #require(
            Policy.FindingsHeadNotice.mismatch(head: Self.head, commit: Self.older).czechSentence
        )

        #expect(sentence.contains("e8d4a60"))
        #expect(sentence.contains("5e2b1aa"))
        #expect(sentence.contains("o kódu na obrazovce nemluví"))
    }

    /// Sha se krátí na sedm znaků, jako všude jinde v okně — celých čtyřicet by se do panelu
    /// nevešlo a věta by se zalomila doprostřed hashe.
    @Test("Sha ve větě je zkrácená na sedm znaků")
    func shasAreShortened() throws {
        let sentence = try #require(
            Policy.FindingsHeadNotice.mismatch(head: Self.head, commit: Self.older).czechSentence
        )

        #expect(!sentence.contains(Self.head))
        #expect(!sentence.contains(Self.older))
    }

    @Test("Bez notice není co říct")
    func silenceHasNoSentence() {
        #expect(Policy.FindingsHeadNotice.none.czechSentence == nil)
    }

    // MARK: - Že panel na notici reaguje

    /// **Tři stavy, tři různé obrázky.** Kdyby panel `headNotice` ignoroval (typicky proto, že ho
    /// někdo zapomene předat z detailu), vyšly by všechny tři stejně — a v okně by u staršího
    /// commitu stály nálezy bez jediného varování.
    ///
    /// Vloženou regresí ověřeno: s `headNotice: .none` zadrátovaným v panelu tenhle test spadne.
    @Test("Panel kreslí tři různé obrázky pro tři stavy notice")
    func thePanelReactsToTheNotice() throws {
        let silent = try Self.render(.none)
        let calm = try Self.render(.head(Self.head))
        let warning = try Self.render(.mismatch(head: Self.head, commit: Self.older))

        #expect(silent != calm, "klidná věta se nenakreslila")
        #expect(calm != warning, "výstraha vypadá stejně jako klidná věta")
        #expect(silent != warning, "výstraha se nenakreslila")
    }

    /// Výstraha je **vyšší** než klidná věta: nese dvě věty a odsazení pod sebou, takže se z výšky
    /// pozná, že se nakreslila ona a ne ta krátká.
    ///
    /// A **bez notice se nekreslí nic** — `ImageRenderer` nad prázdným view nevydá ani obrázek, což
    /// je z těch tří tvrzení to nejtvrdší: prázdná notice nezabere v panelu ani bod.
    @Test("Výstraha je vyšší než klidná věta a bez notice se nekreslí nic")
    func theWarningIsTallerThanTheSentence() throws {
        let calm = try #require(Self.height(of: .head(Self.head)))
        let warning = try #require(Self.height(of: .mismatch(head: Self.head, commit: Self.older)))

        #expect(warning > calm)
        #expect(Self.height(of: .none) == nil, "bez notice se nekreslí nic")
    }

    // MARK: - Ztlumení

    /// Ztlumení je **jen u neshody**. U klidné věty by tvrdilo, že s nálezy něco není v pořádku, a u
    /// prázdné notice by ztlumilo nálezy v `Přehledu`.
    @Test("Ztlumené jsou karty jedině u neshody")
    func onlyTheMismatchDims() {
        #expect(Policy.FindingsHeadNotice.mismatch(head: Self.head, commit: Self.older).dimsFindings)
        #expect(!Policy.FindingsHeadNotice.head(Self.head).dimsFindings)
        #expect(!Policy.FindingsHeadNotice.none.dimsFindings)
    }

    // MARK: - Scéna

    /// Panel s jedním blokujícím nálezem — na cizím PR, tedy s `Mojím review` a bez akcí u labelů.
    @MainActor private static func panel(_ notice: Policy.FindingsHeadNotice) -> some View {
        let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14119)
        let finding = makeFinding(
            file: "SecretClient.php",
            line: 81,
            category: "correctness",
            summary: "Prázdný secret projde fallbackem dál jako platný."
        )
        return ReviewPanel(
            record: makeRecord(runs: [makeStoredRun(findings: [finding.reported])], headSha: head),
            isExpanded: .constant(true),
            jump: { _ in },
            findings: [finding],
            pullRequest: pr,
            headNotice: notice,
            tab: .constant(.findings)
        )
        .frame(width: 306, height: 320)
    }

    /// **Surové pixely, ne `tiffRepresentation`.** TIFF ze dvou renderů se liší, i když je obrázek
    /// týž (obálka nese metadata), takže by porovnání vycházelo různě vždycky — a test by prošel
    /// i nad panelem, který notici ignoruje. Ověřeno vloženou regresí: se zadrátovaným `.none`
    /// v panelu na `tiffRepresentation` **prošel**, na bajtech bitmapy spadne.
    private static func render(_ notice: Policy.FindingsHeadNotice) throws -> Data {
        let renderer = ImageRenderer(content: panel(notice))
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    /// Výška samotné věty — z ní se pozná, která z obou podob se nakreslila. `nil` znamená, že se
    /// nenakreslilo **nic**: `ImageRenderer` nad prázdným view obrázek nevydá.
    private static func height(of notice: Policy.FindingsHeadNotice) -> CGFloat? {
        let renderer = ImageRenderer(content: FindingsHeadNoticeView(notice: notice).frame(width: 280))
        renderer.scale = 1
        return renderer.nsImage?.size.height
    }
}
