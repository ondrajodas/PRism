import Foundation
import Testing

@testable import PRism

/// Brief ze strany store (#516) — brána, spouštěč a to, co se s výsledkem stane.
///
/// **Nejcennější tvrzení téhle sady jsou ta, která říkají, že se něco NEstalo**: že se
/// s vypnutou branou nespustí session, že ji tik v režimu `Na požádání` nespustí taky, a že
/// spadlý běh **nezůstane prázdný**. Rozbijí se potichu — výsledkem porušení není chyba, ale
/// session za peníze, o kterou nikdo nepožádal, nebo blok, který vypadá jako vypnutý.
@Suite("AppStore — brief na domově (#516)")
@MainActor
struct AppStoreBriefTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(_ identifier: String = "keboola/job-queue#727") -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "feat(flow-result): read persisted requested job delay",
            author: "sykora-ji",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: start.addingTimeInterval(-600),
            state: .open
        )
    }

    /// Scéna: jedno cizí PR ve frontě a fake session.
    ///
    /// **Bez `BriefStore`u**, takže se do cache nesahá a dnešek se posuzuje z toho, co je ve stavu
    /// — o uložení na disk je vlastní sada (`BriefStoreTests`).
    private func store(
        mode: BriefMode,
        writer: FakeBriefWriter? = FakeBriefWriter(),
        refreshed: Bool = true
    ) async -> (store: AppStore, writer: FakeBriefWriter?, time: FakeTimeSource) {
        var configuration = Configuration.standard
        configuration.global.brief = mode
        let time = FakeTimeSource(start: start)
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary()])),
            configuration: configuration,
            time: time,
            briefWriter: writer
        )
        if refreshed {
            await store.refresh()
            // **Tik je spouštěč**, takže v režimu `Při prvním tiku dne` se brief složí už tady —
            // a test, který by na běh nepočkal, by měřil stav uprostřed něj.
            while let task = store.briefTask { await task.value }
        }
        return (store, writer, time)
    }

    /// Spouštěč na běh **nečeká** (visí na tiku), takže test musí počkat sám — jinak by měřil
    /// stav uprostřed běhu.
    private func settle(_ store: AppStore) async {
        while let task = store.briefTask { await task.value }
    }
}

// MARK: - Co brief nepustí

extension AppStoreBriefTests {
    /// **Vypnutá brána znamená, že se nespustí nic** — a blok se nekreslí. Je to celá vlastnost
    /// „samo nic nezačne“.
    @Test("S vypnutou branou se nespustí žádná session")
    func startsNothingWhenOff() async {
        let scene = await store(mode: .off)

        scene.store.writeBrief()
        await scene.store.writeBriefIfDue()
        await settle(scene.store)

        #expect(scene.writer?.runs == 0)
        #expect(scene.store.briefState == .never)
        #expect(Policy.briefBlock(mode: .off, state: scene.store.briefState) == nil)
    }

    /// **`Na požádání` je požádání.** Tik nesmí spustit nic; tlačítko ano.
    @Test("Tik v režimu Na požádání nespustí nic")
    func tickDoesNothingOnDemand() async {
        let scene = await store(mode: .onDemand)

        await scene.store.writeBriefIfDue()
        await settle(scene.store)
        #expect(scene.writer?.runs == 0)

        scene.store.writeBrief()
        await settle(scene.store)
        #expect(scene.writer?.runs == 1)
    }

    /// Nenačtená fronta: brief by mluvil o datech, která se ještě nestáhla.
    @Test("Nad nenačtenou frontou se brief nespustí")
    func waitsForTheQueue() async {
        let scene = await store(mode: .firstTickOfDay, refreshed: false)

        scene.store.writeBrief()
        await settle(scene.store)

        #expect(scene.writer?.runs == 0)
    }

    /// Zavírání aplikace (#264): session, která ji přežije, je zrovna to, co se tím zavíráním
    /// zastavuje. Tvrdí se to **nad skutečným tikem**, ne nad přímým voláním — tak se brief
    /// v provozu pouští.
    @Test("Při zavírání aplikace se brief nespustí")
    func startsNothingWhileTerminating() async {
        let scene = await store(mode: .firstTickOfDay, refreshed: false)
        scene.store.isTerminating = true

        await scene.store.refresh()
        await settle(scene.store)

        #expect(scene.writer?.runs == 0)
    }

    /// **Jednou za den.** Druhý tik téhož dne session nepustí, i když je brána zapnutá.
    @Test("Automat shrnuje jednou za den")
    func summarizesOncePerDay() async {
        // Scéna se načte tikem, takže první brief složil **automat sám** — právě to je na téhle
        // cestě nové (jediná session, která startuje bez kliknutí, je jinak agent z #510).
        let scene = await store(mode: .firstTickOfDay)
        #expect(scene.writer?.runs == 1)

        await scene.store.writeBriefIfDue()
        await settle(scene.store)
        #expect(scene.writer?.runs == 1)

        // Druhý den už ano — rozhoduje razítko briefu, ne počitadlo běhů.
        scene.time.advance(by: 90_000)
        await scene.store.writeBriefIfDue()
        await settle(scene.store)
        #expect(scene.writer?.runs == 2)
    }
}

// MARK: - Co se stane s výsledkem

extension AppStoreBriefTests {
    /// Základní směr: tlačítko → jedna session, tři věty, razítko a cena.
    @Test("Tlačítko složí brief i s cenou")
    func writesTheBrief() async throws {
        let scene = await store(mode: .onDemand)

        scene.store.writeBrief()
        await settle(scene.store)

        let writer = try #require(scene.writer)
        #expect(writer.runs == 1)
        let brief = try #require(scene.store.briefState.brief)
        #expect(brief.lines.map(\.part) == [.added, .burning, .next])
        #expect(brief.lines.first?.text.hasPrefix("Přes den přišly") == true)
        #expect(brief.writtenAt == start)
        #expect(brief.cost == 0.09)
    }

    /// **Vstup nese stav aplikace, ne kód.** Tvrdí se to nad tím, co session doopravdy dostala —
    /// `Policy.briefInput` se testuje zvlášť, ale tady jde o to, že store předává **jeho** výstup.
    @Test("Session dostane stav aplikace, ne cesty a kód")
    func passesStateNotCode() async throws {
        let scene = await store(mode: .onDemand)

        scene.store.writeBrief()
        await settle(scene.store)

        let input = try #require(scene.writer?.requests.first?.input)
        #expect(input.contains("keboola/job-queue #727"))
        #expect(input.contains("Pruh Přečíst (1):"))
        #expect(!input.contains("/Users/"))
        #expect(!input.contains("https://"))
        #expect(!input.contains(".swift"))
    }

    /// **Cíle odkazů si brief nese z materiálu, ne z odpovědi modelu** (#516). Text je volný
    /// výstup session, takže o tom, na co se dá kliknout, nesmí rozhodovat — rozhoduje o tom
    /// seznam pull requestů, které do zadání doopravdy šly.
    @Test("Hotový brief nese pull requesty, které do zadání šly")
    func carriesLinkTargetsFromTheInput() async throws {
        let scene = await store(mode: .onDemand)

        scene.store.writeBrief()
        await settle(scene.store)

        let brief = try #require(scene.store.briefState.brief)
        #expect(brief.mentioned == [PRIdentifier("keboola/job-queue#727")!])
    }

    /// **Spadlá session nesmí skončit prázdnem.** Prázdný blok je k nerozeznání od vypnutého
    /// briefu, takže se v něm musí objevit věta o tom, že se to nepovedlo — i s důvodem — a
    /// nabídka zkusit to znovu.
    @Test("Spadlá session nechá v bloku větu a nabídku, ne prázdno")
    func failedRunSaysSo() async throws {
        let scene = await store(
            mode: .onDemand,
            writer: FakeBriefWriter(answers: [
                BriefAnswer(lines: nil, usage: RunUsage(cost: 0.01), failure: "Session skončila chybou (error).")
            ])
        )

        scene.store.writeBrief()
        await settle(scene.store)

        #expect(scene.store.briefState == .failed(reason: "Session skončila chybou (error)."))
        let block = try #require(Policy.briefBlock(mode: .onDemand, state: scene.store.briefState))
        #expect(block.action == "Zkusit znovu")
        guard case .failed(let headline, let detail) = block.body else {
            Issue.record("čekaly se dvě věty")
            return
        }
        #expect(headline == "Shrnutí se nepovedlo.")
        #expect(detail == "Session skončila chybou (error).")
    }

    /// **Cena spadlého běhu se taky účtuje.** Zabitá session peníze stála a útrata, která se
    /// ztratí zrovna u nepovedeného běhu, je o účtu lež.
    @Test("Cena jde do dnešní útraty i u spadlého běhu")
    func recordsSpendEvenOnFailure() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        var configuration = Configuration.standard
        configuration.global.brief = .onDemand
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary()])),
            configuration: configuration,
            time: FakeTimeSource(start: start),
            briefWriter: FakeBriefWriter(answers: [
                BriefAnswer(lines: nil, usage: RunUsage(cost: 0.02), failure: "spadlo")
            ]),
            spend: SpendLedger(layout: layout),
            cacheLayout: layout
        )
        await store.refresh()

        store.writeBrief()
        await settle(store)

        #expect(store.dailySpend?.cost == 0.02)
    }

    /// Druhá session se nespustí, dokud první běží — ani tlačítkem. Tvrdí se to přes stav, protože
    /// právě ten drží bránu.
    @Test("Běžící brief se nespustí podruhé")
    func refusesWhileRunning() async {
        let scene = await store(mode: .onDemand)
        scene.store.briefState = .running

        scene.store.writeBrief()
        await settle(scene.store)

        #expect(scene.writer?.runs == 0)
    }
}
