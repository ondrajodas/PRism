import SwiftUI

/// Blok `brief` nad pruhy desky (#516) — až tři **pojmenované** věty o stavu aplikace a řádek pod
/// nimi.
///
/// **Rozhoduje `Policy.briefBlock`, tady se kreslí.** Jestli se blok kreslí vůbec, co v něm stojí
/// a co je na tlačítku, vydá `Policy`; view z toho nesmí nic dopočítávat — právě tady by se dalo
/// nejsnáz napsat něco, co data neunesou.
///
/// Rozměry jsou z návrhu (`.rv-brief`, sekce 58) doslova: rámeček s akcentovým pruhem vlevo,
/// věty 13 b se sloupcem návěští 11 b vlevo a pod nimi řádek monem 10,5 b.
struct BriefBlockView: View {
    let block: BriefBlock
    /// Co má tlačítko udělat. Jedna akce na všechny tři podoby (`Shrň`, `Shrň znovu`,
    /// `Zkusit znovu`) — je to pořád totéž spuštění, jen popisek se liší podle stavu.
    let write: () -> Void
    /// Otevřít záložku pull requestu, na jehož číslo se ve větě kliklo (#516).
    ///
    /// **Je to `AppStore.openPullRequest`, tedy tatáž cesta jako `prism://`, `Odkaz` v paletě ⌘K
    /// a klik ve frontě** — druhá cesta k otevření záložky by se s tou první rozešla přesně
    /// v tom, co je na ní jediné zajímavé: co se stane s PR, který ve zdrojích není.
    let open: (PRIdentifier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            body(of: block.body)
            meta
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1) }
        // Akcentový pruh vlevo z návrhu. `clipShape` na rámu bloku, aby pruh sledoval zaoblení.
        .overlay(alignment: .leading) { Rectangle().fill(Palette.accent).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 12))
        // **Odkaz ve větě je odkaz, ne tlačítko** — proto `.link` v textu a odchycení tady.
        // Adresa je ta na GitHubu (`Policy.githubURL`), takže ji zvládne i `⌘C` z kontextové
        // nabídky; rozebírá se **toutéž funkcí jako vložený odkaz v paletě** (#531), aby se ty dvě
        // místa nemohla rozejít. Co se rozebrat nedá, se nepolyká: jde systému, ne do prázdna.
        .environment(\.openURL, OpenURLAction { url in
            guard let pullRequest = Policy.linkedPullRequest(in: url.absoluteString) else {
                return .systemAction
            }
            open(pullRequest)
            return .handled
        })
    }

    @ViewBuilder private func body(of body: BriefBlock.Body) -> some View {
        switch body {
        case .text(let brief):
            lines(of: brief)
        case .never(let text):
            sentence(text, color: Palette.ink2)
        case .running(let text):
            HStack(spacing: 8) {
                // Týž prstýnek jako na záložce s běžícím review — jeden tvar pro „pracuje se“
                // (návrh, sekce 44). Nekonečná animace patří na `CALayer`, ne do SwiftUI (#350).
                SpinningRing()
                sentence(text, color: Palette.ink2)
            }
        case .failed(let headline, let detail):
            VStack(alignment: .leading, spacing: 4) {
                sentence(headline, color: Palette.ink)
                // **Důvod je vidět**, ne jen „nepovedlo se“: bez něj je blok prázdno s rámečkem,
                // což je přesně to, čemu se tenhle stav vyhýbá.
                sentence(detail, color: Palette.ink2)
            }
        }
    }

    /// Šířka sloupce s návěštím. **Konstanta, ne měření**: jsou to tři pevné popisky
    /// (`BriefPart.title`), takže se nemá co měnit — a pružný sloupec by právě tady srovnání vět
    /// pod sebou rozbil, což je celý smysl rozdělení.
    ///
    /// Nejdelší z nich je `První na řadě`; 88 bodů ho při 11 b pojme i s rezervou na širší písmo.
    private static let labelWidth: CGFloat = 88

    /// Tři pojmenované věty pod sebou (#516) — **ne odstavec**.
    ///
    /// Blok kreslí **jen ty řádky, které dorazily**: otázka, na kterou ve vstupu odpověď nebyla, se
    /// vynechává už v odpovědi session (`BriefCommand.parse`), a prázdné návěští by tvrdilo, že se
    /// o ní nedá nic říct — což je jiné tvrzení než „nikdo se neptal“.
    ///
    /// **Návěští je sloupec, ne lead-in ve větě.** Vlevo zarovnané popisky se dají přelétnout okem
    /// a vybrat si z nich jeden; tučný začátek uvnitř odstavce by se pořád četl jako próza, tedy
    /// jako to, co se tímhle ruší.
    private func lines(of brief: Brief) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(brief.lines, id: \.part) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: line.part.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    sentence(of: line, mentioning: brief.mentioned)
                }
            }
        }
    }

    /// Jedna věta briefu — **text s klikatelnými čísly** (#516).
    ///
    /// Rozdělení na text a odkazy vydá `Policy.briefSpans`; tady se z něj skládá `AttributedString`,
    /// aby číslo zůstalo **uvnitř věty** a věta se lámala jako dřív. Tlačítko na konci řádku by
    /// znamenalo jeden odkaz na větu a další prvek v bloku, který má být levnější na přečtení než
    /// čtyři bloky pod ním.
    private func sentence(of line: BriefLine, mentioning mentioned: [PRIdentifier]) -> some View {
        Text(attributed(line.text, mentioning: mentioned))
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Věta složená z kusů, které vydala `Policy`. **View nerozhoduje, co je odkaz** — jen kreslí:
    /// akcentová barva a adresa, na kterou se klikne.
    private func attributed(_ text: String, mentioning mentioned: [PRIdentifier]) -> AttributedString {
        var result = AttributedString()
        for span in Policy.briefSpans(of: text, mentioning: mentioned) {
            switch span {
            case .text(let plain):
                result += AttributedString(plain)
            case .link(let label, let target):
                var run = AttributedString(label)
                run.link = Policy.githubURL(of: target)
                run.foregroundColor = Palette.accent
                result += run
            }
        }
        return result
    }

    private func sentence(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Řádek pod textem — razítko s cenou vlevo, tlačítko vpravo.
    ///
    /// **Razítko má jedině hotový brief.** U běžícího a spadlého by `shrnuto —` tvrdilo, že něco
    /// shrnuto je; věta o tom, co se děje, stojí nad ním.
    private var meta: some View {
        HStack(spacing: 10) {
            if case .text(let brief) = block.body {
                Text(verbatim: Policy.briefMeta(
                    at: brief.writtenAt.formatted(date: .omitted, time: .shortened),
                    // **`nil` cena není nula** — formátuje se jedině to, co dorazilo
                    // (`RunUsageText.cost`, tedy totéž místo jako u útraty za den).
                    cost: brief.cost.map(RunUsageText.cost)
                ))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let action = block.action {
                Button(action) { write() }
                    .buttonStyle(.mini)
                    .help("Složí až tři věty o tom, co je zrovna na desce — co přibylo, co hoří a co si vzít první. Je to session Claude Code bez jediného nástroje: čte stav aplikace, ne kód. Stojí kolem 0,09 $ a počítá se do dnešní útraty.")
            }
        }
    }
}
