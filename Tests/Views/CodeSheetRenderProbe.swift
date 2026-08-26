import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#417): vyrendruje **sheet s hunkem a sheet s logem** v obou režimech a ve
/// velikostech, se kterými se otevírají.
///
/// Proč sonda a ne měření: „je hlavička tři řádky a sedí patička s návrhem?“ je otázka na obrázek.
/// Co se **dá** tvrdit číslem, je v `CodeSheetTests` (profily velikosti), `CodeTextSheetSizingTests`
/// (okno sheetu) a `CodeSheetTextTests` (věty) — sonda je k tomu, aby se dala položit vedle sekce 28
/// návrhu.
///
/// **A hlavně: k sheetu s logem se v aplikaci klikáním nedostaneš, kdykoli se ti zachce** — chce to
/// PR se spadlým checkem, který má v odkazu číslo jobu, a stažený log. Tohle je ta cesta k němu,
/// o které mluví `docs/testovani.md` v *Jak si zkontrolovat, jak view vypadá*.
///
/// `NSHostingView` + `cacheDisplay`, ne `ImageRenderer`: v patičce logu je `Link`, který
/// `ImageRenderer` nakreslí jako žlutý placeholder.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` (prefix `TEST_RUNNER_` je to, čím `xcodebuild` proměnnou předá
/// hostu — bez něj se sonda nespustí a vypadá to, že prošla).
@MainActor
@Suite(
    "Sonda sheetu s kódem (#417)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct CodeSheetRenderProbe {
    @Test("Vyrendrovat sheet s hunkem i s logem")
    func rendersBothKinds() throws {
        let directory = Self.outputDirectory
        for scheme in [ColorScheme.dark, .light] {
            for content in [Self.hunk, Self.log] {
                let sizing = Policy.codeSheetSizing(kind: content.kind, screen: Self.screen)
                let name = "sheet-\(content.kind == .hunk ? "hunk" : "log")-\(scheme == .dark ? "tmavy" : "svetly")"
                let url = directory.appending(path: "\(name).png")
                try render(content, scheme: scheme, size: sizing.ideal, to: url)
                print("SONDA \(url.path) — \(Int(sizing.ideal.width))×\(Int(sizing.ideal.height)) b")
            }
        }
        // A ještě podlaha hunku, tedy to, co sheet dostával do #417: 560 bodů, 66 znaků na řádek.
        let floor = Policy.codeSheetHunkFloor
        let url = directory.appending(path: "sheet-hunk-podlaha.png")
        try render(Self.hunk, scheme: .dark, size: floor, to: url)
        print("SONDA \(url.path) — podlaha \(Int(floor.width))×\(Int(floor.height)) b")
    }

    /// Obrazovka, pro kterou je návrh spočítaný (`visibleFrame` 1512 × 883) — ne ta, na které sonda
    /// zrovna běží: jinak by snímky ze stroje s velkým monitorem nešly položit vedle sekce 28.
    private static let screen = CGSize(width: 1_512, height: 883)

    private func render(_ content: CodeText, scheme: ColorScheme, size: CGSize, to url: URL) throws {
        let scene = CodeTextSheet(content: content)
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
            .background(Palette.surface)
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        // Hierarchie se doskládá až po kole smyčky; `NSTextView` uvnitř navíc dostane text
        // v `updateNSView`, tedy až po prvním rozvržení.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    // MARK: - Obsah

    /// Hunk ze sekce 28 návrhu, i s tím dlouhým řádkem, který se zalomí — v kresbě je schválně.
    private static let hunk: CodeText = {
        let code = """
                public function getSecret(string $key): string
                {
                    $row = $this->cache->get($key) ?? $this->client->fetch($key);
                    if ($row === null) {
                        throw new SecretNotFoundException(sprintf('Secret %s is not in the vault at %s.', $key, $this->path($key)));
                    }
                    if (($row['value'] ?? '') === '') {
                        $this->logger->warning(sprintf('Secret %s came back empty from %s, falling back to the copy cached at %s.', $key, $this->client->endpoint(), $row['fetched_at']));
                    }
                    return $row['value'] ?? '';
                }

                /** @param array<string, string> $items */
                public function putAll(array $items, ?int $ttl = null): void
                {
                    foreach ($items as $key => $value) {
                        $this->cache->set($key, $value, $ttl ?? self::DEFAULT_TTL);
                    }
                }
            """
        return CodeText(
            kind: .hunk,
            id: "src/Vault/SecretClient.php#@@ -78,9 +78,21 @@",
            title: CodeSheetText.hunkTitle(path: "src/Vault/SecretClient.php"),
            slug: CodeSheetText.hunkSlug(
                header: "@@ -78,9 +78,21 @@ final class SecretClient",
                subject: "keboola/vault#412"
            ),
            note: CodeSheetText.hunkNote(code: code),
            path: "src/Vault/SecretClient.php",
            code: code,
            link: nil
        )
    }()

    /// Log doběhlého jobu — s timestampy, bez ANSI, jak ho sheet dostane od `Policy.jobLog`.
    private static let log: CodeText = {
        let raw = """
            2026-08-23T21:07:31.4821904Z ##[group]Run vendor/bin/phpstan analyse --level=8 --error-format=table --memory-limit=1G
            2026-08-23T21:07:33.9120041Z Note: Using configuration file /home/runner/work/vault/vault/phpstan.neon.
            2026-08-23T21:09:44.1174220Z  12/14 [============================>  ]  85%
            2026-08-23T21:09:45.2211903Z  ------ ------------------------------------------------------
            2026-08-23T21:09:45.2212904Z   Line   src/Cart.php
            2026-08-23T21:09:45.2216604Z   41     Parameter #1 $items of method Cart::addAll() expects array<Item>, array<string> given.
            2026-08-23T21:09:45.2219902Z   26     Call to an undefined method Cart::assertItems(). Did you mean Cart::assertItem() declared in src/Cart.php:118?
            2026-08-23T21:09:45.2224180Z   88     Unable to resolve the template type TValue in call to method Illuminate\\Support\\Collection::map(); consider adding @template-covariant TValue to Basket::items().
            2026-08-23T21:09:45.9930712Z  \u{1B}[31m[ERROR]\u{1B}[0m Found 2 errors
            2026-08-23T21:09:45.9931551Z Error: Process completed with exit code 1.
            """
        let prepared = Policy.jobLog(raw, fetchedAt: Date(timeIntervalSince1970: 1_787_000_000))
        return CodeText(
            kind: .log,
            id: "log:phpstan (level 8)",
            title: CodeSheetText.logTitle(check: "phpstan (level 8)"),
            slug: CodeSheetText.logSlug(prepared, subject: "keboola/vault#412"),
            note: CodeSheetText.logNote(
                outcome: .failed,
                duration: 134,
                at: Date(timeIntervalSince1970: 1_787_000_000)
            ),
            path: nil,
            code: prepared.text,
            link: URL(string: "https://github.com/keboola/vault/actions/runs/1/job/2")
        )
    }()
}
