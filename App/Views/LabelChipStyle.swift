import AppKit
import SwiftUI

/// Sazba chipu labelu v pravém panelu (#392) — a **rozměry, ze kterých se počítá zalomení**.
///
/// Metriky a kresba bydlí spolu schválně: pravidlo #236 říká, že kdo si říká o velikost, musí ji
/// měřit na tom, na čem kreslí. Dvě místa (jedno pro `Policy`, jedno pro `body`) znamenají dvě
/// pravdy o jedné šířce — a rozejdou se při prvním doladění odsazení.
///
/// Čísla jsou z návrhu doslova (`docs/navrh.html`, `.lchip`, `.lchip.more`, `.chip-add`):
/// 10,5 bodu, odsazení 2/7, obtažení 1, puntík 8, mezera 5.
enum LabelChipStyle {
    static let fontSize = 10.5
    /// `padding: 2px 7px`.
    static let insetHorizontal = 7.0
    static let insetVertical = 2.0
    /// `border: 1px solid`. **Počítá se do šířky** (`box-sizing: border-box`) — bez toho chip
    /// o okraj a odsazení přeroste, což je změřená past ze zákresu: 230 bodů v řádku širokém 214,
    /// tedy 3 body za pravým okrajem panelu.
    static let borderWidth = 1.0
    /// Puntík s barvou labelu.
    static let dotSize = 8.0
    /// `gap: 5px` uvnitř chipu i mezi chipy.
    static let spacing = 5.0
    static let cornerRadius = 20.0

    /// **Funkce, ne konstanty**: `NSFont` není `Sendable`, takže statická konstanta z něj je
    /// v Swiftu 6 chyba souběhu. Tentýž tvar jako `MiniButtonStyle.labelFont(of:)`.
    nonisolated static func nameFont() -> NSFont {
        NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    }

    /// `+N` je mono, jako všechny počty v okně.
    nonisolated static func countFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// `+ label` je mediumem, ne semiboldem — je to akce, ne štítek.
    nonisolated static func actionFont() -> NSFont {
        NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }

    /// Šířka chipu s puntíkem a jménem, **i s odsazením a obtažením**.
    nonisolated static func chipWidth(_ label: PullRequestLabel) -> Double {
        TextWidth.of(label.name, font: nameFont()) + dotSize + spacing + frameWidth
    }

    /// Šířka odznaku `+N`. Bez puntíku — není to label, je to počet.
    nonisolated static func moreWidth(_ count: Int) -> Double {
        TextWidth.of("+\(count)", font: countFont()) + frameWidth
    }

    /// Šířka akčního chipu. Bez puntíku, jako `+N`.
    nonisolated static func actionWidth(_ title: String) -> Double {
        TextWidth.of(title, font: actionFont()) + frameWidth
    }

    /// Co si chip vezme mimo text — odsazení z obou stran a obě obtažení.
    ///
    /// **Obtažení se počítá**, protože v CSS leží **venku za odsazením**: v `.lchip` je text osm
    /// bodů od vnější hrany (1 rám + 7 odsazení), ne sedm. V SwiftUI `overlay` rámeček frame
    /// nezvětšuje, takže se ten jeden bod přidává k odsazení — jinak by chip vyšel o dva body užší
    /// než v zákresu a rozměry z návrhu by se přestaly brát 1 : 1. Hlídá to test, který porovnává
    /// spočítanou šířku s nakreslenou.
    nonisolated static var textInset: Double { insetHorizontal + borderWidth }

    nonisolated private static var frameWidth: Double { 2 * textInset }

    /// Metriky pro `Policy.labelChips`. Jedno místo, ze kterého se berou.
    nonisolated static func metrics(addTitle: String) -> Policy.LabelChipMetrics {
        Policy.LabelChipMetrics(
            spacing: spacing,
            chipWidth: chipWidth,
            moreWidth: moreWidth,
            addWidth: actionWidth(addTitle)
        )
    }
}

/// Chip jednoho labelu: puntík s barvou z repozitáře a jméno.
///
/// **Barva je puntík, ne výplň chipu.** Barvy labelů jsou libovolné, takže plná výplň by u každé
/// z nich musela počítat kontrast textu — a v panelu, kde jediné plné pole patří odznaku závažnosti
/// nálezu, by přebíjela zrovna to. Podklad je proto neutrální trojice `raised`/`ink2`/`line`, tatáž
/// jako u odznaku `doporučení`.
struct LabelChipView: View {
    let label: PullRequestLabel
    /// Mez, na kterou se **ořezává jméno**. `nil` = chip se vejde celý.
    let maxWidth: Double?

    var body: some View {
        HStack(spacing: LabelChipStyle.spacing) {
            // Puntík **zůstává vždycky**: podle něj se label pozná i s ukusnutým jménem. Obtažený
            // `line`, protože bez obtažení se bledé barvy ztratí na světlém podkladu a tmavé na
            // tmavém — každý motiv má tu vadu z jiné strany.
            Circle()
                .fill(dotColor)
                .frame(width: LabelChipStyle.dotSize, height: LabelChipStyle.dotSize)
                .overlay { Circle().strokeBorder(Palette.line, lineWidth: 1) }
            Text(verbatim: label.name)
                .font(.system(size: LabelChipStyle.fontSize, weight: .semibold))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, LabelChipStyle.textInset)
        .padding(.vertical, LabelChipStyle.insetVertical + LabelChipStyle.borderWidth)
        .background { RoundedRectangle(cornerRadius: LabelChipStyle.cornerRadius).fill(Palette.raised) }
        .overlay {
            RoundedRectangle(cornerRadius: LabelChipStyle.cornerRadius)
                .strokeBorder(Palette.line, lineWidth: LabelChipStyle.borderWidth)
        }
        // Mez se uplatňuje na **celý chip**, ne na text: `frame` v SwiftUI omezuje vnější rozměr,
        // takže odsazení i obtažení jsou uvnitř — tedy `box-sizing: border-box` z návrhu.
        .frame(maxWidth: maxWidth.map { CGFloat($0) })
        .help(label.name)
        .accessibilityLabel("label \(label.name)")
    }

    /// Barva z odpovědi GitHubu. Neplatný nebo chybějící hex je **tichý neutrál**, ne výstraha:
    /// nepřečtená barva o labelu neříká nic špatného a puntík má být vidět tak jako tak.
    private var dotColor: Color {
        guard let hex = UInt32(label.color, radix: 16), label.color.count == 6 else {
            return Palette.ink3
        }
        // Barva labelu je **jedna pro oba motivy** — je to hodnota z repozitáře, ne token palety,
        // takže se pro tmavý režim nemá odkud vzít druhá.
        return Color(light: hex, dark: hex)
    }
}

/// Odznak `+N` — kolik labelů se nevešlo.
///
/// **Počítá se, neořezává**: z prostě ořezaného seznamu se nepozná, že něco chybí.
struct LabelMoreChipView: View {
    let count: Int

    var body: some View {
        Text(verbatim: "+\(count)")
            .font(.system(size: LabelChipStyle.fontSize, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, LabelChipStyle.textInset)
            .padding(.vertical, LabelChipStyle.insetVertical + LabelChipStyle.borderWidth)
            .background { RoundedRectangle(cornerRadius: LabelChipStyle.cornerRadius).fill(Palette.raised) }
            .overlay {
                RoundedRectangle(cornerRadius: LabelChipStyle.cornerRadius)
                    .strokeBorder(Palette.line, lineWidth: LabelChipStyle.borderWidth)
            }
            .help(Plural.czech(count, one: "další label", few: "další labely", many: "dalších labelů"))
    }
}

/// Podoba akčního chipu (`+ label`, `+ reviewer`).
///
/// Přerušovaný okraj proti plnému drží úmluvu z návrhu: **plné je to, co na PR je, přerušované to,
/// co se dá přidat.**
struct AddChipLabel: View {
    let title: String
    /// Zakázaná akce se kreslí ztlumeně — na vlastním PR, kde je odesílání vypnuté, je „tady se to
    /// dělá, jen teď ne“ pravda. Na cizím PR se chip nekreslí vůbec, o tom rozhoduje volající.
    var isEnabled = true

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: LabelChipStyle.fontSize, weight: .medium))
            .foregroundStyle(isEnabled ? Palette.ink3 : Palette.ink3.opacity(0.5))
            .lineLimit(1)
            .padding(.horizontal, LabelChipStyle.textInset)
            .padding(.vertical, LabelChipStyle.insetVertical + LabelChipStyle.borderWidth)
            .overlay {
                RoundedRectangle(cornerRadius: LabelChipStyle.cornerRadius)
                    .strokeBorder(
                        Palette.line,
                        style: StrokeStyle(lineWidth: LabelChipStyle.borderWidth, dash: [3, 2])
                    )
            }
            .contentShape(.rect)
    }
}
