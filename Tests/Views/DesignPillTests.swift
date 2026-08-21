import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Kapsle stavu z návrhu (#348) — **mono 10,5, odsazení 7 a 2, a na jednom místě**.
///
/// Vzniklo z odchylky, kterou našlo srovnání okna s mockupem u #299: chip v hlavičce karty popisu
/// byl `11 bez mono`, kdežto návrh má na tom místě `.pill idle`. Není to kosmetika — mono v tomhle
/// okně nese **stavy a počty** a UI font **labely z repozitáře** (`.lchip`), takže nemono chip
/// vypadal jako jiný druh prvku, než čím je.
///
/// Tři třídy tvrzení:
///
/// - **že je to mono**: šířka dvou stejně dlouhých, ale různě širokých slov musí vyjít stejně;
/// - **jaká je metrika**: rozměr kapsle proti sazbě z návrhu, včetně toho, že mono 10,5 je
///   o bod **nižší** než dosavadní systémových 11 — hlavička karty tedy nemůže povyrůst;
/// - **že má jedno místo**: metrika byla v sedmi kopiích a jedna z nich se rozešla. Tvrdí se to
///   nad **zdrojáky**, jako v `GlobalAppearanceTests` — za běhu se „kolikrát je to zapsané“ zjistit
///   nedá.
///
/// Co tady **není**: že se hlavička v úzkém tabu nerozsype. Na to je `OverviewWidthTests`, které
/// měří přetečení v pásmu 128–1180 bodů — mono je o 4 až 9,4 bodu širší (naměřeno na čtyřech
/// stavech PR), takže právě tam se to musí projevit, kdyby se to nevešlo.
@Suite("Kapsle stavu z návrhu (#348)")
struct DesignPillTests {
    private static let stateLabels = PullRequestState.allCases.map(\.czechLabel)

    /// Výška řádku kapsle a té před #348 — **přečtená jednou za test** (#367). Metrika písma je
    /// stav procesu, takže se v jednom testu nesmí čítat dvakrát: pod paralelním během se dvě
    /// čtení umí vyřešit jinak a spadne z toho tvrzení, které nad aplikací platí
    /// (`CommitPanelRoomTests`, `LogTailHeightTests`).
    private let pillLine = NSLayoutManager().defaultLineHeight(for: DesignPill.font)
    private let previousLine = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 11))

    // MARK: - Že je to mono

    /// Mono se pozná tím, že **různě široké glyfy mají stejnou šířku** (naměřeno: `iii` i `WWW`
    /// 19,472). `TextWidth.pill(_:)` bere řez z `DesignPill.font` a od #406 se týmž řezem i kreslí
    /// (`Font(_:)`), takže tohle tvrzení mluví o tom, čím se kapsle doopravdy sází.
    @Test("Kapsle se sází mono řezem")
    func typesetsThePillWithAMonospacedFace() {
        #expect(TextWidth.pill("iii") == TextWidth.pill("WWW"))
        // A měřidlo to umí poznat: v UI fontu o téže velikosti se ta dvě slova liší.
        let ui = NSFont.systemFont(ofSize: DesignPill.fontSize)
        #expect(TextWidth.of("iii", font: ui) != TextWidth.of("WWW", font: ui))
    }

    // MARK: - Jaká je metrika

    /// Nakreslená kapsle má rozměr ze sazby — tedy **text plus 2 × 7 na šířku a 2 × 2 na výšku**.
    ///
    /// Měří se `fittingSize` hostované kapsle, ne konstanty v testu: kdyby `designPill` nasadilo
    /// jiný řez nebo jiné odsazení, tohle je to jediné, co si toho všimne.
    @MainActor
    @Test("Kapsle má rozměr z návrhu")
    func drawsThePillWithTheDesignMetric() throws {
        for label in Self.stateLabels {
            let size = fittingSize(of: label)
            let text = TextWidth.of(label, font: DesignPill.font)

            #expect(abs(size.width - (text + 2 * DesignPill.horizontalPadding)) <= 1, "„\(label)“: šířka \(size.width)")
            #expect(abs(size.height - (pillLine + 2 * DesignPill.verticalPadding)) <= 1, "„\(label)“: výška \(size.height)")
        }
    }

    /// **Kapsle nesmí povyrůst.** Hlavička karty popisu má dvě podoby podle šířky (#291) a je to
    /// jeden řádek, takže vyšší kapsle by ho roztlačila. Mono 10,5 má řádek **12 bodů** proti 13
    /// u systémových 11 — kapsle je tedy o bod **nižší**, ne vyšší; naměřeno, ne odvozeno.
    @MainActor
    @Test("Kapsle není vyšší než ta před #348")
    func staysNoTallerThanBefore() {
        let before = previousLine + 4
        for label in Self.stateLabels {
            #expect(fittingSize(of: label).height <= before, "„\(label)“ je vyšší než dosavadní kapsle")
        }
    }

    /// Cena mono je **šířka**, a je ohraničená: nejdelší stav (`rozpracovaný`) roste o 9,4 bodu.
    /// Je to zapsané měření — kdyby se sazba omylem zvedla na 12 nebo 13, tohle spadne dřív, než
    /// se začne hledat v přetečení hlavičky.
    @MainActor
    @Test("Mono nestojí víc než deset bodů na šířku")
    func keepsTheCostOfMonoBounded() {
        for label in Self.stateLabels {
            let before = TextWidth.of(label, font: .systemFont(ofSize: 11)) + 12
            let after = TextWidth.pill(label)
            #expect(after > before, "„\(label)“: mono má být širší, jinak měřidlo měří jeden font dvakrát")
            #expect(after - before <= 10, "„\(label)“: kapsle vyrostla o \(after - before)")
        }
    }

    // MARK: - Že má jedno místo

    /// Hlavička karty popisu kreslí **tu kapsli z návrhu**, ne vlastní sazbu. Je to celé zadání
    /// #348 a za běhu se to nezměří: barvy chipu (`raised` na `chrome`) jsou od sebe devět
    /// dvěstěpětapadesátin, takže by se v bitmapě nedaly rozlišit.
    @Test("Hlavička karty popisu bere kapsli z jednoho místa")
    func drawsTheHeaderPillFromTheSharedMetric() throws {
        let overview = try source(at: "App/Views/OverviewView.swift")

        #expect(overview.contains("designPill(tint: Palette.ink2, background: Palette.raised)"))
        // A stará sazba je pryč — `11 bez mono` byla přesně ta odchylka, kterou #348 opravuje.
        #expect(!overview.contains(".font(.system(size: 11))"))
    }

    /// **Metrika je zapsaná jednou.** Do #348 stálo `size: 10.5, weight: .semibold, design:
    /// .monospaced` na sedmi místech — šest z nich shodně a sedmé (hlavička karty) jinak. Rozejít
    /// se může jedině to, co je zapsané víckrát, takže guard hlídá počet zápisů, ne jejich obsah.
    ///
    /// **Hlídají se obě podoby zápisu**, a je to nález Copilota na #406: první verze znala jen
    /// SwiftUI `size: 10.5, weight: .semibold` a minula tu AppKitovou
    /// (`monospacedSystemFont(ofSize: 10.5, weight: .semibold)`) — tedy zrovna tu, kterou
    /// `SinceLastVisitView` do #348 doopravdy mělo. Guard, který nechytá jednu ze dvou forem, co se
    /// v repu vyskytly, hlídá něco jiného, než co o sobě tvrdí.
    ///
    /// Čte se **`DesignPill.fontSize`**, ne zapsaná desetina: kdyby se velikost změnila, má guard
    /// hlídat tu novou. Ověřeno vložením regrese v obou podobách.
    @Test("Sazbu kapsle nikdo nepíše mimo DesignPill")
    func keepsTheTypesettingInOnePlace() throws {
        let spellings = [
            "size: \(DesignPill.fontSize), weight: .semibold",
            "ofSize: \(DesignPill.fontSize), weight: .semibold",
        ]
        let offenders = try appSources()
            .filter { $0.path != "App/Views/DesignPill.swift" }
            .filter { source in spellings.contains { source.code.contains($0) } }
            .map(\.path)

        #expect(offenders.isEmpty, "vlastní sazba kapsle: \(offenders.joined(separator: ", "))")
    }

    // MARK: - Měřidlo

    @MainActor
    private func fittingSize(of label: String) -> CGSize {
        let pill = Text(verbatim: label).designPill(tint: Palette.ink2, background: Palette.raised)
        return NSHostingView(rootView: pill).fittingSize
    }

    private struct Source {
        let path: String
        /// Jen kód — řádkové komentáře jsou pryč, protože o sazbě kapsle se v nich mluví.
        let code: String
    }

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(at path: String) throws -> String {
        try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
    }

    /// Zdrojáky aplikace bez řádkových komentářů — tatáž konstrukce jako v `GlobalAppearanceTests`.
    private func appSources() throws -> [Source] {
        let root = Self.repository.appending(path: "App")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append(Source(path: "App/" + url.path.replacingOccurrences(of: root.path + "/", with: ""), code: code))
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }
}
