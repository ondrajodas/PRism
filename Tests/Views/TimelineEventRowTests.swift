import Foundation
import Testing

@testable import PRism

/// Texty událostí v přehledu (#171).
///
/// Skládají se **mimo view**, jako u `FindingRow` a `ReleaseRow` — datum si formátuje view,
/// takže texty nezávisí na locale a dají se testovat bez UI.
@Suite("TimelineEventRow")
struct TimelineEventRowTests {
    private func row(
        _ kind: TimelineEvent.Kind,
        by login: String? = "ondrajodas",
        isBot: Bool = false
    ) -> TimelineEventRow {
        TimelineEventRow(
            event: TimelineEvent(
                id: "e1",
                kind: kind,
                actor: login.map { EventActor(login: $0, avatarURL: nil, isBot: isBot) },
                at: Date(timeIntervalSince1970: 100)
            )
        )
    }

    /// U commitu je hlavní text **titulek commitu**, ne věta o tom, že se pushlo: to je
    /// informace, kterou nese ikona a avatar. Sha jde vpravo, zkrácený jako všude jinde.
    @Test("Commit ukazuje titulek a zkrácený sha")
    func describesACommit() {
        let value = row(.commit(oid: "90449b51970c05fe07ed5270ee75578c3f8568d4", headline: "feat: přidat filtr"))

        #expect(value.title == "feat: přidat filtr")
        #expect(value.detail == "90449b5")
    }

    /// Commit bez titulku se stát může (prázdná zpráva) a řádek nesmí zůstat bez textu —
    /// prázdný řádek s avatarem nedává smysl.
    @Test("Commit bez titulku má aspoň náhradní text")
    func describesACommitWithoutAHeadline() {
        #expect(row(.commit(oid: "90449b5", headline: "")).title == "commit bez popisu")
    }

    @Test("Vyžádané review jmenuje toho, od koho se žádá")
    func describesARequestedReview() {
        #expect(row(.reviewRequested(reviewer: "janvanicek")).title == "ondrajodas vyžádal review od janvanicek")
    }

    /// Vyžádání od sebe sama píše GitHub jinou větou a musí se to poznat i tady — jinak
    /// z toho vyjde „ondrajodas vyžádal review od ondrajodas“.
    @Test("Vyžádání review od sebe sama má vlastní větu")
    func describesASelfRequestedReview() {
        #expect(row(.reviewRequested(reviewer: "ondrajodas")).title == "ondrajodas si vyžádal review")
        #expect(row(.reviewRequestRemoved(reviewer: "ondrajodas")).title == "ondrajodas odebral svoje vyžádané review")
    }

    /// Změřeno na `cli/cli#13084`: cíl umí přijít `null`. Věta pak nesmí končit „od “.
    @Test("Vyžádané review bez cíle nemá vlastní ocásek")
    func describesARequestWithoutATarget() {
        #expect(row(.reviewRequested(reviewer: nil)).title == "ondrajodas vyžádal review")
        #expect(row(.reviewRequestRemoved(reviewer: nil)).title == "ondrajodas odebral vyžádané review")
    }

    @Test("Force push nese oba commity")
    func describesAForcePush() {
        let value = row(.forcePushed(before: "b23bc28e800dd1", after: "90449b51970c05"))

        #expect(value.title == "ondrajodas přepsal historii větve")
        #expect(value.detail == "b23bc28 → 90449b5")
    }

    @Test(
        "Zbylé druhy událostí mají větu",
        arguments: [
            (TimelineEvent.Kind.readyForReview, "ondrajodas označil PR za hotový k review"),
            (.convertedToDraft, "ondrajodas převedl PR na draft"),
            (.merged(into: "main"), "ondrajodas mergnul PR do main"),
            (.merged(into: nil), "ondrajodas mergnul PR"),
            (.closed, "ondrajodas zavřel PR"),
            (.reopened, "ondrajodas otevřel PR znovu"),
            (.baseChanged(from: "main", to: "develop"), "ondrajodas změnil base z main na develop"),
            (.baseChanged(from: nil, to: "develop"), "ondrajodas změnil base na develop"),
        ]
    )
    func describesTheRemainingKinds(kind: TimelineEvent.Kind, expected: String) {
        #expect(row(kind).title == expected)
    }

    /// Smazaný účet: aktér nedorazí. „Někdo“ je pravda, kdežto věta bez podmětu by u části
    /// druhů vyšla jako „zavřel PR“ bez toho kdo.
    @Test("Bez aktéra věta neztratí podmět")
    func describesAnEventWithoutAnActor() {
        #expect(row(.closed, by: nil).title == "někdo zavřel PR")
    }

    /// Bot vyžádá review stejně jako člověk (`github-actions`), takže se musí dát odlišit —
    /// odznak je vedle jména, ne v něm.
    @Test("Bot má odznak, ale jméno si nechá")
    func marksABotActor() {
        let value = row(.reviewRequested(reviewer: "ondrajodas"), by: "github-actions", isBot: true)

        #expect(value.isBot)
        #expect(value.title == "github-actions vyžádal review od ondrajodas")
        #expect(!row(.closed).isBot)
    }

    /// Titulek commitu je zpráva commitu, tedy **kód** — sází se monospace jako na GitHubu.
    /// Věty ostatních událostí kód nejsou. Rozhoduje o tom řádek, ne view: jinak by ve view
    /// stál `switch` nad druhem události.
    @Test("Monospace má jen titulek commitu")
    func setsCodeStyleOnlyForCommits() {
        #expect(row(.commit(oid: "90449b5", headline: "feat: cokoli")).isTitleCode)
        #expect(!row(.merged(into: "main")).isTitleCode)
        #expect(!row(.reviewRequested(reviewer: "kdosi")).isTitleCode)
    }

    /// Každý druh musí mít **neprázdný** symbol a text — řádek beze symbolu vypadá jako
    /// rozbité vykreslení a řádek bez textu jako prázdno.
    @Test(
        "Každý druh má symbol i text",
        arguments: [
            TimelineEvent.Kind.commit(oid: "90449b5", headline: "cokoli"),
            .reviewRequested(reviewer: "kdosi"),
            .reviewRequestRemoved(reviewer: "kdosi"),
            .forcePushed(before: nil, after: nil),
            .readyForReview,
            .convertedToDraft,
            .merged(into: nil),
            .closed,
            .reopened,
            .baseChanged(from: nil, to: nil),
        ]
    )
    func hasASymbolAndATitle(kind: TimelineEvent.Kind) {
        let value = row(kind)

        #expect(!value.symbol.isEmpty)
        #expect(!value.title.isEmpty)
    }
}
