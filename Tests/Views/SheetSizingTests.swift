import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Sheet bez `presentationSizing(.fitted)` zahodí ideální šířku, ale ideální výšku si vezme**
/// (#491, upřesňuje #327).
///
/// Pravidlo pochází z #327 a bylo změřené nad dvěma sheety (`RawSessionSheet`, `CodeTextSheet` —
/// oba `.fitted` mají, a mají na to vlastní suity). Tahle suita ho měří nad **těmi třemi, které
/// `.fitted` nemají a mít nebudou**: potvrzení odeslání review (#68), potvrzení merge (#465)
/// a zadání pro agenta (#333).
///
/// **Ta asymetrie je celý důvod, proč suita existuje.** Zadání #491 vycházelo z toho, že `ideal*`
/// je u sheetu bez `.fitted` mrtvá hodnota a odebrat se dá **celé**. Měření (`docs/testovani.md`,
/// *Co dělá `ideal*` u sheetu*) ukázalo, že to platí jen o šířce:
///
/// | Rámec (prázdný obsah) | Sheet |
/// |---|---|
/// | `min 460×300`, `ideal 520×380` | 470 × **380** |
/// | `min 460×300`, `ideal 900×900` | 470 × **860** (strop obrazovky) |
/// | `min 460×300`, bez ideálu | 470 × **300** |
/// | bez `min`, `ideal 520×380` | 470 × 380 |
/// | `min 600×300`, `ideal 520×380` | **600** × 380 |
///
/// Šířka je tedy vždycky `max(minWidth, 470)` — ideál se neuplatní ani nahoru, ani dolů —, kdežto
/// výška ideál bere. Odebrat `idealHeight` by proto nebyla oprava mrtvé hodnoty, ale **zmenšení
/// hotové obrazovky** o 80 (merge), 140 (odeslání review) a 200 bodů (zadání pro agenta). Zůstává
/// tedy, a odešla jen ta šířka, která nikdy nic neznamenala.
///
/// **Přidat `.fitted` bylo zamítnuté, ne opomenuté** — u všech tří ze stejného důvodu jako u #466:
/// rozšíření hotové obrazovky je změna vzhledu, a ta jde přes zákres do návrhu a souhlas, ne přes
/// opravu rozvržení.
///
/// **Měří se nad skutečným oknem sheetu**, ne nad hodnotami v `Policy`: rozhoduje o tom SwiftUI
/// a z dokumentace se to přečíst nedá. Scéna je tatáž jako u `RawSessionSheetSizingTests` — okno
/// mimo obrazovku, `sheet(isPresented:)`, čekání na `attachedSheet`.
@Suite("Velikost sheetů bez .fitted (#491)", .serialized)
@MainActor
struct SheetSizingTests {
    // MARK: - Změřená velikost

    /// **Sheety bez `.fitted` se neroztáhnou a jejich výška je ta ideální.**
    ///
    /// Čísla jsou tady schválně **literály, ne konstanty z `Policy`** — jinak by test porovnával
    /// view sám se sebou. Do `Policy` ta velikost nepatří: `Policy.rawSessionSheet*`
    /// a `Policy.codeSheetSizing` existují proto, že se z nich **počítá** (ořez uložené velikosti
    /// o okraje obrazovky, výběr profilu podle druhu obsahu), kdežto tyhle tři sheety nic neukládají
    /// a nic z obrazovky neberou. Konstanta by tedy jen přestěhovala literál a vzala testu možnost
    /// spadnout.
    ///
    /// **Na šířku se tvrdí mez, ne rovnost**, a je to rozdíl proti výšce: šířku sheetu zvedá
    /// i vlastní ideál obsahu (`MergeSheet` s tímhle materiálem chce 507 bodů, tedy víc než jeho
    /// podlaha 460), takže rovnost by tvrdila něco o šířce textu ve fixture, ne o rozvržení. Co
    /// tvrdit jde a na čem #491 stojí, je, že se šířka **nezvedla na ideál** — a ten je u všech tří
    /// nad podlahou i nad tím, co si obsah řekne.
    @Test(
        "Sheet bez .fitted má ideální výšku, ne ideální šířku",
        arguments: [
            // `deadIdeal` je šířka, která v rámci stála do #491. Kdyby ji SwiftUI bralo, byl by
            // sheet přesně tak široký — a tenhle test je právě to, co takovou změnu chytí.
            (name: "ReviewSubmissionSheet", floorWidth: 560.0, deadIdeal: 620.0, height: 560.0),
            (name: "MergeSheet", floorWidth: 460.0, deadIdeal: 520.0, height: 380.0),
            (name: "AgentPromptSheet", floorWidth: 840.0, deadIdeal: 1_080.0, height: 620.0),
        ]
    )
    func opensAtItsIdealHeightButNeverAtTheIdealWidth(
        scene: (name: String, floorWidth: CGFloat, deadIdeal: CGFloat, height: CGFloat)
    ) async throws {
        let opened = try await open(named: scene.name)
        defer { opened.close() }

        try await opened.wait(forHeight: scene.height)
        let size = opened.sheet.frame.size
        #expect(size.height == scene.height)
        #expect(size.width >= scene.floorWidth, "\(scene.name) je pod svou podlahou: \(size.width).")
        #expect(size.width < scene.deadIdeal, "\(scene.name) se rozšířil na ideál: \(size.width).")
        // **Bez `.fitted` a bez pružného rámce nedostane okno sheetu `.resizable`** (#327). Je to
        // druhá polovina téhož: sheet, který se nedá roztáhnout, má jedinou velikost — tuhle.
        let mask = opened.sheet.styleMask.rawValue
        #expect(
            !opened.sheet.styleMask.contains(.resizable),
            "\(scene.name) má `.resizable`, takže se velikost sheetu změnila — styleMask \(mask)."
        )
    }

    /// **Okno hostitele velikost sheetu neurčuje.** Kdyby ji určovalo, byla by podlaha jen spodní
    /// mez a `idealWidth` by na malých obrazovkách mohlo mít smysl — takže je to tvrzení, bez
    /// kterého by odebrání ideální šířky stálo na domněnce. (U #327 se to změřilo nad oknem 2 000
    /// bodů; tady se srovnávají dvě okna proti sobě, což je totéž tvrzení bez závislosti na tom,
    /// jak velká je obrazovka stroje.)
    @Test("Široké okno za sheetem velikost nezmění")
    func ignoresTheWindowBehindIt() async throws {
        let narrow = try await open(named: "MergeSheet", hostWidth: 700)
        defer { narrow.close() }
        try await narrow.wait(forHeight: 380)

        let wide = try await open(named: "MergeSheet", hostWidth: 2_000)
        defer { wide.close() }
        try await wide.wait(forHeight: 380)

        #expect(narrow.sheet.frame.size == wide.sheet.frame.size)
    }

    // MARK: - Stráž nad zdrojáky

    /// Kořen repa — tenhle soubor leží v `Tests/Views/`, takže tři složky nahoru.
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// **`idealWidth` smí být jedině tam, kde je `presentationSizing`.**
    ///
    /// Je to ta tvrdší podoba grepu, který má `CLAUDE.md` — nad **sheety** se totiž dá vyslovit bez
    /// výjimek: v `App/Views/` je každý sheet soubor `*Sheet.swift` (roster níž to pojistí)
    /// a `presentationSizing` je jediný způsob, jak ideální šířku v prezentaci oživit. Mimo sheety
    /// zůstává grep výčtem k posouzení, protože v obyčejném pružném rámci (`DiffSearchBar`) je
    /// `idealWidth` v pořádku a v okně `Settings` scény je mrtvý z **jiného** důvodu, na který
    /// `presentationSizing` nedosáhne (`SettingsView`).
    ///
    /// **`idealHeight` se nehlídá, a je to změřené rozhodnutí, ne mezera**: tu si sheet vezme
    /// i bez `.fitted` (tabulka v dokumentaci suity), takže by zákaz zakazoval hodnotu, která
    /// funguje — a tři obrazovky by se tím zmenšily.
    ///
    /// Hledá se v **kódu bez komentářů a bez mezer** (tatáž konstrukce jako `GlobalAppearanceTests`
    /// a `SingleWayOutTests`): o `idealWidth` se v komentářích u čtyř sheetů píše — je to zrovna to
    /// místo, kde se vysvětluje, proč tam není —, a mezera uvnitř volání je ve Swiftu volná, takže
    /// `.frame(minWidth: 460, idealWidth : 520)` by stráž nad surovým textem obešlo.
    ///
    /// Provinilci se sbírají **do seznamu cest** a tvrdí se prázdnost, ne `contains` u každého
    /// souboru zvlášť: `#expect(file.condensed.contains(…))` vypíše při pádu **celý zhuštěný
    /// zdroják**, takže by hláška o třech sheetech měla desítky kilobajtů a jméno souboru by se
    /// v ní ztratilo (změřeno, když se u #491 vkládala regrese).
    @Test("Sheet s idealWidth musí mít presentationSizing")
    func keepsIdealWidthWithFittedPresentationOnly() throws {
        let offenders = try sheetSources()
            .filter { $0.condensed.contains("idealWidth") && !$0.condensed.contains("presentationSizing") }
            .map(\.path)
            .sorted()
        #expect(
            offenders.isEmpty,
            "Bez `presentationSizing(.fitted)` SwiftUI ideální šířku zahodí a sheet zůstane široký jako `minWidth` (#327, #491) — a přesto si o ni říká: \(offenders)."
        )
    }

    /// **Roster sheetů je uzavřený**, aby předchozí tvrzení nešlo obejít novým souborem s jiným
    /// jménem. Sedm `.sheet(` v `App/` prezentuje právě těchhle šest typů; jakmile přibude sedmý,
    /// spadne tenhle test a jeho autor si přečte, co si o `idealWidth` má rozmyslet.
    ///
    /// **Počet prezentací se tvrdí taky**, ne jen jména souborů: bez toho by věta o „sedmi `.sheet(`“
    /// byla tvrzení, které data neunesou — sheet prezentovaný typem, který se nejmenuje `*Sheet`,
    /// by roster minul a stráž výš by o něm nevěděla. Je to hrubý drát, a schválně: přesnější
    /// tvrzení by znamenalo rozebírat, co v tom uzávěru stojí, a to už je parsování Swiftu.
    @Test("Sheety v aplikaci jsou právě tyhle")
    func pinsTheRosterOfSheets() throws {
        let presentations = try sources(under: "App")
            .reduce(0) { $0 + $1.condensed.components(separatedBy: ".sheet(").count - 1 }
        #expect(presentations == 7, "Počet `.sheet(` v `App/` je \(presentations) místo sedmi.")

        let roster = try sheetSources().map(\.path).sorted()
        #expect(
            roster == [
                "Views/AgentPromptSheet.swift",
                "Views/BranchPushSheet.swift",
                "Views/CodeTextSheet.swift",
                "Views/MergeSheet.swift",
                "Views/RawSessionSheet.swift",
                "Views/ReviewSubmissionSheet.swift",
            ],
            "Roster sheetů se změnil: \(roster)."
        )

        // A druhá strana téhož: `presentationSizing` je modifikátor prezentace, takže **mimo
        // sheety nemá co dělat**. Kdyby se objevil na okně scény, vypadalo by to jako oživení
        // ideálu — a `SettingsView` je změřený příklad toho, že se nic takového nestane.
        let elsewhere = try sources(under: "App")
            .filter { $0.condensed.contains("presentationSizing") }
            .map(\.path)
            .sorted()
        #expect(elsewhere == ["Views/CodeTextSheet.swift", "Views/RawSessionSheet.swift"])
    }

    /// Sheety jsou soubory `App/Views/*Sheet.swift`. **Předpona `Views/` tam musí být**: pod
    /// `App/Policy/` leží `CodeSheet.swift`, což je politika velikosti, ne obrazovka.
    private func sheetSources() throws -> [Source] {
        try sources(under: "App").filter { $0.path.hasPrefix("Views/") && $0.path.hasSuffix("Sheet.swift") }
    }

    private struct Source {
        let path: String
        /// Kód **bez řádkových komentářů a bez mezer** — viz dokumentace u testu výš.
        let condensed: String

        init(path: String, code: String) {
            self.path = path
            self.condensed = code.filter { !$0.isWhitespace }
        }
    }

    private func sources(under folder: String) throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let lines = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""),
                    code: lines.joined(separator: "\n")
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    // MARK: - Scéna

    /// Okno s otevřeným sheetem. Drží se v něm i hostitelské okno, aby ho nikdo neuklidil dřív, než
    /// se doměří.
    @MainActor
    private struct Opened {
        let window: NSWindow
        let sheet: NSWindow

        /// Čeká se **na výšku**, ne na šířku: šířka je u dvou ze tří sheetů daná obsahem, takže by
        /// se na ni nedalo čekat bez toho, aby se do testu napsalo číslo, o kterém nic netvrdíme.
        /// Výška se na ideál usadí v druhém průchodu rozvržení (#327), takže je to zároveň jev,
        /// který říká „sheet je hotový“.
        func wait(forHeight height: CGFloat) async throws {
            let reached = await waitUntil("sheet je \(height) bodů vysoký") { sheet.frame.height == height }
            #expect(reached, "Sheet zůstal \(sheet.frame.size) místo výšky \(height).")
        }

        func close() {
            window.endSheet(sheet)
            window.orderOut(nil)
        }
    }

    /// Postaví okno, otevře v něm sheet a počká, až ho AppKit připojí. Okno je **mimo obrazovku**,
    /// jako u ostatních sond v `Tests/Views/` — sheet se má změřit, ne ukázat.
    private func open(named name: String, hostWidth: CGFloat = 1_400) async throws -> Opened {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: hostWidth, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: Host(name: name, width: hostWidth))
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()

        let attached = await waitUntil("sheet se otevřel") { window.attachedSheet != nil }
        #expect(attached, "Sheet se v okně neotevřel.")
        return Opened(window: window, sheet: try #require(window.attachedSheet))
    }

    /// Hostitel, který sheet otevře sám — prezentuje se `sheet(isPresented:)` jako v aplikaci,
    /// takže se měří ta cesta, kterou kód doopravdy jde.
    private struct Host: View {
        let name: String
        let width: CGFloat
        @State private var open = true

        var body: some View {
            Color.clear
                .frame(width: width, height: 900)
                .sheet(isPresented: $open) { sheet }
        }

        @ViewBuilder private var sheet: some View {
            switch name {
            case "ReviewSubmissionSheet":
                ReviewSubmissionSheet(submission: SheetSizingFixture.reviewSubmission(), close: {})
            case "MergeSheet":
                MergeSheet(submission: SheetSizingFixture.merge(), close: {})
            default:
                AgentPromptSheet(
                    selection: SheetSizingFixture.agentPrompt(),
                    rebuild: { _ in SheetSizingFixture.agentPrompt() }
                )
            }
        }
    }
}

/// Materiál pro sheety v `SheetSizingTests`.
///
/// **Nejmenší možný, a je to rozhodnutí**: měří se rámec sheetu, ne jeho obsah — a obsah, který by
/// si šířku vynucoval (dlouhý řádek bez mezer), by z měření udělal měření toho obsahu. Právě proto
/// se na šířku tvrdí mez a ne rovnost, viz dokumentace u testu.
@MainActor
enum SheetSizingFixture {
    static let pullRequest = PRIdentifier("ondrajodas/prism-review-sandbox#7")!

    static func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pullRequest,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    static func reviewSubmission() -> ReviewSubmission {
        ReviewSubmission(
            pullRequest: summary(),
            draft: ReviewDraft(pullRequest: pullRequest, headSha: "aaaa1111", body: "tělo", verdict: .approve),
            suggestion: nil,
            publisher: { FakeReviewPublisher([]) },
            afterSuccess: {}
        )
    }

    static func merge() -> MergeSubmission {
        MergeSubmission(
            pullRequest: summary(),
            proposal: MergeProposal(
                pullRequest: pullRequest,
                headSha: "aaaa1111",
                head: "autor:vetev",
                base: "main",
                commits: 1,
                title: "titulek",
                defaultMethod: .squash,
                repository: RepositoryMergeSettings(
                    allowsMergeCommit: true,
                    allowsSquash: true,
                    allowsRebase: true,
                    squashBody: .commitMessages,
                    mergeCommitBody: .pullRequestTitle
                )
            ),
            publisher: { FakeReviewPublisher([]) },
            afterSuccess: {}
        )
    }

    static func agentPrompt() -> AgentPromptSelection {
        AgentPromptSelection(
            prompt: AgentPrompt(
                subject: AgentPromptSubject(pullRequest: pullRequest, branch: "vetev", headSha: "aaaa1111"),
                text: "# zadání",
                inventory: AgentPromptInventory([]),
                included: AgentPromptInventory([]),
                handed: [],
                blocking: 0,
                isConversationLoaded: true
            ),
            groups: [],
            only: nil
        )
    }
}
