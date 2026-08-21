import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#327): vyrendruje **sheet se surovou session** i všechny tři podoby „přepis tu
/// není“.
///
/// Otázka je na obrázek — „dá se přepis přečíst, je z hlavičky poznat, že je to snímek, a poznají se
/// ty tři chybové stavy od sebe?“ Čísla o tom, co se kdy kreslí, drží `RawSessionPolicyTests`
/// a `RawSessionScriptTests`; tady se to dá srovnat se sekcí 20 návrhu.
///
/// **Existuje proto, že k tabu `Průběh` v běžícím okně vede jedině klik** a aplikaci nesmí sonda
/// ovládat. Tohle je jediná cesta, jak se na tu obrazovku podívat bez skutečné session na disku.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR`. Prefix `TEST_RUNNER_` je podmínka, ne ozdoba — `xcodebuild`
/// jinak proměnnou do testovacího procesu nepředá a suita se **tiše přeskočí**.
@MainActor
@Suite(
    "Sonda surové session (#327)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct RawSessionRenderProbe {
    private let target = RawSessionTarget(
        sessionID: "4b90c7e2-1d55-4f0a-9c3e-77b0a2e41d6f",
        worktree: URL(filePath: "/tmp/cache/worktrees/keboola/connection-php-client/412-9c1de02"),
        skill: "security-review",
        slug: "keboola/connection-php-client#412"
    )

    @Test("Vyrendrovat sheet s přepisem")
    func rendersTheTranscript() throws {
        let directory = renderDirectory()
        for scheme in [ColorScheme.dark, .light] {
            let name = scheme == .dark ? "tmavy" : "svetly"
            let url = directory.appending(path: "surova-session-\(name).png")
            try render(sheet(state: .shown(transcript())), scheme: scheme, height: 640, to: url)
            print("SONDA \(url.path)")
        }
    }

    @Test("Vyrendrovat tři podoby chybějícího přepisu")
    func rendersEveryFailure() throws {
        let directory = renderDirectory()
        let states: [(String, RawTranscriptState)] = [
            ("neni", .missing),
            ("necitelny", .unreadable(TranscriptUnreadable.invalidEncoding.reason)),
            ("prazdny", .empty(bytes: 0)),
            ("neprecetlo-se-nic", .empty(bytes: 1_204_000)),
            ("cte-se", .loading),
        ]
        for (name, state) in states {
            let url = directory.appending(path: "surova-session-\(name).png")
            try render(sheet(state: state), scheme: .dark, height: 460, to: url)
            print("SONDA \(url.path)")
        }
    }

    // MARK: - Scéna

    /// Přírůstek se předává **jen u přepisu, který je** — v aplikaci to rozhoduje
    /// `AppStore.rawSessionGrowth()` a je to jedno místo. Sonda, která by ho dodala i k chybovému
    /// stavu, by kreslila obrazovku, jaká v aplikaci nevznikne.
    private func sheet(state: RawTranscriptState) -> some View {
        var shown = false
        if case .shown = state { shown = true }
        return RawSessionSheet(
            target: target,
            state: state,
            growth: shown ? 1_258_000 : nil,
            path: URL(filePath: "/Users/ondra/.claude/projects/-tmp-cache-.../\(target.sessionID).jsonl"),
            reload: {},
            refreshSize: {}
        )
    }

    /// Přepis, ve kterém je od každého druhu události jedna — a k tomu **obě** další přiznání
    /// zkrácení: řez na začátku textu a ořez uvnitř události.
    private func transcript() -> RawTranscript {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var events: [TranscriptEvent] = []
        func add(
            _ kind: TranscriptEvent.Kind,
            _ offset: Double,
            subject: String? = nil,
            body: String? = nil,
            cut: String? = nil,
            denied: Bool = false
        ) {
            events.append(TranscriptEvent(
                id: events.count,
                at: start + offset,
                kind: kind,
                subject: subject,
                body: body,
                bodyCut: cut,
                isDenied: denied
            ))
        }

        add(.system("queue-operation"), 0, subject: "enqueue")
        add(.system("attachment"), 1, subject: "skill_listing")
        add(
            .tool("Grep"),
            13,
            subject: "-rn \"getSecret\\|setSecret\" src tests --include=*.php",
            body: """
            src/Client/SecretClient.php:118:    public function getSecret(string $key): ?string
            src/Client/SecretClient.php:139:    public function setSecret(string $key, string $value): void
            tests/Client/SecretClientTest.php:44:        $this->client->setSecret('a', 'b');
            """,
            cut: "… + 61 řádků nad strop události"
        )
        add(
            .prose,
            14,
            subject: "próza · 0,4 kB",
            body: """
            Ten fallback v getSecret mi nesedí — vrací prázdný řetězec místo null, takže volající \
            nepozná rozdíl mezi „secret není“ a „secret je prázdný“. Podívám se, jestli na tom někdo \
            staví.
            """
        )
        add(
            .thinking,
            15,
            subject: "1,4 kB",
            body: """
            Nejdřív ověřit, jestli je to vůbec nová věc, nebo to tak bylo i před tímhle PR. \
            git log na ten soubor by to řekl rychleji než čtení historie testů.
            """
        )
        add(
            .tool("Bash"),
            16,
            subject: "gh pr view 412 --json reviews",
            body: "Claude requested permissions to use Bash, but you haven't granted it yet.",
            denied: true
        )
        add(.image(bytes: 412_000), 17)
        add(
            .report,
            26,
            subject: "2 nálezy",
            body: """
            {"findings":[{"file":"src/Client/SecretClient.php","line":120,"severity":"blocking",\
            "summary":"Prázdný secret projde jako platný — fallback vrací '' místo null."}]}
            """
        )
        add(.unreadable, 27, body: "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"te")

        return RawTranscript(
            events: events,
            omittedBytes: 5_100_000,
            fileBytes: 9_100_000,
            takenAt: start + 26,
            unreadableLines: 1
        )
    }

    // MARK: - Kresba

    private func renderDirectory() -> URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    /// **Režim se vynucuje na svém okně, ne na `NSApp`** (#367): globální stav procesu je jedna
    /// hodnota na celý testovací host a píše ho i hostitel sám.
    private func render(_ scene: some View, scheme: ColorScheme, height: CGFloat, to url: URL) throws {
        // **Šířka je ta, se kterou se sheet doopravdy otevře**, ne zadrátovaných 940 z návrhu:
        // od roztahovatelného sheetu ji drží `Policy`, takže obrázek jinak kreslí užší obrazovku,
        // než jakou uživatel uvidí.
        let width = Policy.rawSessionSheetIdealWidth
        let hosting = NSHostingView(rootView: scene.frame(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("kresba se nepodařila")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            Issue.record("PNG se nepodařilo složit")
            return
        }
        try data.write(to: url)
    }
}
