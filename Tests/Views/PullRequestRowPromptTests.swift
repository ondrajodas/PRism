import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Řádek vlastního PR má vpravo `Prompt →` (#331).
///
/// Dvě třídy tvrzení. **Že se to nekreslí u cizího PR:** tlačítko na cizím řádku by slibovalo akci
/// nad prací, která není moje, a v `body` se to tvrdit nedá — proto je rozhodnutí pojmenované.
/// A **že se doopravdy nakreslí:** `if` nad `ownership` může projít, aniž by se prvek do řádku
/// vešel, takže se řádek rozvrhne mimo obrazovku a porovná se výška.
@Suite("Řádek vlastního PR (#331)")
@MainActor
struct PullRequestRowPromptTests {
    private func row(_ ownership: PullRequestOwnership) -> PullRequestRow {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("ondrajodas/PRism#324")!,
                title: "feat: put the reviewer run timeout into settings",
                author: "ondrajodas",
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/324")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            reviewState: .completed(findings: 6),
            ownership: ownership
        )
    }

    @Test("Prompt se nabízí jen u vlastního PR")
    func offersThePromptOnlyOnOwnPullRequests() {
        #expect(row(.mine).showsPromptAction)
        #expect(!row(.theirs).showsPromptAction)
        // A výchozí hodnota je `theirs`: řádek bez informace o autorovi tlačítko **nemá**, jinak by
        // se objevilo všude, kde se řádek kreslí bez storu.
        #expect(!PullRequestRow(pullRequest: row(.mine).pullRequest, reviewState: .notStarted).showsPromptAction)
    }

    /// Tlačítko je z návrhu 25 bodů vysoké (`.mini.pri`), kdežto odznak stavu je jen text
    /// v kapsli — vlastní řádek proto vyroste. Kdyby se `if` nakreslil „naprázdno“ (prvek se do
    /// řádku nevejde), zůstala by výška stejná a test to chytí.
    @Test("Řádek s promptem je vyšší, tedy tlačítko se nakreslilo")
    func drawsTheButtonIntoTheRow() {
        let mine = height(of: row(.mine))
        let theirs = height(of: row(.theirs))

        #expect(mine > theirs)
        // Vejde se do rozdílu, který dělá tlačítko z návrhu — ne o desítky bodů víc, což by
        // znamenalo, že se řada zalomila.
        #expect(mine - theirs <= MiniButtonStyle.Metrics.height)
    }

    /// Rozvržení mimo obrazovku — accessibility tree se v okně mimo obrazovku nenaplní (změřeno
    /// u #269), zato `fittingSize` odpoví.
    private func height(of row: PullRequestRow) -> Double {
        let hosting = NSHostingView(rootView: row.frame(width: 520))
        return hosting.fittingSize.height
    }
}
