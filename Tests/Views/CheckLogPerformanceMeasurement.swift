import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Měření, ne test (#214) — kolik stojí ukázat log jobu. Nic netvrdí, vypisuje čísla.
///
/// Existuje proto, že zadání #214 chtělo strop na velikost logu **změřit, ne odhadnout** (viz #275
/// o ceně sazby textu). Časy se nehlídají `#expect`em: na jiném stroji vyjdou jinak a byl by z toho
/// test, který padá bez chyby v kódu. **Pouští se ručně:** `PRISM_MEASURE=1`.
///
/// Log je **syntetický, ale podle skutečného**. Tvar je změřený na `keboola/job-queue-daemon`,
/// job `93844012547` — největší log na našich repech: 8,78 MB, 25 533 řádků, nejdelší řádek 2 258
/// znaků, 272 řádků nad tisíc znaků, timestamp na 25 528 z nich. Dvoumegový soubor se do repa
/// nepřikládá (fixtures jsou skutečné výstupy, ale ne takhle velké), takže se generuje na míru — co
/// se z něj bere, jsou právě ty rozměry.
@Suite(
    "Měření ceny logu (#214)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
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

    private func ms(_ body: () -> Void) -> String {
        let clock = ContinuousClock()
        return "\(clock.measure { body() }.milliseconds)"
    }

    /// **Tohle je to měření, o které jde**: unese `NSTextView` dvoumegový log?
    ///
    /// Naměřeno u #214 (na skutečném logu, ne na tomhle syntetickém): dvoumegový ocas
    /// (5 843 řádků) se nasází za **220 ms**, celých 8,78 MB (25 534 řádků) za **850 ms**. Strop
    /// 2 MB tedy má rezervu a zůstal — 220 ms je jednorázová cena při otevření sheetu.
    @Test("Cena sazby logu podle velikosti")
    func layoutCost() {
        for lines in [1_000, 6_000, 25_000] {
            let text = log(lines: lines)
            print("MĚŘENÍ log \(lines) řádků (\(text.utf8.count) B):")
            print("  příprava (ANSI + timestampy + ocas): \(ms { _ = Policy.logTail(text) }) ms")
            print("  attributed po řádcích (obarvení):    \(ms { _ = SelectableCodeView.attributed(text, path: "job.log", colorScheme: .dark) }) ms")
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let plain = NSAttributedString(string: text, attributes: [.font: font])
            print("  attributed jednolitý:                \(ms { _ = NSAttributedString(string: text, attributes: [.font: font]) }) ms")
            print("  layout v NSTextView (šířka 900):     \(ms { layout(plain, width: 900) }) ms")
        }
    }

    /// Proč log nejde přes obarvování po řádcích: naměřeno **38 ms proti 2,2 ms** na dvoumegovém
    /// logu, tedy 17× za nic — log není kód a `Language(path:)` pro `.log` nic nevrátí.
    @Test("Obarvování po řádcích proti jednolitému textu")
    func highlightingOverhead() {
        let text = log(lines: 6_000)
        print("MĚŘENÍ 6000 řádků, po řádcích: \(ms { _ = SelectableCodeView.attributed(text, path: "job.log", colorScheme: .dark) }) ms")
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        print("MĚŘENÍ 6000 řádků, jednolitě:  \(ms { _ = NSAttributedString(string: text, attributes: [.font: font]) }) ms")
    }

    /// Sází se do view nastaveného stejně jako `SelectableCodeView`: zalamování,
    /// `widthTracksTextView`, žádný vodorovný scroll. U dvoutisícznakových řádků je zalamování
    /// to drahé, ne počet řádků.
    private func layout(_ text: NSAttributedString, width: CGFloat) {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(text)
        // Vynutí sazbu celého textu — bez toho se změří jen vytvoření storage.
        if let container = textView.textContainer, let manager = textView.layoutManager {
            manager.ensureLayout(for: container)
            _ = manager.usedRect(for: container)
        }
    }
}
