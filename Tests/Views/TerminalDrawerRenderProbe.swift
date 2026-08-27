import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#459): vyrendruje **zásuvku s terminálem** — s obsahem i bez pracovní kopie.
///
/// Otázka je na obrázek: „sedí hlavička se sekcí 35 návrhu, je kapsle `plná práva` vidět a je text
/// v ploše emulátoru čitelný v obou režimech?“ Čísla o výšce a o tom, co se kdy kreslí, drží
/// `TerminalDrawerTests`.
///
/// **Existuje proto, že k zásuvce v běžícím okně vede jedině `` ⌃` `` nad otevřeným pull requestem
/// s kopií repa v cache** — a aplikaci sonda ovládat nesmí.
///
/// **Žádný shell se nespouští.** Plocha se naplní `feed(text:)`, tedy toutéž cestou, jakou do ní
/// tečou bajty z pty — jen bez procesu, který by běh testů přežil.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR`. Prefix `TEST_RUNNER_` je podmínka, ne ozdoba — `xcodebuild`
/// jinak proměnnou do testovacího procesu nepředá a suita se **tiše přeskočí**.
@MainActor
@Suite(
    "Sonda zásuvky s terminálem (#459)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct TerminalDrawerRenderProbe {
    private let pullRequest = PRIdentifier("keboola/vault#85")!
    private let directory = URL(
        filePath: "/Users/ondra/Library/Application Support/PRism/worktrees/keboola/vault/85-9c1de02"
    )

    @Test("Vyrendrovat zásuvku s běžícím shellem")
    func rendersTheDrawer() throws {
        let host = ProbeTerminalHost(script: Self.script)
        for scheme in [ColorScheme.dark, .light] {
            let name = scheme == .dark ? "tmavy" : "svetly"
            let url = renderDirectory().appending(path: "terminal-zasuvka-\(name).png")
            try render(
                drawer(directory: directory, state: .running, host: host),
                scheme: scheme,
                to: url
            )
            print("SONDA \(url.path)")
        }
    }

    /// Dva stavy, u kterých se nekreslí plocha emulátoru: shell, který skončil s nenulovým kódem,
    /// a pull request, ke kterému v cache není kopie repa.
    @Test("Vyrendrovat zásuvku bez kopie repa a po pádu shellu")
    func rendersTheEdgeStates() throws {
        let host = ProbeTerminalHost(script: Self.script)
        let scenes: [(String, URL?, TerminalRunState?)] = [
            ("bez-kopie", nil, nil),
            ("skoncil", directory, .exited(code: 130)),
        ]
        for (name, directory, state) in scenes {
            let url = renderDirectory().appending(path: "terminal-zasuvka-\(name).png")
            try render(drawer(directory: directory, state: state, host: host), scheme: .dark, to: url)
            print("SONDA \(url.path)")
        }
    }

    // MARK: - Scéna

    private func drawer(
        directory: URL?,
        state: TerminalRunState?,
        host: any TerminalHosting
    ) -> some View {
        TerminalDrawerView(
            pullRequest: pullRequest,
            directory: directory,
            state: state,
            host: directory == nil ? nil : host,
            available: 700,
            close: {}
        )
    }

    /// To, co v zásuvce doopravdy uvidí — navázaná session v `claude`, jak ji kreslí sekce 35.
    private static let script = """
        \u{1B}[2m$ claude --resume 8c1f0ab2\u{1B}[0m\r
        \u{1B}[35m✻\u{1B}[0m Navazuji na session z \u{1B}[2m10:41\u{1B}[0m · php-review · 14 kol\r
        \r
        \u{1B}[32m>\u{1B}[0m proč jsi u toho timeoutu nehlásil nález?\r
        \u{1B}[2m  Přečetl jsem SecretClient.php:112 a timeout je tam nastavený\r
          na 30 s v konstruktoru, takže se na tuhle cestu nevztahuje…\u{1B}[0m\r
        \r
        \u{1B}[32m>\u{1B}[0m\u{20}
        """

    private func renderDirectory() -> URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    /// **Režim se vynucuje na svém okně, ne na `NSApp`** (#367): globální stav procesu je jedna
    /// hodnota na celý testovací host a píše ho i hostitel sám.
    ///
    /// Výška je ta, se kterou se zásuvka doopravdy otevře (`Policy`), ne číslo z návrhu — jinak by
    /// obrázek kreslil jinou obrazovku, než jakou uživatel uvidí. Šířka odpovídá detailu PR
    /// v okně 1100 bodů bez railu.
    private func render(_ scene: some View, scheme: ColorScheme, to url: URL) throws {
        let width: CGFloat = 1_048
        let height = Policy.terminalDrawerHeight(stored: 0, available: 700)
        let hosting = NSHostingView(rootView: scene.frame(width: width))
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
        // `orderFrontUnanimated`, ne `orderFront` — animace objevení okna zasekávala plný běh (#462).
        window.orderFrontUnanimated()
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

/// Hostitel, který vyrobí **skutečnou plochu emulátoru**, ale žádný shell nespustí.
///
/// Kreslí se tedy to, co uvidí uživatel — včetně řezu, palety a rozboru escape sekvencí —, jen
/// bajty nepřitečou z pty, ale z `feed(text:)`.
@MainActor
private final class ProbeTerminalHost: TerminalHosting {
    private let script: String
    private var views: [PRIdentifier: EmbeddedTerminalView] = [:]

    init(script: String) { self.script = script }

    var report: (@MainActor (PRIdentifier, TerminalRunState) -> Void)?
    var focusChanged: (@MainActor (Bool) -> Void)?
    var runningTerminals: Int { views.count }

    func terminal(for pr: PRIdentifier, in directory: URL) -> NSView {
        if let existing = views[pr] { return existing }
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 1_048, height: 260))
        view.font = TerminalHost.font
        view.applyPalette()
        view.feed(text: script)
        views[pr] = view
        return view
    }

    @discardableResult
    func stopTerminal(for pr: PRIdentifier) -> Bool { views.removeValue(forKey: pr) != nil }

    func stopAllTerminals() { views.removeAll() }
}
