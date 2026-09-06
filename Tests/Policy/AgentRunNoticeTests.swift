import Foundation
import Testing

@testable import PRism

/// Notifikace a řádek v `Dění` o doběhlém agentovi (#511) — **tatáž brána jako ostatní** (#414).
///
/// **Dvě nejcennější tvrzení jsou negativní**: na cizím PR se nehlásí nic (banner ani řádek)
/// a vypnutý přepínač znamená ticho. Obojí se rozbije potichu — výsledkem není chyba, ale hláška
/// o práci, o kterou nikdo nežádal.
@Suite("Policy — agent doběhl: banner a dění (#511)")
struct AgentRunNoticeTests {
    private let pr = PRIdentifier("ondrajodas/PRism#511")!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Na cizím PR se nehlásí nic

    /// **Pojistka, ne brána**: agent se na cizím PR nespouští, takže je to stav, který nemá jak
    /// vzniknout — a kdyby vznikl, nesmí z něj být hláška o cizí práci.
    @Test("Na cizím PR nevznikne ani banner, ani řádek")
    func foreignPullRequestIsSilent() {
        let outcomes: [AgentRunOutcome] = [
            .done(files: 2),
            .partial(files: 1, skipped: "nechávám tobě"),
            .nothing(detail: nil),
            .failed(detail: "spadlo"),
            .discarded(detail: "nepřijalo se"),
        ]
        for outcome in outcomes {
            #expect(
                Policy.agentRunNotification(for: pr, ownership: .theirs, outcome: outcome) == nil
            )
            #expect(
                Policy.agentFixEvent(
                    for: pr,
                    ownership: .theirs,
                    outcome: outcome,
                    worktree: "511-sync",
                    at: now,
                    announced: false
                ) == nil
            )
        }
        #expect(!Policy.isReported(.agentFix, on: .theirs))
        #expect(Policy.isReported(.agentFix, on: .mine))
    }

    // MARK: - Co banner nese

    /// Rozvržení **titulek → detail → PR** (#200): nahoře to, podle čeho se člověk rozhoduje,
    /// dole identifikace, protože se čtvrtý řádek ořezává.
    @Test("Banner nese počet nahoře, další krok pod ním a PR nakonec")
    func notificationIsLaidOutTopDown() throws {
        let notification = try #require(
            Policy.agentRunNotification(for: pr, ownership: .mine, outcome: .done(files: 2))
        )

        #expect(notification.title == "Agent má hotovo · 2 soubory")
        #expect(notification.body == "zkontroluj a pushni\nondrajodas/PRism#511")
        #expect(notification.event == .agentFix)
    }

    /// **Vlastní titulek, ne `hotovo` s poznámkou v těle**: v banneru se čte první řádek.
    @Test("Nesplněná část zadání je vidět už v titulku")
    func partialRunSaysSoInTheTitle() throws {
        let notification = try #require(
            Policy.agentRunNotification(
                for: pr,
                ownership: .mine,
                outcome: .partial(files: 2, skipped: "README nechávám tobě.")
            )
        )

        #expect(notification.title == "Agent hotov jen zčásti · 2 soubory")
        #expect(notification.body.hasPrefix("část zadání nechal tobě"))
    }

    /// Nula souborů se do titulku **nepíše**: `0 souborů` nad commitem, který vznikl, si odporuje.
    @Test("Nula souborů se do titulku nepíše")
    func zeroFilesStayOutOfTheTitle() {
        #expect(Policy.agentRunHeadline(.done(files: 0)) == "Agent má hotovo")
    }

    /// Každý konec má **jiný titulek a jiný další krok** — jinak se z banneru nedá poznat, co se
    /// stalo.
    @Test("Pět konců, pět různých titulků a kroků")
    func everyOutcomeReadsDifferently() {
        let outcomes: [AgentRunOutcome] = [
            .done(files: 1),
            .partial(files: 1, skipped: "x"),
            .nothing(detail: nil),
            .failed(detail: "spadlo"),
            .discarded(detail: "nepřijalo se"),
        ]
        let headlines = outcomes.map(Policy.agentRunHeadline)
        let steps = outcomes.map(Policy.agentRunNextStep)

        #expect(Set(headlines).count == outcomes.count)
        #expect(Set(steps).count == outcomes.count)
        #expect(steps.allSatisfy { !$0.isEmpty })
    }

    /// **Push se slibuje jen tam, kde je co pushnout.** `zkontroluj a pushni` nad prázdným stromem
    /// je rada, po které se nedá nic udělat.
    @Test("Pushnout se radí jedině nad commitem, který leží v cache")
    func pushIsOfferedOnlyWhenSomethingWaits() {
        #expect(Policy.agentRunNextStep(.done(files: 1)).contains("pushni"))
        #expect(Policy.agentRunNextStep(.partial(files: 1, skipped: "x")).contains("pushni"))

        for outcome in [AgentRunOutcome.nothing(detail: nil), .failed(detail: "x"), .discarded(detail: "x")] {
            #expect(!Policy.agentRunNextStep(outcome).contains("pushni"))
        }
    }

    // MARK: - Brána

    /// **Vypnutý přepínač znamená ticho** — a hlavní vypínač přebíjí i ten.
    @Test("Přepínač agenta se dá vypnout zvlášť")
    func theGateIsItsOwnSwitch() {
        #expect(NotificationSettings().allows(.agentFix))
        #expect(!NotificationSettings(agentFix: false).allows(.agentFix))
        #expect(!NotificationSettings(isEnabled: false).allows(.agentFix))
        // Vypnutý agent neumlčí zprávy o cizí aktivitě a naopak — jsou to dvě různé otázky.
        #expect(NotificationSettings(agentFix: false).allows(.activity))
        #expect(NotificationSettings(activity: false).allows(.agentFix))
    }

    /// **Vlastní skupina**: že doběhl agent, nesmí přebít zprávu, na kterou ten agent reagoval.
    @Test("Agent nepřepíše ani review, ani cizí aktivitu")
    func agentHasItsOwnReplacementGroup() {
        let groups = Set(NotificationEvent.allCases.map(\.replacementGroup))

        #expect(NotificationEvent.agentFix.replacementGroup == "agent")
        #expect(NotificationEvent.agentFix.replacementGroup != NotificationEvent.activity.replacementGroup)
        #expect(NotificationEvent.agentFix.replacementGroup != NotificationEvent.findings.replacementGroup)
        #expect(groups.count == 4)
    }

    /// Rozbitá hodnota v souboru se sráží na **výchozí (zapnuto)**, jako u zbytku notifikací:
    /// umlčet aplikaci kvůli překlepu je horší než hláška navíc.
    @Test("Chybějící klíč v konfiguraci znamená zapnuto")
    func missingKeyMeansOn() throws {
        let decoded = try JSONDecoder().decode(
            NotificationSettings.self,
            from: Data(#"{"isEnabled": true}"#.utf8)
        )

        #expect(decoded.agentFix)
    }

    // MARK: - Řádek v dění

    /// Headline je **tentýž text jako titulek banneru**, detail celá věta z panelu — v řádku je na
    /// ni místo a je to jediné, kde se po týdnu dohledá, co agent nechal být.
    @Test("Řádek v dění nese titulek banneru a pod ním celou větu")
    func feedRowCarriesTheWholeSentence() throws {
        let event = try #require(
            Policy.agentFixEvent(
                for: pr,
                outcome: .partial(files: 2, skipped: "README nechávám tobě."),
                worktree: "511-sync",
                at: now,
                announced: true
            )
        )

        #expect(event.kind == .agentFix)
        #expect(event.headline == "Agent hotov jen zčásti · 2 soubory")
        #expect(event.detail?.contains("ve stromě 511-sync") == true)
        #expect(event.detail?.contains("README nechávám tobě.") == true)
        #expect(event.wasAnnounced)
        #expect(event.pullRequest == pr)
    }

    /// Kresba řádku: **akcent** (na tomhle PR na tebe něco čeká), cíl `Přehled` (nad tabem je
    /// dráha), a chip `bez banneru` se u něj kreslit **smí** — banner za něj chodí.
    @Test("Řádek má akcent, vede na Přehled a umí chip bez banneru")
    func feedRowIsDrawnLikeSomethingThatWaits() {
        #expect(Policy.tone(of: .agentFix) == .accent)
        #expect(Policy.destination(of: .agentFix) == .tab(.overview))
        #expect(Policy.showsSilentChip(.agentFix, announced: false))
        #expect(!Policy.showsSilentChip(.agentFix, announced: true))
        #expect(!Policy.symbol(of: .agentFix).isEmpty)
        #expect(Policy.activityKind(of: .agentFix) == .agentFix)
    }
}
