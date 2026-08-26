import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#298, rozšířeno #309): vykreslí **tabulku nálezů a bublinu u kódu vedle sebe**
/// v obou režimech, aby se dalo vidět, že „klikni sem“ má v okně jednu barvu — a od #309 i to, že
/// **stav má druhou**. Obojí naráz na jednom plátně: akce akcentem, konstatování mintem.
///
/// Existuje vedle `AccentLinkButtonTests` proto, že měření odpovídá na „kolik je kontrast“, kdežto
/// otázka #298 je „vypadají obě formy akce jako táž věc“. Na tu se dá odpovědět jedině obrázkem —
/// a musí být na jednom plátně: dva snímky pod sebou se porovnávají po paměti, což je zrovna to,
/// čemu se tady vyhýbáme.
///
/// **`NSHostingView`, ne `ImageRenderer`.** Ten `ScrollView` nevykreslí vůbec (tabulka je v něm)
/// a odkaz v něm vyjde jako žlutý placeholder, takže by o barvě akce neřekl nic. Postup je
/// v `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda barvy akcí a stavů u nálezu (#298, #309)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct FindingActionColourProbe {
    /// Šířka, ve které tabulka má **všech šest sloupců** (`Policy.findingTableReviewerBreakpoint`).
    /// Pod ní odpadá reviewer a řada akcí se nemění, takže na barvu je to táž otázka.
    private let tableWidth: CGFloat = 980

    @Test("Vyrendrovat tabulku a bublinu vedle sebe")
    func rendersTableNextToBubble() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for dark in [false, true] {
            let url = directory.appending(path: "akce-\(dark ? "tmavy" : "svetly").png")
            try write(dark: dark, to: url)
            print("SONDA \(url.path)")
        }
    }

    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(dark: Bool, to url: URL) throws {
        let scene = scene(dark: dark)
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: Error?
        appearance.performAsCurrentDrawingAppearance {
            do {
                try capture(scene, width: tableWidth, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Tabulka nahoře, bublina pod ní, a **stavový řádek na konci** — tři místa, kde po #298 stojí
    /// tatáž barva. Bublina se kreslí bez tabulky kolem, aby byla vidět celá i s řadou tlačítek.
    private func scene(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("tabulka nálezů — akce jsou barevný text (`.go`)")
            rows
            label("bublina u kódu — táž akce jako tlačítko (`.mini`, #283)")
            FindingBubbleView(group: Self.blockingGroup, draft: Self.draft, actions: Self.actions, indent: 0)
                .padding(.horizontal, FindingTableLayout.inset)
            label("bublina se shodou a s převzatým nálezem — `2×` i `✓ v mém review` mintem (#309)")
            // **Se značkou** (`toggle`), jinak se `2×` nekreslí vůbec: `showsMark` je `false`, dokud
            // se bublina nedá sbalit, a odznak shody sedí právě v ní.
            FindingBubbleView(
                group: Self.agreedGroup,
                draft: Self.draft,
                actions: Self.actions,
                indent: 0,
                toggle: {}
            )
            .padding(.horizontal, FindingTableLayout.inset)
            label("stavový řádek — `Připravit` je akce (akcent), souhrn fronty je stav (mint)")
            statusBar
            label("odznaky stavu review — `běží` je akcent, `odmítnuto` mint (#309)")
            stateBadges
        }
        .frame(width: tableWidth, alignment: .topLeading)
        .background(Palette.surface)
        // **`tint` musí být i v sondě**, protože ho skutečné okno nese na kořeni (`ContentView`).
        // Do #309 z něj četl `✓ v mém review` (`.foregroundStyle(.tint)`) a bez tintu by vyšel
        // systémově modrý; od #309 si obě značky berou `FindingBadgeAppearance.stateTint`, takže
        // na tintu nevisí ani jedna. Zůstává tu proto, že ho nese skutečné okno a sonda má
        // kreslit totéž — a protože pod ním je vidět, že `2×` **není** akcent, ne že by nemohl.
        .tint(Palette.accent)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Řádky, každý s jinou akcí: `Převzít`, `⋯` u shody `2×`, `✓ v mém review` (převzatý nález
    /// s jediným reviewerem) a **`Vrátit` na odmítnutém řádku**, který je ten jediný ztlumený.
    private var rows: some View {
        let layout = Policy.findingTableLayout(availableWidth: tableWidth)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.tableRows, id: \.id) { row in
                FindingTableRowView(
                    row: row,
                    layout: layout,
                    isCurrent: row.id == Self.tableRows.first?.id,
                    findingActions: Self.actions,
                    draft: Self.draft,
                    toggle: {},
                    jump: {}
                )
            }
        }
    }

    /// Pruh se stejnou sazbou jako `StatusBarView` — plocha `chrome`, popisek `ink2`, akce akcentem.
    /// Vlastní `AppStore` se kvůli jednomu tlačítku nestaví; sonda se ptá na **barvu**, a ta je
    /// v `AccentLinkButtonStyle`, ne ve storu.
    ///
    /// **Souhrn fronty je tu od #309** a je to jediné místo v okně, kde stav a akce sedí ve stejném
    /// pruhu pár desítek bodů od sebe — tedy to místo, kde se ta dvojice barev musí ukázat.
    private var statusBar: some View {
        HStack(spacing: 5) {
            Text(verbatim: "Pracovní kopie zatím není · HEAD 4f2ac91")
                .font(.caption)
                .foregroundStyle(Palette.ink2)
            Button("Připravit") {}
                .buttonStyle(.accentLink)
                .font(.caption)
            Spacer(minLength: 0)
            QueueSummaryView(summary: QueueSummary(pullRequests: 5, blocking: 1, drafts: 2))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    /// Odznaky ze seznamu PR — dvě barvy, které #309 přesunulo do palety, vedle těch, které v ní
    /// nejsou. `běží` byl do #309 systémově modrý, `odmítnuto` systémově tyrkysové.
    private var stateBadges: some View {
        HStack(spacing: 7) {
            ReviewStateBadge(state: .running(finished: 2, total: 3))
            ReviewStateBadge(state: .dismissed(findings: 3))
            ReviewStateBadge(state: .clean)
            ReviewStateBadge(state: .completed(findings: 3), blocking: 1)
            ReviewStateBadge(state: .stale)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FindingTableLayout.inset)
        .padding(.bottom, 14)
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, FindingTableLayout.inset)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    // MARK: - Materiál

    private static let actions = FindingActions()
    /// `canCompose` musí být `true`, jinak se `Převzít` ani `✓ v mém review` nekreslí — a sonda by
    /// mlčky ukázala řádek bez té akce, na kterou se ptá.
    ///
    /// Převzatý je **nález s jediným reviewerem**: `adoption(of:)` se u shody `2×` nekreslí vůbec
    /// (za celý řádek není co převzít), takže odznak by na řádku `2×` nevyšel a chybělo by v sondě
    /// právě to místo, kde vedle sebe stojí stav a akce.
    ///
    /// Převzatá je od #309 **i dvojice se shodou** — jedině tak je v bublině vidět `2×` a
    /// `✓ v mém review` naráz, tedy obě místa, kde mint stojí vedle akcentové akce. Na tabulku to
    /// nemá vliv: `adoption(of:)` se u řádku se dvěma nálezy nekreslí.
    private static let draft = FileDraftActions(
        canCompose: true,
        isAdopted: { $0.summary.hasPrefix("Šifrovací klíč") || $0.summary.hasPrefix("Timeout") }
    )

    private static func finding(
        _ summary: String,
        reviewer: String,
        category: String,
        file: String? = "SecretClient.php",
        line: Int? = 81
    ) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: file,
                line: line,
                category: category,
                verdict: .confirmed,
                shortSummary: nil,
                summary: summary,
                failureScenario: "Secret zmizí z Vaultu, podpis se spočítá z prázdného klíče a request projde."
            ),
            reviewer: reviewer,
            headSha: "4f2ac91"
        )
    }

    private static let blocking = finding(
        "`?? ''` schová chybějící secret jako prázdnou hodnotu",
        reviewer: "php-review",
        category: "correctness"
    )
    private static let agreed = finding(
        "Timeout se nastavuje až po vytvoření klienta, takže první dotaz jde bez něj",
        reviewer: "php-review",
        category: "correctness",
        line: 44
    )
    private static let agreedSecond = finding(
        "Timeout se nastavuje až po vytvoření klienta, takže první dotaz jde bez něj",
        reviewer: "security-review",
        category: "correctness",
        line: 44
    )
    private static let adopted = finding(
        "Šifrovací klíč se v debug režimu vypíše do logu",
        reviewer: "security-review",
        category: "security",
        file: "Encryptor.php",
        line: 41
    )
    private static let dismissed = finding(
        "Nová výjimka `SecretNotFound` nemá test",
        reviewer: "test-coverage",
        category: "test-coverage",
        file: nil,
        line: nil
    )

    private static let blockingGroup = FindingGroup(file: blocking.file, line: blocking.line, findings: [blocking])
    private static let agreedGroup = FindingGroup(
        file: agreed.file,
        line: agreed.line,
        findings: [agreed, agreedSecond]
    )

    private static let tableRows = FindingTableRow.rows(
        of: [blocking, agreed, agreedSecond, adopted, dismissed],
        sort: nil,
        dismissals: [
            Policy.key(of: dismissed): FindingDismissal(reason: .invalid, dismissedAt: Date(timeIntervalSince1970: 1_754_000_000))
        ]
    )

    // MARK: - Kreslení

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako
    /// `OverviewRenderProbe` (#291), viz `docs/testovani.md`.
    private func capture(_ scene: some View, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — vedle sebe běží víc slotů a cizí okno
        // je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        // Hierarchie se doskládá až po jednom kole smyčky, takže se výška bere znovu až za ní.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.frame.size.height = hosting.fittingSize.height
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
