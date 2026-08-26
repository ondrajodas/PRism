import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Composer tabu `Zeptat se` (#452) — co se odešle a co zůstane v poli.
///
/// **Testuje se přes `NSHostingView` a skutečné zmáčknutí `⌘⏎`**, ne nad storem, a je to celý
/// smysl téhle sady: store obě poloviny té výměny dělal správně od začátku (`AppStoreAskTests`
/// tvrdí, že otázka doletí do rozhovoru) a otázka **přesto** po odeslání zůstala v poli.
/// Rozbité to bylo okružní cestou — pole drží text u sebe a dolů ho posílalo po odmlce 400 ms,
/// takže klik trefený do té mezery odeslal starší otázku a rozepsanou dostal zpátky. Nad storem
/// se to napsat nedá, protože store o tom poli nic neví.
///
/// **Tlačítko se mačká klávesou, ne `performClick`em**: `Button` je v tomhle okně kreslený
/// SwiftUI, takže v hierarchii žádný `NSButton` není (ověřeno výpisem — jsou tam jen views
/// textového pole). `window.performKeyEquivalent(with:)` projde i bez aktivace aplikace, kterou
/// testovací host nedostane (#392), a jako vedlejší efekt tvrdí i to, že si `⌘⏎` v tomhle tabu
/// doopravdy bere `Zeptat se`.
@MainActor
@Suite("Composer tabu Zeptat se")
struct AskComposerTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let question = "proč se ten mutex bere kolem celého fetch?"

    // MARK: - Odeslání

    /// **Vyprázdnit pole je součást odeslání.** Otázka, která v poli zůstane, se dá odeslat
    /// podruhé — a stojí podruhé.
    @Test("Odeslaná otázka z pole zmizí")
    func sendingEmptiesTheField() async throws {
        let store = store()
        let scene = try hosted(store)
        defer { scene.close() }

        scene.type(question)
        await waitUntil("tlačítko Zeptat se ožije") { scene.press() }
        await waitUntil("otázka doletí do rozhovoru") { !self.messages(store).isEmpty }

        // **Jev, ne okamžik** (#269): vyprázdnění pole je průchod SwiftUI po akci tlačítka.
        await waitUntil("pole se vyprázdní") { scene.text.isEmpty }
        #expect(messages(store).map(\.text) == [question])
        #expect(store.askDraft(for: pr).isEmpty, "v záloze zůstalo „\(store.askDraft(for: pr))“")
    }

    /// **Odešle se to, co je vidět.** Tohle je ta původní chyba: mezi posledním úhozem a zápisem
    /// do storu bývala odmlka, takže se odeslala starší podoba otázky a v poli zbyla ta novější.
    /// Test píše dvakrát hned po sobě a mačká **bez čekání**.
    @Test("Odešle se to, co je v poli, ne starší podoba otázky")
    func sendsWhatIsOnTheScreen() async throws {
        let store = store()
        let scene = try hosted(store)
        defer { scene.close() }

        scene.type("proč se ten mutex")
        scene.type(question)
        await waitUntil("tlačítko Zeptat se ožije") { scene.press() }
        await waitUntil("otázka doletí do rozhovoru") { !self.messages(store).isEmpty }

        await waitUntil("pole se vyprázdní") { scene.text.isEmpty }
        #expect(messages(store).map(\.text) == [question])
    }

    /// Druhý konec, a **tvrdí, že se něco NEstalo**: přijít o napsanou otázku je horší než ji mít
    /// v poli po odeslání. Když se neodešle, text zůstane, kde je.
    ///
    /// Zavírání aplikace (#264) je jediná cesta, kterou odeslání odmítne a pole přitom není
    /// zakázané — u chybějícího `claude` i běžící odpovědi je tlačítko zašedlé, takže by se na ně
    /// nedalo zmáčknout.
    @Test("Otázka, která neodešla, v poli zůstane")
    func aRefusedQuestionStaysInTheField() async throws {
        let store = store()
        let scene = try hosted(store)
        defer { scene.close() }

        scene.type(question)
        store.isTerminating = true
        await waitUntil("tlačítko Zeptat se ožije") { scene.press() }
        await settle()

        #expect(messages(store).isEmpty, "otázka odešla, i když neměla")
        #expect(scene.text == question, "v poli zbylo „\(scene.text)“")
    }

    /// Klik na **nabízenou otázku** (ta jde do storu rovnou, ne přes pole) nesmí sníst větu,
    /// kterou má člověk rozepsanou vedle — a je to zároveň tvrzení o tom, že přechod z prázdného
    /// tabu na rozhovor composer nepřestaví.
    @Test("Nabízená otázka nesní rozepsanou")
    func aSuggestedQuestionKeepsWhatIsTyped() async throws {
        let store = store()
        let scene = try hosted(store)
        defer { scene.close() }

        scene.type(question)
        store.askQuestion("Co v tomhle PR nejvíc riskuje?", about: pr)
        await waitUntil("otázka z nabídky doletí do rozhovoru") { !self.messages(store).isEmpty }
        await settle()

        #expect(scene.text == question, "v poli zbylo „\(scene.text)“")
    }

    // MARK: - Záloha pro přepnutí tabu

    /// Rozepsaná otázka se do storu ukládá **při zmizení** — překliknutí tabu ani přepnutí PR
    /// ji nesmí sníst. Během psaní se tam nesahá schválně: zápis každého úhozu překresluje celý
    /// detail PR.
    @Test("Rozepsaná otázka se uloží při zmizení, ne během psaní")
    func theDraftIsKeptWhenTheTabGoesAway() async throws {
        let store = store()
        let scene = try hosted(store)

        scene.type(question)
        await settle()
        #expect(store.askDraft(for: pr).isEmpty, "během psaní se do storu sahat nemá")

        scene.close()
        await waitUntil("rozepsaná otázka se uloží do zálohy") { store.askDraft(for: self.pr) == self.question }
    }

    /// A při objevení se ze zálohy vrátí — jinak by přepnutí tabu rozepsanou otázku ztratilo.
    @Test("Uložená otázka se v poli objeví zpátky")
    func theDraftComesBack() async throws {
        let store = store()
        store.setAskDraft(question, for: pr)
        let scene = try hosted(store)
        defer { scene.close() }

        #expect(scene.text == question)
    }

    // MARK: - Pomůcky

    private func messages(_ store: AppStore) -> [AskMessage] {
        store.askConversation(for: pr)?.messages ?? []
    }

    private func store() -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([]),
                detail: .success(
                    PullRequest(
                        id: pr,
                        title: "titulek",
                        author: "autor",
                        headSha: "aaaa1111",
                        baseSha: "bbbb2222",
                        url: URL(string: "https://github.com/cli/cli/pull/42")!,
                        updatedAt: Date(timeIntervalSince1970: 100),
                        state: .open
                    )
                )
            ),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(),
            asker: FakeAskRunner(holdsUntilRelease: true)
        )
    }

    /// Tab v okně mimo obrazovku — `ScrollView` bez okna obsah nerozvrhne (tatáž potíž jako
    /// u `AskTabRenderProbe`).
    private func hosted(_ store: AppStore) throws -> AskScene {
        let hosting = NSHostingView(rootView: AskHarness(store: store, pullRequest: pr))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 520)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        let scene = AskScene(window: window, hosting: hosting)
        _ = try #require(scene.textView, "v tabu není textové pole")
        return scene
    }
}

/// Okno s tabem a jeho textové pole — aby se v testech nepsalo pokaždé, jak se do pole píše
/// a jak se mačká `⌘⏎`.
@MainActor
private struct AskScene {
    let window: NSWindow
    let hosting: NSView

    /// Textové pole se hledá **pokaždé znovu**, ne jednou při postavení okna: prázdný tab a tab
    /// s rozhovorem jsou dvě různé větve, takže si SwiftUI umí composer přestavět — a uložená
    /// reference by pak ukazovala na `NSTextView`, který na obrazovce dávno není. Test by nad ním
    /// tvrdil, že se pole nevyprázdnilo, i kdyby se vyprázdnilo.
    var textView: NSTextView? { hosting.firstDescendant(ofType: NSTextView.self) }

    /// Co je v poli vidět.
    var text: String { textView?.string ?? "" }

    /// Píše se **přes `didChangeText()`**, ne přiřazením do `string`: binding se v SwiftUI plní
    /// z delegáta, takže samotné přiřazení by se do view nikdy nedostalo a test by tvrdil, že se
    /// nic neztratilo, i kdyby se ztrácelo všechno.
    func type(_ text: String) {
        guard let field = textView else { return }
        field.string = text
        field.didChangeText()
    }

    /// Zmáčkne `⌘⏎`, tedy tlačítko `Zeptat se`. Vrací, jestli si klávesu někdo **vzal** — tedy
    /// jestli tlačítko v tu chvíli nebylo zašedlé; o tom, co udělalo, to netvrdí nic.
    ///
    /// Čeká se **na jev, ne na okamžik** (#269): mezi zápisem do pole a překreslením tlačítka je
    /// jeden průchod SwiftUI, a jeho délku pod zátěží nemá test z čeho spočítat. Volá se proto
    /// z `waitUntil` a mačká se, dokud si klávesu někdo nevezme. Zašedlé tlačítko přitom nedělá
    /// nic, takže opakování nic neodešle.
    @discardableResult
    func press() -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
        guard let event else { return false }
        return window.performKeyEquivalent(with: event)
    }

    /// Zavře okno, tedy odstraní tab — `onDisappear` composeru jde touhle cestou.
    func close() {
        window.contentView = nil
        window.orderOut(nil)
    }
}

/// Obal, který `AskView` skládá **ze storu**, jako to dělá `PullRequestDetailView` — jinak by
/// test měřil statický snímek a o okružní cestě by netvrdil nic.
@MainActor
private struct AskHarness: View {
    let store: AppStore
    let pullRequest: PRIdentifier

    var body: some View {
        let chips = store.askContextChips(for: pullRequest)
        return AskView(
            content: Policy.askTab(
                conversation: store.askConversation(for: pullRequest),
                isAnswering: store.isAnswering(pullRequest),
                context: chips
            ),
            chips: chips,
            activity: store.askActivityLine(for: pullRequest),
            draft: store.askDraft(for: pullRequest),
            block: store.askBlock(for: pullRequest),
            persistDraft: { store.setAskDraft($0, for: pullRequest) },
            send: { store.askQuestion($0, about: pullRequest) },
            cancel: { store.cancelAsk(for: pullRequest) },
            reset: { store.resetAskConversation(for: pullRequest) }
        )
        .frame(width: 900, height: 520)
    }
}
