import AppKit
import SwiftUI

/// Přepis surové session jako **řádky s rolemi** (#327).
///
/// Existuje proto, aby vysázený text a zkopírovaný text byly **jedna pravda**. Sheet potřebuje
/// obojí — `NSAttributedString` do `NSTextView`u a čistý `String` pod `Zkopírovat přepis` —, a dvě
/// samostatná skládání téhož by se rozešla první úpravou hlavičky události; je to tatáž úvaha jako
/// u sady labelů, kterou skládá `Policy`, ne publisher (#392).
///
/// **Role, ne barvy.** V řádku stojí, čím ten kus textu je; barvu z toho udělá `attributed(_:)`.
/// Díky tomu se dá otestovat, **co** se kreslí, bez toho, aby test kreslil.
enum RawSessionScript {
    /// Čím je kus textu v přepisu.
    enum Role: Hashable, Sendable {
        case time
        /// Druh události. Barva je ta, kterou ten druh nese jinde v okně — ne nová škála.
        case kind
        /// Próza a `ReportFindings` — akcent, protože to je výstup, ne krok.
        case kindAccent
        /// `thinking` a systémové události — tišší než zbytek.
        case kindDim
        case subject
        /// Štítek `ODMÍTNUTO`.
        case denied
        case body
        /// Ořez uvnitř události, na místě, kde nastal.
        case cut
        /// Řez na začátku textu — co se do okna nevešlo.
        case topCut
    }

    struct Run: Equatable, Sendable {
        let text: String
        let role: Role
    }

    /// Jeden řádek přepisu. `indented` = tělo události, tedy odsazené pod hlavičku.
    ///
    /// Tělo je **jeden řádek s vnitřními zlomy**, ne řádek na každý zlom, a je to schválně: tělo umí
    /// mít po ořezu 8 kB, takže rozpad na tisíce položek by byl tisíc alokací na událost. Odsazení
    /// za to nic neplatí — v `NSParagraphStyle` je `headIndent` vlastnost **odstavce**, takže se
    /// uplatní na každý zlom uvnitř.
    struct Line: Equatable, Sendable {
        let runs: [Run]
        let indented: Bool
    }

    /// Řádky celého přepisu, v pořadí, v jakém se kreslí.
    nonisolated static func lines(of transcript: RawTranscript) -> [Line] {
        var lines: [Line] = []
        if let cut = RawSessionText.topCut(transcript) {
            lines.append(Line(runs: [Run(text: "— \(cut) —", role: .topCut)], indented: false))
        }
        for event in transcript.events {
            lines.append(header(of: event))
            if let body = event.body, !body.isEmpty {
                lines.append(Line(runs: [Run(text: body, role: .body)], indented: true))
            }
            if let cut = event.bodyCut {
                lines.append(Line(runs: [Run(text: cut, role: .cut)], indented: true))
            }
        }
        return lines
    }

    /// Hlavička události — jediné, co je v přepisu vysázené.
    private nonisolated static func header(of event: TranscriptEvent) -> Line {
        var runs = [Run(text: time(of: event), role: .time)]
        runs.append(Run(text: RawSessionText.kind(event.kind), role: role(of: event.kind)))
        if let subject = RawSessionText.subject(of: event), !subject.isEmpty {
            runs.append(Run(text: subject.singleLine, role: .subject))
        }
        if event.isDenied {
            runs.append(Run(text: RawSessionText.denied, role: .denied))
        }
        return Line(runs: runs, indented: false)
    }

    /// Čas v hlavičce. Událost bez časové značky dostane **prázdno o téže šířce**, ne domyšlený čas:
    /// sloupec se tím nerozjede a nic se netvrdí.
    private nonisolated static func time(of event: TranscriptEvent) -> String {
        guard let at = event.at else { return "        " }
        return at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }

    private nonisolated static func role(of kind: TranscriptEvent.Kind) -> Role {
        switch kind {
        case .prose, .report: .kindAccent
        case .thinking, .system, .image: .kindDim
        case .prompt, .input, .tool, .result, .unreadable: .kind
        }
    }

    // MARK: - Čistý text

    /// Mezera mezi kusy hlavičky (`gap: 9px` u `.rawtx .ev` v návrhu, v mono písmu dvě mezery).
    ///
    /// **Jedna konstanta pro kresbu i pro kopii, a je to chyba, kterou chytil až render**: první
    /// podoba ji měla jen v `plain(_:)`, takže vysázená hlavička slepila čas, druh i detail do
    /// `23:13:36Bashgh pr view 412`. Dvě různá skládání téhož jsou přesně to, čemu se tenhle typ
    /// vyhýbá.
    nonisolated static let gap = "  "

    /// Přepis k zkopírování.
    ///
    /// **Tělo se v kopii neodsazuje**, a je to vědomé: odsazení je věc kresby a v editoru nebo
    /// v komentáři na PR by z něj byl mezerový šum před každým řádkem výstupu. Hlavička události
    /// události od sebe odděluje i bez něj.
    nonisolated static func plain(_ lines: [Line]) -> String {
        lines
            .map { line in line.runs.map(\.text).joined(separator: gap) }
            .joined(separator: "\n")
    }

    // MARK: - Sazba

    /// Velikost písma přepisu — `font-size: 10.5px` u `.rawtx` v návrhu.
    nonisolated static let fontSize: CGFloat = 10.5
    /// Prokládání do `line-height: 1.6`: řádek mono písma o 10,5 bodu má 13 bodů, cíl je 16,8.
    nonisolated static let lineSpacing: CGFloat = 3.8
    /// Odsazení těla pod hlavičku — `padding-left: 33px` proti `12px` u hlavičky, tedy 21 bodů.
    nonisolated static let bodyIndent: CGFloat = 21

    /// Vysázený přepis. **Barva se nasazuje u každého kusu** (#393): `NSAttributedString` bez
    /// `.foregroundColor` se v AppKitu kreslí **černě**, ne „dědí z okolí“ — takže by v tmavém
    /// režimu byl přepis černý na tmavém.
    nonisolated static func attributed(_ lines: [Line]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: attributes(of: .body, in: line)))
            }
            for (position, run) in line.runs.enumerated() {
                if position > 0 {
                    result.append(NSAttributedString(string: gap, attributes: attributes(of: run.role, in: line)))
                }
                result.append(NSAttributedString(string: run.text, attributes: attributes(of: run.role, in: line)))
            }
        }
        return result
    }

    private nonisolated static func attributes(
        of role: Role,
        in line: Line
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font(of: role),
            .foregroundColor: NSColor(color(of: role)),
            .paragraphStyle: paragraph(indented: line.indented),
        ]
    }

    private nonisolated static func font(of role: Role) -> NSFont {
        switch role {
        case .kind, .kindAccent:
            return .monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        case .kindDim:
            return .monospacedSystemFont(ofSize: fontSize, weight: .medium)
        case .denied:
            return .monospacedSystemFont(ofSize: fontSize - 1, weight: .bold)
        case .time, .subject, .body, .cut, .topCut:
            return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    private nonisolated static func color(of role: Role) -> Color {
        switch role {
        case .time: Palette.ink3
        case .kind: Palette.ink
        case .kindAccent: Palette.accent
        case .kindDim: Palette.ink3
        case .subject: Palette.ink2
        case .denied: Palette.crit
        case .body: Palette.ink2
        case .cut, .topCut: Palette.stale
        }
    }

    /// Odstavec. Odsazení těla je `headIndent` **i** `firstLineHeadIndent`, takže se uplatní na
    /// každý zlom uvnitř těla i na jeho zalomené pokračování.
    private nonisolated static func paragraph(indented: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        if indented {
            style.headIndent = bodyIndent
            style.firstLineHeadIndent = bodyIndent
        }
        return style
    }
}
