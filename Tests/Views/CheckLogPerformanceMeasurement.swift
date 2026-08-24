import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Měření, ne test (#214, rozšířeno u #292 a #303) — kolik stojí ukázat log jobu. Nic netvrdí, vypisuje
/// čísla.
///
/// Existuje proto, že stropy na velikost logu mají být **změřené, ne odhadnuté** (viz #275 o ceně
/// sazby textu). Časy se nehlídají `#expect`em: na jiném stroji vyjdou jinak a byl by z toho test,
/// který padá bez chyby v kódu.
///
/// **Jak to pustit.** Suita je vypnutá, dokud není `PRISM_MEASURE`, a předává se s prefixem
/// `TEST_RUNNER_` — jen to `xcodebuild` do testovacího procesu pustí:
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_LOG_FILE=/cesta/job.log \
///     xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
///     -only-testing:PRismTests/CheckLogPerformanceMeasurement > /tmp/mereni.log 2>&1
/// ```
///
/// **Opraveno u #303**: do té doby tu stálo, že to `xcodebuild` nepředá ani s prefixem a že se musí
/// pouštět z Xcode. Není to pravda — vyzkoušeno, `TEST_RUNNER_PRISM_MEASURE=1` k `ProcessInfo`
/// dorazí (a stejně to má popsané `docs/testovani.md` u sondy sazby). Vypnutá suita přitom nevypadá
/// jinak než proběhlá, takže ta domněnka stála za to, že se měření po #292 nepustilo znovu.
///
/// Ochrana sama zbytečná není: měření SwiftUI `Text`u na deseti tisících řádcích trvá dvě a půl
/// minuty **na hlavním vlákně**, takže v běžném běhu vyhladoví celou sadu.
///
/// **Log je syntetický, ale podle skutečného** — a když je po ruce ten skutečný, vezme se on:
/// `PRISM_LOG_FILE`. Tvar je změřený na `keboola/job-queue-daemon`,
/// job `93844012547` — největší log na našich repech: 8,78 MB, 25 533 řádků, nejdelší řádek 2 258
/// znaků, 272 řádků nad tisíc znaků, timestamp na 25 528 z nich. Osmimegový soubor se do repa
/// nepřikládá (fixtures jsou skutečné výstupy, ale ne takhle velké).
@Suite(
    "Měření ceny logu (#214, #292, #303)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
@MainActor
struct CheckLogPerformanceMeasurement {
    /// Log o daném počtu řádků s **rozdělením délek podle skutečného**: většina krátká, hrst
    /// dlouhých. Právě ty dlouhé jsou pro zalamování horší než počet řádků.
    private func log(lines: Int, longEvery: Int = 21, longest: Int = 2258) -> String {
        (0..<lines).map { index in
            let stamp = "2026-08-11T16:09:11.263691\(index % 10)Z"
            let length = index % longEvery == 0 ? longest : 80
            let payload = String(repeating: "x", count: length)
            return "\(stamp) \(payload)"
        }
        .joined(separator: "\n")
    }

    /// Skutečný log, když je po ruce (`PRISM_LOG_FILE`); jinak syntetický o stejném počtu řádků.
    private func realLog() -> String? {
        guard let path = ProcessInfo.processInfo.environment["PRISM_LOG_FILE"] else { return nil }
        return try? String(contentsOf: URL(filePath: path), encoding: .utf8)
    }

    private func ms(_ body: () -> Void) -> String {
        let clock = ContinuousClock()
        let elapsed = clock.measure { body() }
        let millis = Double(elapsed.components.attoseconds) / 1e15
            + Double(elapsed.components.seconds) * 1000
        return String(format: "%.2f", millis)
    }

    // MARK: - Příprava textu

    /// **Cena, kterou se platí při každém rozbalení checku**, bez ohledu na strop — a proto od #292
    /// běží mimo hlavní vlákno. Naměřeno na skutečném 8,78MB logu: ANSI 192 ms, timestampy 348 ms,
    /// celý `logTail` **808 ms**, a to stejně dlouho pro ocas o 300 i o 25 000 řádcích (rozhoduje
    /// velikost vstupu, ne výřezu).
    @Test("Cena přípravy logu")
    func preparationCost() {
        let text = realLog() ?? log(lines: 25_000)
        print("MĚŘENÍ příprava (\(text.utf8.count) B, \(Policy.logLines(of: text).count) řádků):")
        print("  strippingANSI:       \(ms { _ = Policy.strippingANSI(text) }) ms")
        let noANSI = Policy.strippingANSI(text)
        print("  strippingTimestamps: \(ms { _ = Policy.strippingTimestamps(noANSI) }) ms")
        for lines in [300, 2_000, 25_000] {
            print("  logTail(\(lines)):      \(ms { _ = Policy.logTail(text, lines: lines) }) ms")
        }
    }

    // MARK: - Konec logu: SwiftUI Text proti NSTextView

    /// **Tohle je to měření, které u #292 rozhodlo o stropu na počet řádků.** SwiftUI `Text`
    /// se `.fixedSize()` roste kvadraticky, `NSTextView` sází líně po viewportu:
    ///
    /// | Řádků | SwiftUI `Text` | `NSTextView` |
    /// |---|---|---|
    /// | 300 | 123,77 ms | 2,58 ms |
    /// | 2 000 | 6 392,79 ms | 2,02 ms |
    /// | 6 000 (dnešní mez) | 57 554,33 ms | **5,45 ms** |
    /// | 10 000 | 202 533,12 ms | 14,34 ms |
    ///
    /// Proto konec logu kreslí `LogTailTextView` a `Policy.logTailLines` může být 6 000.
    ///
    /// **`Policy.logTailLines` je v tom výčtu jmenovitě**, ne opsané číslo: cena dnešní mezi je to
    /// jediné, co se z tohohle měření doopravdy používá při rozhodování, jestli se dá zvednout.
    @Test("Cena sazby konce logu")
    func tailRenderingCost() {
        let text = realLog() ?? log(lines: 25_000)
        for lines in [300, 2_000, Policy.logTailLines, 10_000] {
            let tail = Policy.logTail(text, lines: lines)
            let swiftUI = ms {
                let view = Text(verbatim: tail.text)
                    .font(.system(size: CheckDetailView.logFontSize, design: .monospaced))
                    .lineSpacing(CheckDetailView.logLineSpacing)
                    .fixedSize()
                _ = NSHostingView(rootView: AnyView(view)).fittingSize
            }
            let appKit = ms { _ = populatedTailView(tail.text) }
            print("MĚŘENÍ ocas \(lines) řádků (\(tail.text.utf8.count) B): SwiftUI Text \(swiftUI) ms, NSTextView \(appKit) ms")
        }
    }

    // MARK: - Projíždění, ne jen první sazba

    /// **Projíždění je ta cena, na kterou si stěžuje #275** — a u `NSTextView` ji nemá kdo platit:
    /// medián snímku 0,00 ms a nejhorší 0,01 ms i na 8,78 MB, protože TextKit sází jen viewport.
    ///
    /// Pozor na past, do které spadlo #214: `ensureLayout(for:)` + `usedRect(for:)` **vynutí sazbu
    /// celého dokumentu** (2 MB 205 ms, 8,78 MB 876 ms) — a to je jediná věc, kterou aplikace nedělá.
    /// Odtud tehdy vyšel strop o řád nižší, než je potřeba.
    @Test("Cena otevření a projíždění celého logu")
    func scrollingCost() {
        let text = realLog() ?? log(lines: 25_000)
        let tail = Policy.logTail(text, lines: Policy.logTailLines).text
        for (label, content) in [("ocas \(Policy.logTailLines) řádků", tail), ("celý", text)] {
            let (scroll, textView) = tailView()
            let attributed = SelectableCodeView.attributed(content, language: Language(path: "job.log"), colorScheme: .dark)
            let open = ms {
                textView.textStorage?.setAttributedString(attributed)
                scroll.displayIfNeeded()
            }
            var frames: [Double] = []
            for step in 0..<40 {
                let clock = ContinuousClock()
                let elapsed = clock.measure {
                    textView.scrollToVisible(NSRect(x: 0, y: CGFloat(step) * 600, width: 900, height: 600))
                    scroll.contentView.displayIfNeeded()
                    textView.displayIfNeeded()
                }
                frames.append(Double(elapsed.components.attoseconds) / 1e15)
            }
            let sorted = frames.sorted()
            let forced = ms {
                if let container = textView.textContainer, let manager = textView.layoutManager {
                    manager.ensureLayout(for: container)
                    _ = manager.usedRect(for: container)
                }
            }
            print("MĚŘENÍ \(label) (\(content.utf8.count) B): otevření \(open) ms, projíždění medián \(String(format: "%.2f", sorted[sorted.count / 2])) ms / nejhorší \(String(format: "%.2f", sorted.last ?? 0)) ms, vynucená sazba celku \(forced) ms")
        }
    }

    // MARK: - Skok na konec logu

    /// **Od #303 je skok na konec skutečná cena, ne mrtvý kód.** Do té doby se v aplikaci nedělal
    /// vůbec (skákalo se do okýnka, které ještě nemělo výšku, a posun se zahodil), takže se za něj
    /// neplatilo — a taky se nikam neskočilo. Teď se platí při každém rozbalení checku, a je proto
    /// potřeba vědět kolik: `scrollToEndOfDocument` **vynutí sazbu až na konec dokumentu**, tedy tu
    /// jedinou drahou věc, kterou aplikace jinak nedělá.
    @Test("Cena skoku na konec logu")
    func jumpToEndCost() {
        let text = realLog() ?? log(lines: 25_000)
        // **Jen meze, které aplikace doopravdy má** (300 do #292, 2 000 chvíli u #292, dnešních
        // 6 000). Celý log v tom výčtu být nemá: na 25 000 řádcích s dlouhými řádky vynucená sazba
        // testovacího hosta **položila** (změřeno u #303, 595 ms a pak pád), a hlavně je to cesta,
        // kterou se nikdy nejde — ocas je vždycky nejvýš `Policy.logTailLines`.
        for lines in [300, 2_000, Policy.logTailLines] {
            let tail = Policy.logTail(text, lines: lines)
            let scroll = populatedTailView(tail.text)
            guard let textView = scroll.documentView as? NSTextView else { continue }
            let jump = ms {
                textView.scrollToEndOfDocument(nil)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            print("""
                MĚŘENÍ skok na konec, \(lines) řádků (\(tail.text.utf8.count) B): \(jump) ms, \
                origin.y \(String(format: "%.0f", scroll.contentView.bounds.origin.y))
                """)
        }
    }

    // MARK: - Obarvování

    /// Proč log nejde přes obarvování po řádcích: naměřeno **38 ms proti 2,2 ms** na dvoumegovém
    /// logu, tedy 17× za nic — log není kód a `Language(path:)` pro `.log` nic nevrátí.
    ///
    /// **Cesta k souboru je tu to podstatné, ne text.** `job.log` už od #214 chodí jednolitou
    /// cestou, takže srovnávat ho se sebou samým nic neukáže; po řádcích se proto měří tentýž text
    /// pod `job.swift`, kde `Language` jazyk **najde**. Do #292 tady stály dvě jednolité cesty vedle
    /// sebe a měření tvrdilo 0,04 proti 0,02 ms, tedy nic — je to tatáž chyba jako u vynucené sazby
    /// níž: měřit se musí ta cesta, o které je řeč.
    @Test("Obarvování po řádcích proti jednolitému textu")
    func highlightingOverhead() {
        let text = log(lines: 6_000)
        print("MĚŘENÍ 6000 řádků, po řádcích (job.swift): \(ms { _ = SelectableCodeView.attributed(text, language: Language(path: "job.swift"), colorScheme: .dark) }) ms")
        print("MĚŘENÍ 6000 řádků, jednolitě (job.log):    \(ms { _ = SelectableCodeView.attributed(text, language: Language(path: "job.log"), colorScheme: .dark) }) ms")
    }

    // MARK: - Pomůcky

    /// **Okýnko z aplikace, ne jeho kopie** (#303): staví ho `LogTailTextView.makeScrollView()`, tedy
    /// tatáž továrnička, kterou jde `makeNSView`. Do #303 tu stála ruční kopie s komentářem
    /// „nastavené stejně jako `LogTailTextView`“ — druhé místo, kde se to dá nastavit jinak, a měření
    /// by pak popisovalo view, které aplikace nekreslí. Je to tentýž vzor, jakým #214 naměřilo strop
    /// o řád vedle: **měřit se musí ta cesta, kterou kód doopravdy jde.**
    private func tailView() -> (NSScrollView, NSTextView) {
        let scroll = LogTailTextView.makeScrollView()
        // Rozměry z aplikace, ne opsaná čísla: měří se to, na čem se kreslí.
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: CheckDetailView.logMaxHeight)
        guard let textView = scroll.documentView as? NSTextView else { return (scroll, NSTextView()) }
        return (scroll, textView)
    }

    private func populatedTailView(_ text: String) -> NSScrollView {
        let (scroll, textView) = tailView()
        textView.textStorage?.setAttributedString(LogTailTextView.attributed(
            text,
            fontSize: CheckDetailView.logFontSize,
            lineSpacing: CheckDetailView.logLineSpacing,
            color: Palette.ink2
        ))
        scroll.displayIfNeeded()
        return scroll
    }
}
