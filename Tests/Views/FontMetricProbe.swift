import AppKit
import Foundation
import Testing

@testable import PRism

/// **Co se s metrikou písma děje v testovacím hostu pod zátěží** (#407).
///
/// Nic netvrdí — čte metriku pořád dokola z několika vláken, vypisuje histogram hodnot a u každé
/// nekladné hodnoty **úplný rozbor** toho písma: jméno, velikost, počet glyfů, ascender, descender,
/// obalový rámec, a jestli pomůže druhé čtení téhož objektu nebo čerstvé písmo. To je ta otázka, na
/// kterou se z pádu tvrzení odpovědět nedá: `pod sebou: 0, vedle sebe: 0` řekne, že šířka znaku byla
/// nula, ale ne co bylo nula uvnitř.
///
/// **Co tahle sonda u #407 dokázala, je negativní výsledek — a je to polovina odpovědi.** Za 45 s
/// plného běhu udělala **3 242 670** čtení šesti cest ze šesti vláken a nenašla **ani jednu**
/// anomálii; v samostatném procesu nenašel milion čtení proti churnu ve font cache pod load 22 taky
/// nic. **Čtení teplého písma to tedy není** a hammerováním se ta vada chytit nedá — je to rozřešení
/// **konkrétního objektu** písma, a těch je za běh hrstka. Zachytila ji až náhradní cesta ve
/// `FontMetric`, viz hlavička toho souboru.
///
/// Sonda proto zůstává na to, na co byla dobrá: **vyloučit**, že se metrika rozchází při čtení. Běží
/// souběžně se zbytkem běhu (Swift Testing pouští suity paralelně), takže je to čtení v tom procesu,
/// o kterém je řeč.
///
/// **Sázet text tady smí, i když ve `FontMetric` ne** (a je to schválně): u #407 byl zrovna pád
/// v sazbě to, co ukázalo příčinu. Když sonda spadne uvnitř CoreTextu, **je to nález**, ne chyba
/// sondy — pouští se ručně, takže nemá co položit.
///
/// Pouští se ručně:
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/fontprobe \
///     xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
///     > /tmp/tests.log 2>&1
/// ```
@Suite(
    "Metrika písma pod zátěží (#407)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct FontMetricProbe {
    /// Jak dlouho se čte. Plný běh je delší, takže sonda pokrývá jeho začátek — a právě tam se
    /// zakládá to, co si pak `FontMetric` pamatuje na celý proces.
    private var seconds: Double {
        Double(ProcessInfo.processInfo.environment["PRISM_FONT_PROBE_SECONDS"] ?? "") ?? 45
    }

    private var readers: Int {
        Int(ProcessInfo.processInfo.environment["PRISM_FONT_PROBE_READERS"] ?? "") ?? 6
    }

    @Test("Čte metriku pořád dokola a hlásí každou nekladnou hodnotu")
    func hammersTheFontMetric() throws {
        let collector = Collector()
        let deadline = Date().addingTimeInterval(seconds)
        let group = DispatchGroup()

        for index in 0..<readers {
            group.enter()
            let thread = Thread {
                while Date() < deadline {
                    Self.readEverything(into: collector, reader: index)
                }
                group.leave()
            }
            thread.name = "font-probe-\(index)"
            thread.start()
        }
        group.wait()

        let report = collector.report(seconds: seconds, readers: readers)
        print(report)
        try write(report)
    }

    /// Čtyři cesty, kterými se metrika v repu bere — každá tak, jak ji bere produkční kód.
    private static func readEverything(into collector: Collector, reader: Int) {
        let mono = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        collector.record("mono.maximumAdvancement", mono.maximumAdvancement.width, font: mono, reader: reader)
        collector.record(
            "mono.attributedSize",
            NSAttributedString(string: "0", attributes: [.font: mono]).size().width,
            font: mono,
            reader: reader
        )

        let log = LogTailTextView.font(size: CheckDetailView.logFontSize)
        collector.record(
            "log.defaultLineHeight",
            NSLayoutManager().defaultLineHeight(for: log),
            font: log,
            reader: reader
        )
        collector.record(
            "log.height(3)",
            LogTailTextView.height(
                forLines: 3,
                fontSize: CheckDetailView.logFontSize,
                lineSpacing: CheckDetailView.logLineSpacing,
                limit: CheckDetailView.logMaxHeight
            ),
            font: log,
            reader: reader
        )

        let pill = DesignPill.font
        collector.record(
            "pill.defaultLineHeight",
            NSLayoutManager().defaultLineHeight(for: pill),
            font: pill,
            reader: reader
        )
        collector.record("pill.TextWidth", TextWidth.pill("otevřený"), font: pill, reader: reader)

        // A tatáž čísla přes sdílené měřidlo — kdyby se rozešla se surovým čtením, je to vidět
        // vedle sebe v jednom výpisu.
        collector.record("FontMetric.characterWidth", FontMetric.shared.characterWidth(of: mono), font: mono, reader: reader)
        collector.record("FontMetric.lineHeight", FontMetric.shared.lineHeight(of: log), font: log, reader: reader)
    }

    private func write(_ report: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let root = URL(filePath: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "font-metric-probe.txt")
        let stamped = "=== \(Date()) pid \(ProcessInfo.processInfo.processIdentifier)\n\(report)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(stamped.utf8))
            try handle.close()
        } else {
            try Data(stamped.utf8).write(to: file)
        }
    }

    /// Sbírá histogram a rozbory. `@unchecked Sendable` se zámkem, protože čte několik vláken.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var histogram: [String: [Double: Int]] = [:]
        private var anomalies: [String] = []
        private let start = Date()

        func record(_ name: String, _ value: Double, font: NSFont, reader: Int) {
            lock.lock()
            histogram[name, default: [:]][value, default: 0] += 1
            lock.unlock()
            guard value <= 0 else { return }
            let dump = """
                ANOMÁLIE \(name)=\(value) v \(String(format: "%.1f", Date().timeIntervalSince(start))) s \
                (čtenář \(reader)): jméno=\(font.fontName) velikost=\(font.pointSize) \
                glyfů=\(font.numberOfGlyphs) ascender=\(font.ascender) descender=\(font.descender) \
                leading=\(font.leading) rámec=\(font.boundingRectForFont) \
                advance=\(font.maximumAdvancement.width) \
                řádek=\(NSLayoutManager().defaultLineHeight(for: font)) \
                znovu=\(NSAttributedString(string: "0", attributes: [.font: font]).size()) \
                čerstvé=\(NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular).maximumAdvancement.width)
                """
            lock.lock()
            anomalies.append(dump)
            lock.unlock()
        }

        func report(seconds: Double, readers: Int) -> String {
            lock.lock()
            defer { lock.unlock() }
            var lines = ["čteno \(seconds) s z \(readers) vláken"]
            for (name, values) in histogram.sorted(by: { $0.key < $1.key }) {
                let text = values.sorted { $0.key < $1.key }
                    .map { "\(String(format: "%.4f", $0.key))×\($0.value)" }
                    .joined(separator: " ")
                lines.append("\(name): \(text)")
            }
            lines.append("sdílené měřidlo: \(FontMetric.shared.tally)")
            lines.append("anomálií: \(anomalies.count)")
            lines.append(contentsOf: anomalies.prefix(20))
            return lines.joined(separator: "\n")
        }
    }
}
