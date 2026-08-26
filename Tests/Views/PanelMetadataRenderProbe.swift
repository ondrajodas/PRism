import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#392): vyrendruje **panel s labely a reviewery** ve všech podobách, které má
/// zákres — a k tomu tab `Commity` s panelem u seznamu i u rozkliknutého staršího commitu.
///
/// Proč sonda: „sedí to se sekcemi 24 a 25?“ je otázka na obrázek. Co se **dá** tvrdit číslem, je
/// v `LabelChipsTests` (pravidlo zalomení), `PanelMetadataWidthTests` (rozměr přes pásmo)
/// a `PanelHeadNoticeTests` (věta a to, že na ni panel reaguje).
///
/// `NSHostingView`, ne `ImageRenderer` — tatáž cesta jako u ostatních sond, viz `docs/testovani.md`:
/// obsah `ScrollView`u se offscreen nerasterizuje.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda panelu s labely a reviewery (#392)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct PanelMetadataRenderProbe {
    /// Podoby panelu — přesně ty, které kreslí sekce 24.
    @Test("Vyrendrovat panel na cizím i vlastním PR")
    func rendersThePanel() throws {
        let scenes: [(String, CGFloat, AnyView)] = [
            ("panel-cizi-300", 300, AnyView(Self.panel(editing: .absent, labels: Self.shortLabels))),
            ("panel-vlastni-300", 300, AnyView(Self.panel(editing: .allowed, labels: [Self.shortLabels[0]]))),
            ("panel-vlastni-dlouha-300", 300, AnyView(Self.panel(editing: .allowed, labels: Self.longLabels))),
            ("panel-vlastni-podlaha-240", 240, AnyView(Self.panel(editing: .allowed, labels: Self.longLabels, width: 240))),
            ("panel-zakazana-brana-300", 300, AnyView(Self.panel(
                editing: .blocked(PublishError.publishingNotAllowed(Self.repo).userDescription),
                labels: Self.shortLabels
            ))),
            ("panel-porucha-300", 300, AnyView(Self.failedPanel)),
            ("panel-zalozil-nepridal-300", 300, AnyView(Self.createdNotAddedPanel)),
        ]

        for (name, width, scene) in scenes {
            let url = Self.outputDirectory.appending(path: "\(name).png")
            try Self.render(scene, width: width + 40, height: 260, to: url)
            print("SONDA \(url.path)")
        }
    }

    /// Nabídky (#392): plná, po filtru, s prázdným výsledkem a nenačtená.
    @Test("Vyrendrovat nabídky labelů a reviewerů")
    func rendersThePickers() throws {
        let scenes: [(String, AnyView)] = [
            ("nabidka-reviewery", AnyView(Self.reviewerPicker(loaded: true))),
            ("nabidka-reviewery-nenactena", AnyView(Self.reviewerPicker(loaded: false))),
            ("nabidka-labely", AnyView(Self.labelPicker())),
            // Sekce 26: dotaz bez shody, dotaz, který něco našel, shoda jen v casingu (bez akce),
            // a druhá obrazovka.
            ("nabidka-labely-zalozit", AnyView(Self.labelPicker(query: "design-debt"))),
            ("nabidka-labely-zalozit-nalezeno", AnyView(Self.labelPicker(query: "bug-ui"))),
            ("nabidka-labely-existuje", AnyView(Self.labelPicker(query: "Bug"))),
            ("nabidka-labely-potvrzeni", AnyView(Self.newLabelConfirmation)),
        ]

        for (name, scene) in scenes {
            let url = Self.outputDirectory.appending(path: "\(name).png")
            // Vyšší plátno než nabídka: strop seznamu je 320 bodů a k němu jde nadpis a hledací
            // řádek — na nižším by se nadpis odřízl a sonda by ukazovala nabídku bez toho, co je
            // na ní u #392 nové.
            try Self.render(scene, width: 360, height: 440, to: url)
            print("SONDA \(url.path)")
        }
    }

    /// Druhá obrazovka nabídky **v obou režimech** (#413).
    ///
    /// `ImageRenderer` s nasazeným `NSAppearance`, ne okno: potvrzení nemá `ScrollView`, takže se
    /// offscreen nakreslí celé — a jedině takhle se dá vyfotit světlý režim, protože barvy z palety
    /// jsou dynamické `NSColor`y a rozhoduje o nich **kreslicí** appearance, ne `colorScheme`
    /// v prostředí. Světlý režim má vlastní snímek schválně: výstraha stojí na
    /// `Palette.stale.opacity(0.11)` a bledý puntík labelu na obtažení `--line`, tedy na dvou
    /// věcech, které se v každém motivu chovají z jiné strany.
    @Test("Vyrendrovat potvrzení nového labelu v obou režimech", arguments: [false, true])
    func rendersTheConfirmationInBothAppearances(dark: Bool) throws {
        let url = Self.outputDirectory.appending(path: "nabidka-potvrzeni-\(dark ? "tmavy" : "svetly").png")
        let scene = Self.newLabelConfirmation
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(Palette.chrome)

        var image: NSImage?
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 2
            image = renderer.nsImage
        }

        let rendered = try #require(image)
        let bitmap = try #require(rendered.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        print("SONDA \(url.path)")
    }

    /// Panel u seznamu commitů a u rozkliknutého staršího commitu — sekce 25.
    @Test("Vyrendrovat panel s nálezy proti hlavě a u staršího commitu")
    func rendersTheHeadNotice() throws {
        let scenes: [(String, Policy.FindingsHeadNotice)] = [
            ("commity-panel-nad-seznamem", .head(Self.head)),
            ("commity-panel-starsi-commit", .mismatch(head: Self.head, commit: Self.older)),
        ]

        for (name, notice) in scenes {
            let url = Self.outputDirectory.appending(path: "\(name).png")
            try Self.render(AnyView(Self.reviewPanel(notice: notice)), width: 340, height: 420, to: url)
            print("SONDA \(url.path)")
        }
    }

    // MARK: - Scéna

    private static let repo = RepoID(owner: "keboola", name: "vault")
    private static let head = "e8d4a60f1c2d3e4f5061728394a5b6c7d8e9f012"
    private static let older = "5e2b1aa31f6c0a2a7f2f0a1b3c4d5e6f70819293"

    /// Barvy jsou skutečné výchozí barvy GitHubu, jako v zákresu.
    private static let shortLabels = [
        PullRequestLabel(name: "dependencies", color: "0366D6"),
        PullRequestLabel(name: "bug", color: "D73A4A"),
    ]

    private static let longLabels = [
        PullRequestLabel(name: "enhancement", color: "A2EEEF"),
        PullRequestLabel(name: "needs-design-review-and-product-signoff", color: "D4C5F9"),
        PullRequestLabel(name: "dependencies", color: "0366D6"),
        PullRequestLabel(name: "bug", color: "D73A4A"),
    ]

    /// Vyžádané týmy — skutečný slug z `keboola/platform-architecture-and-concepts#278`.
    private static let teams = ["ajda-swimlane"]

    private static let reviewers = [
        RequestedReviewer(login: "ondrajodas", answer: .approved),
        RequestedReviewer(login: "katerina-prochazkova-mala", answer: .changesRequested),
        RequestedReviewer(login: "marie-zikova", answer: .waiting),
    ]

    @MainActor private static func panel(
        editing: Policy.MetadataEditing,
        labels: [PullRequestLabel],
        width: Double = 300
    ) -> some View {
        PanelMetadataView(
            state: .loaded(
                PullRequestMetadata(labels: labels, reviewers: reviewers, teams: teams),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            editing: editing,
            repo: repo,
            contentWidth: PanelMetadataView.contentWidth(inPanelOf: width),
            known: longLabels,
            candidates: [.person("odinuv"), .team("ajda-swimlane")]
        )
        .frame(width: width, alignment: .topLeading)
        .background(Palette.chrome)
    }

    /// Panel s větou o tom, že se label založil a přidat se nepovedlo (#413) — druhá obrazovka
    /// sekce 26.
    @MainActor private static var createdNotAddedPanel: some View {
        PanelMetadataView(
            state: .loaded(
                PullRequestMetadata(labels: [shortLabels[0]], reviewers: [reviewers[2]]),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            editing: .allowed,
            repo: repo,
            contentWidth: PanelMetadataView.contentWidth(inPanelOf: 300),
            known: longLabels,
            actionState: .createdNotAdded(
                name: "design-debt",
                error: .network("dial tcp: lookup api.github.com")
            )
        )
        .frame(width: 300, alignment: .topLeading)
        .background(Palette.chrome)
    }

    @MainActor private static var failedPanel: some View {
        PanelMetadataView(
            state: .failed(GitHubError.network("dial tcp: lookup api.github.com").userDescription),
            editing: .allowed,
            repo: repo,
            contentWidth: PanelMetadataView.contentWidth(inPanelOf: 300)
        )
        .frame(width: 300, alignment: .topLeading)
        .background(Palette.chrome)
    }

    @MainActor private static func reviewPanel(notice: Policy.FindingsHeadNotice) -> some View {
        let pr = PRIdentifier(repo: repo, number: 85)
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
            metadata: .loaded(
                PullRequestMetadata(labels: shortLabels, reviewers: Array(reviewers.prefix(2))),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            metadataEditing: .absent,
            headNotice: notice,
            tab: .constant(.findings)
        )
        .background(Palette.background)
    }

    /// Skutečné loginy z `orgs/keboola` a slugy týmů — nabídka o čtrnácti řádcích je zrovna ten
    /// stav, kvůli kterému hledání přibylo.
    @MainActor private static func reviewerPicker(loaded: Bool) -> some View {
        let people = [
            "adamvoves", "BagToad", "dasa-novakova", "ErikZigo", "halinapetrikova",
            "jirkanovak", "odinuv", "petramala", "sergiou87", "tomaskraus",
        ]
        return ReviewerPickerView(
            candidates: people.map { .person($0) } + ["ajda-swimlane", "platform"].map { .team($0) },
            isLoaded: loaded,
            request: { _ in },
            load: {}
        )
        .frame(width: 340, alignment: .topLeading)
        .background(Palette.chrome)
    }

    /// Labely, které v zákresu zná repozitář.
    private static let repositoryLabels = [
        PullRequestLabel(name: "bug", color: "D73A4A"),
        PullRequestLabel(name: "bug-ui-legacy", color: "D73A4A"),
        PullRequestLabel(name: "dependencies", color: "0366D6"),
        PullRequestLabel(name: "enhancement", color: "A2EEEF"),
        PullRequestLabel(name: "go", color: "16E2E2"),
        PullRequestLabel(name: "needs-design-review", color: "D4C5F9"),
        PullRequestLabel(name: "ready-for-review", color: "39D965"),
        PullRequestLabel(name: "unmet-requirements", color: "EE2329"),
    ]

    @MainActor private static func labelPicker(
        query: String = "",
        editing: Policy.MetadataEditing = .allowed
    ) -> some View {
        LabelPickerView(
            repo: RepoID(owner: "ondrajodas", name: "PRism"),
            known: repositoryLabels,
            selected: [PullRequestLabel(name: "bug", color: "D73A4A")],
            isLoaded: true,
            editing: editing,
            toggle: { _ in },
            create: { _ in },
            load: {},
            // Dotaz se nastaví **jako by ho člověk napsal** — sonda nemá klávesnici, takže se
            // počáteční hodnota předává parametrem, který kvůli tomu existuje.
            query: query
        )
        .frame(alignment: .topLeading)
        .background(Palette.chrome)
    }

    /// Druhá obrazovka nabídky — potvrzení nového labelu (#413).
    @MainActor private static var newLabelConfirmation: some View {
        LabelPickerView(
            repo: RepoID(owner: "ondrajodas", name: "PRism"),
            known: repositoryLabels,
            selected: [],
            isLoaded: true,
            toggle: { _ in },
            create: { _ in },
            load: {},
            query: "design-debt",
            // **Label se bere z `Policy`, ne se vypisuje ručně** — sonda pak fotí tu barvu, kterou
            // aplikace doopravdy pošle.
            confirming: Policy.newLabelOffer(
                query: "design-debt",
                known: repositoryLabels,
                isLoaded: true,
                editing: .allowed
            )
        )
        .frame(alignment: .topLeading)
        .background(Palette.chrome)
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond.
    private static func render(_ scene: AnyView, width: CGFloat, height: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene.frame(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
