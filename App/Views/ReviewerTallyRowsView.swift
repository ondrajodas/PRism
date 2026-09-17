import SwiftUI

/// Řádky bloku `Reviewery · 30 dní` na domově (#514) a legenda pod nimi.
///
/// **Rám bloku kreslí `BoardView`** (`block(_:count:action:)`), jako u `Odložených`: hlavička
/// s nadpisem a odkazem do Nastavení je jedna komponenta pro celý pravý sloupec a druhá kopie
/// by se s ní rozešla.
///
/// **Rozhodování je v `Policy`, tady se kreslí.** Kolik čeho je, jak zní věta a kam míří, vydá
/// `Policy.reviewerTallies(from:now:)` a `Policy.reviewerSignal(of:)`; view z toho nesmí nic
/// dopočítávat — je to zrovna to místo, kde by se dalo nejsnáz napsat něco, co data neunesou.
///
/// Rozměry a barvy jsou z návrhu (`.rv-stat`, `.rv-bar`, `.rv-barlegend`, sekce 61) doslova.
struct ReviewerTallyRowsView: View {
    let tallies: [ReviewerTally]

    var body: some View {
        VStack(spacing: 0) {
            // **O podobě řádku se rozhoduje za celý blok, ne za řádek** — viz `rows(stacked:)`.
            ViewThatFits(in: .horizontal) {
                rows(stacked: false)
                rows(stacked: true)
            }
            // **Legenda je pod řádky, ne v hlavičce.** Čtyři barvy se do hlavičky bloku vedle
            // nadpisu a odkazu nevejdou, a hlavně se čtou **až** s pruhem nad nimi — legenda
            // nad prvním pruhem by byla vysvětlení něčeho, co člověk ještě neviděl.
            separator
            legend
        }
    }

    // MARK: - Řádek

    /// Řádky bloku v jedné ze dvou podob.
    ///
    /// **Dvě podoby, ne zkracování na sílu** (tatáž úvaha jako u hlavičky karty v `Přehledu`,
    /// #291). Pravý sloupec domova má v okně na jeho minimu (700) kolem 210 bodů obsahu, a to
    /// je méně, než co si věta `5 z 11 nepatří sem → pravidla repa` bere sama. `HStack` by ji
    /// nakrájel tak, že by z ní zbylo `5 z 11 nepatří…`, tedy zrovna ta půlka bez cíle. Užší
    /// podoba proto věc **složí pod sebe**: jméno s repem na první řádek, pruh s větou na druhý.
    ///
    /// **Rozhoduje se to za celý blok, a je to oprava po prvním proklikání.** `ViewThatFits`
    /// navěšený na jednotlivý řádek vydal blok, ve kterém byly dva řádky složené a dva na jeden
    /// řádek — o podobě totiž rozhodovala **délka věty**, a ta se řádek od řádku liší. Vypadalo
    /// to jako porucha kresby, ne jako ústupek úzkému sloupci. Takhle se složí buď všechny, nebo
    /// žádný, a pruhy zůstanou pod sebou v jedné svislici.
    private func rows(stacked: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(tallies) { tally in
                row(tally, stacked: stacked)
                if tally.id != tallies.last?.id { separator }
            }
        }
    }

    @ViewBuilder private func row(_ tally: ReviewerTally, stacked: Bool) -> some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    who(tally)
                    HStack(spacing: 12) {
                        bar(tally).frame(width: barWidth)
                        verdict(tally)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    who(tally)
                    Spacer(minLength: 0)
                    bar(tally).frame(width: barWidth)
                    verdict(tally)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    /// Kdo a kde — mono, protože je to id skillu a jméno repa, ne próza.
    ///
    /// **Počet nálezů patří sem, ne do věty vpravo**: věta o něm mluví jako o jmenovateli
    /// (`9 z 14`), takže bez něj nad ní chybí to, z čeho se počítá. A `nálezů` se skloňuje —
    /// `1 nálezů` je v okně vidět dřív než v testu.
    private func who(_ tally: ReviewerTally) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: tally.reviewer)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "\(tally.repo.name) · \(Plural.czech(tally.total, one: "nález", few: "nálezy", many: "nálezů"))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Pruh ze čtyř podílů. Podklad je `Palette.raised`, takže prázdné místo (nemůže vzniknout,
    /// ale kdyby) není díra.
    ///
    /// **Nula se nekreslí**, ne kreslí se na nulovou šířku: `frame(width: 0)` s mezerou vedle sebe
    /// dá jednobodovou spáru, tedy dílek, který v datech není.
    private func bar(_ tally: ReviewerTally) -> some View {
        let segments = ReviewerBarSegment.all(of: tally)
        // **`ProportionalColumns`, ne `HStack` s prioritami**: dílek má být přesný podíl, a to
        // `HStack` neumí ani s `layoutPriority` — ta rozděluje **přebytek**, ne celek. Je to
        // tentýž layout, kterým se dělí sloupce domova, jen s jinými poměry.
        return ProportionalColumns(ratios: segments.map(\.share), spacing: 1) {
            ForEach(segments) { segment in
                Rectangle().fill(segment.color)
            }
        }
        .frame(height: 8)
        .background(Palette.raised)
        .clipShape(.rect(cornerRadius: 4))
    }

    /// Věta vpravo. `warn` z návrhu je `--crit` u **obou** důvodů — v bloku jde o to, že se
    /// něco ozývá, kdežto v tabulce v Nastavení nese barvu ten konkrétní důvod. Je to z návrhu
    /// doslova, ne opomenutí.
    @ViewBuilder private func verdict(_ tally: ReviewerTally) -> some View {
        if let signal = Policy.reviewerSignal(of: tally) {
            Text(verbatim: signal.text)
                .font(.system(size: 11.5))
                .foregroundStyle(signal.aim == .none ? Palette.ink2 : Palette.crit)
                .lineLimit(1)
                .help(help(for: signal))
        }
    }

    private func help(for signal: ReviewerSignal) -> String {
        switch signal.aim {
        case .skill:
            "Přes polovinu nálezů tohohle revieweera v tomhle repu neobstálo a nejčastěji proto, "
                + "že v kódu nebylo, co popisuje. Opravit to jde v skillu."
        case .repoRules:
            "Přes polovinu nálezů tohohle revieweera v tomhle repu neobstálo a nejčastěji proto, "
                + "že sem nepatří. Reviewer má pravdu, jen hlásí, co tenhle repozitář nechce — "
                + "patří to do jeho pravidel."
        case .none:
            "Kolik nálezů tohohle revieweera v tomhle repu jsem nechal platit."
        }
    }

    // MARK: - Legenda

    private var legend: some View {
        // Zalamuje se (`flex-wrap` z návrhu), protože čtyři popisky se do ~210 bodů pravého
        // sloupce na jeden řádek nevejdou. `spacing` 14 je z návrhu.
        FlowRow(spacing: 14, lineSpacing: 6) {
            ForEach(ReviewerBarSegment.legend) { segment in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.color)
                        .frame(width: 10, height: 8)
                    Text(verbatim: segment.title)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    /// Šířka pruhu. **Pevná, ne pružná**: v úzké podobě řádku stojí pruh vedle věty, a pružný by
    /// se z něj v ní stal proužek na pár bodů — dílek o jednom nálezu by v něm zmizel.
    private let barWidth: CGFloat = 92

    private var separator: some View {
        Rectangle().fill(Palette.lineSoft).frame(height: 1)
    }
}
