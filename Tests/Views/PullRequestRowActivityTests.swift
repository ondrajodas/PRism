import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Meta řádek s cizí aktivitou (#335) — `2 nové komentáře od minule` místo autora a času.
///
/// Tři třídy tvrzení, tatáž stavba jako u `Prompt →` (#331). **Že se to nekreslí u cizího PR:**
/// cizí diskuzi aplikace na pozadí nehlídá, takže by text byl vždycky prázdný — a v `body` se to
/// tvrdit nedá, proto je rozhodnutí pojmenované. **Že text říká, kolik a čeho** (mockup, poznámka
/// 66b: tečka by řekla jen, že se něco stalo). A **že se doopravdy nakreslí**, tedy že řádek zůstane
/// jednořádkový — text novinek je delší než `ondrajodas · před 3 hodinami`, kterého nahrazuje,
/// takže by se v úzkém seznamu mohl zalomit.
@Suite("Řádek s cizí aktivitou (#335)")
@MainActor
struct PullRequestRowActivityTests {
    private func comment(id: String, by author: String = "odinuv") -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "opravdu to potřebuje ten mutex?",
            createdAt: Date(timeIntervalSince1970: 2000),
            url: URL(string: "https://github.com/keboola/app-project-restore/pull/91#c-\(id)")!
        )
    }

    private func row(
        _ ownership: PullRequestOwnership = .mine,
        activity: ForeignActivity = .none
    ) -> PullRequestRow {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("keboola/app-project-restore#91")!,
                title: "[AJDA-1215] Update specific tables/configurations",
                author: "ondrajodas",
                url: URL(string: "https://github.com/keboola/app-project-restore/pull/91")!,
                updatedAt: Date(timeIntervalSince1970: 1000),
                state: .open
            ),
            reviewState: .completed(findings: 2),
            ownership: ownership,
            openPrompt: {},
            activity: activity
        )
    }

    @Test("Text nese počet a druh, jak ho má návrh")
    func theLineCarriesTheCountAndKind() {
        #expect(row(activity: ForeignActivity(comments: [comment(id: "a")], reviews: [])).activityLine
            == "1 nový komentář od minule")
        #expect(row(activity: ForeignActivity(
            comments: [comment(id: "a"), comment(id: "b")],
            reviews: []
        )).activityLine == "2 nové komentáře od minule")
    }

    /// **Tvrzení, že se nic nekreslí**: bez novinek zůstane meta řádek, jaký byl — autor a čas.
    @Test("Bez novinek text není")
    func withoutActivityThereIsNoLine() {
        #expect(row(activity: .none).activityLine == nil)
    }

    /// A na cizím řádku se nemění vůbec nic: hlídá se jedině diskuze vlastních PR
    /// (`Policy.activitySweep`), takže by tam text stejně nikdy nebyl — a kdyby se objevil,
    /// tvrdil by o cizí práci něco, co aplikace nesleduje.
    @Test("Cizí PR text nedostane, ani když aktivitu dostane omylem")
    func aForeignRowNeverShowsTheLine() {
        let activity = ForeignActivity(comments: [comment(id: "a")], reviews: [])

        #expect(row(.theirs, activity: activity).activityLine == nil)
    }

    /// Text **nahrazuje autora a čas** (návrh, sekce 21), takže řádek nesmí vyrůst: kdyby se
    /// zalomil, byla by z dvouřádkového řádku trojřádková buňka a seznam by přestal být skenovatelný.
    @Test("Řádek s novinkami zůstane stejně vysoký")
    func theRowDoesNotGrow() {
        let plain = height(of: row(activity: .none))
        let withActivity = height(of: row(activity: ForeignActivity(
            comments: [comment(id: "a"), comment(id: "b")],
            reviews: []
        )))

        #expect(withActivity == plain)
    }

    /// Rozvržení mimo obrazovku — accessibility tree se v okně mimo obrazovku nenaplní (změřeno
    /// u #269), zato `fittingSize` odpoví. Šířka je ta nejužší, na které se seznam kreslí.
    private func height(of row: PullRequestRow) -> Double {
        let hosting = NSHostingView(rootView: row.frame(width: 320))
        return hosting.fittingSize.height
    }
}
