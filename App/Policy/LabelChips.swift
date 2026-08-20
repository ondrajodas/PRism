import Foundation

/// Jak se labely v pravém panelu zalomí (#392).
///
/// **Počítá se to, nevyjednává** — pravidlo #220. Panel má známou šířku (tu, kterou si člověk
/// vytáhl), popisky jsou konkrétní řetězce, takže se šířka každého chipu dá změřit a o podobě
/// řádků rozhodnout z čísel. Kdyby se to nechalo na SwiftUI, dostal by se do hry nejen výkon, ale
/// hlavně **dvouřádkový strop** — ten se z pružného rozvržení nedá vyjádřit vůbec.
///
/// Dvě pasti, na které se přišlo teprve měřením zákresu (#390) a obě jsou tady:
///
/// - **Ořez jménu musí nechat místo na `+N`.** Prostý „ořež na šířku řádku“ dá chip přes celý
///   druhý řádek, `+N` spadne na třetí a řádky labelů jsou **tři** — tedy zrovna to, co má strop
///   zakázat, protože třetí řádek ukusuje místo nálezům.
/// - **Šířka chipu se počítá i s rámem a odsazením.** Mez uplatněná na obsah nechá chip o padding
///   a okraj přerůst; v zákresu z toho byl chip 230 bodů v řádku širokém 214, tedy 3 body za
///   pravým okrajem panelu.
extension Policy {
    /// Jeden prvek v řádku chipů.
    enum LabelChip: Hashable, Sendable {
        /// Label; `maxWidth` je `nil`, dokud se nemusí ořezávat.
        case label(PullRequestLabel, maxWidth: Double?)
        /// Kolik labelů se nevešlo. Kreslí se jako `+2`.
        case more(Int)
        /// `+ label`. **Neustoupí nikdy** — když na poslední řádek nevyjde, vezme si vlastní.
        case add
    }

    /// Rozměry, ze kterých se rozvržení počítá. Měří je ten, kdo kreslí (`LabelChipStyle`),
    /// protože jedině on ví, jakým písmem — `Policy` je bez I/O a bez AppKitu.
    struct LabelChipMetrics: Sendable {
        /// `gap` z návrhu (`.chipline`).
        var spacing = 5.0
        /// Šířka chipu i s puntíkem, odsazením a obtažením.
        var chipWidth: @Sendable (PullRequestLabel) -> Double
        /// Šířka odznaku `+N` pro daný počet. Závisí na počtu číslic, takže je to funkce.
        var moreWidth: @Sendable (Int) -> Double
        /// Šířka akčního chipu `+ label`.
        var addWidth: Double
    }

    /// Řádky chipů, jak se mají nakreslit.
    struct LabelChipLayout: Hashable, Sendable {
        var rows: [[LabelChip]]

        /// Kolik labelů se nevešlo. Nula = jsou vidět všechny.
        var hidden: Int

        /// Řádky, na kterých je aspoň jeden label. **Do stropu se akční řádek nepočítá** —
        /// `+ label` se neschovává, takže vlastní řádek nesmí ubrat místo labelům.
        var labelRows: Int {
            rows.count {
                $0.contains { if case .label = $0 { true } else { false } }
            }
        }
    }

    /// Rozvržení řádku chipů v panelu dané šířky.
    ///
    /// `width` je šířka, která na chipy doopravdy zbývá (panel minus jeho odsazení), `rowLimit`
    /// strop **řádků s labely**. `canAdd` je akce `+ label`, tedy jen na vlastním PR — na cizím se
    /// nekreslí vůbec, ne zašedle.
    static func labelChips(
        _ labels: [PullRequestLabel],
        width: Double,
        metrics: LabelChipMetrics,
        canAdd: Bool,
        rowLimit: Int = 2
    ) -> LabelChipLayout {
        var reserve = 0.0
        var layout = pack(labels, width: width, metrics: metrics, rowLimit: rowLimit, reserve: reserve)
        // `+N` je široké podle počtu, který se dozvíme až po zabalení — a s rezervou se ten počet
        // může zvednout, čímž se rezerva zvětší. Roste monotónně, takže se to po pár krocích
        // zastaví; strop je jen pojistka proti nekonečnu, ne očekávaný počet kol.
        for _ in 0...labels.count {
            let needed = layout.hidden > 0 ? metrics.moreWidth(layout.hidden) + metrics.spacing : 0
            guard needed != reserve else { break }
            reserve = needed
            layout = pack(labels, width: width, metrics: metrics, rowLimit: rowLimit, reserve: reserve)
        }

        var rows = layout.rows
        if layout.hidden > 0 {
            append(.more(layout.hidden), to: &rows, width: metrics.moreWidth(layout.hidden), metrics: metrics, available: width)
        }
        if canAdd {
            append(.add, to: &rows, width: metrics.addWidth, metrics: metrics, available: width)
        }
        return LabelChipLayout(rows: rows, hidden: layout.hidden)
    }

    /// Chipy do řádků, zleva a s výškou stropu. `reserve` je místo, které se na **posledním
    /// povoleném** řádku drží pro `+N`.
    private static func pack(
        _ labels: [PullRequestLabel],
        width: Double,
        metrics: LabelChipMetrics,
        rowLimit: Int,
        reserve: Double
    ) -> LabelChipLayout {
        var rows: [[LabelChip]] = []
        var index = 0
        while rows.count < rowLimit, index < labels.count {
            let isLastRow = rows.count == rowLimit - 1
            // Nikdy ne nula ani záporno: rezerva širší než panel by chip vyřadila úplně.
            let available = max(1, width - (isLastRow ? reserve : 0))
            var row: [LabelChip] = []
            var used = 0.0
            while index < labels.count {
                let chip = metrics.chipWidth(labels[index])
                let needed = row.isEmpty ? chip : used + metrics.spacing + chip
                if needed <= available {
                    row.append(.label(labels[index], maxWidth: nil))
                    used = needed
                    index += 1
                } else if row.isEmpty {
                    // Chip sám je širší než řádek — **ořeže se text, chip zůstane celý** a puntík
                    // s barvou v něm. Podle něj se label pozná i s ukusnutým jménem.
                    row.append(.label(labels[index], maxWidth: available))
                    used = available
                    index += 1
                } else {
                    break
                }
            }
            rows.append(row)
        }
        return LabelChipLayout(rows: rows, hidden: labels.count - index)
    }

    /// Připíše `+N` nebo `+ label` na poslední řádek, a když se tam nevejde, dá mu vlastní.
    private static func append(
        _ chip: LabelChip,
        to rows: inout [[LabelChip]],
        width: Double,
        metrics: LabelChipMetrics,
        available: Double
    ) {
        let used = rows.last.map { row in
            row.reduce(0.0) { total, item in
                total + chipWidth(item, metrics: metrics) + metrics.spacing
            }
        } ?? 0
        if !rows.isEmpty, used + width <= available {
            rows[rows.count - 1].append(chip)
        } else {
            rows.append([chip])
        }
    }

    private static func chipWidth(_ chip: LabelChip, metrics: LabelChipMetrics) -> Double {
        switch chip {
        case .label(let label, let maxWidth): min(metrics.chipWidth(label), maxWidth ?? .infinity)
        case .more(let count): metrics.moreWidth(count)
        case .add: metrics.addWidth
        }
    }
}
