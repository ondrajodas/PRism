import SwiftUI

/// Chipy reviewerů: co který udělal a jestli jsou jeho nálezy vidět.
///
/// Dvě věci naráz — stav a filtr. Vypnutý chip je ztlumený a jeho nálezy zmizí z bublin
/// i z tabulky.
///
/// **Puntík a počet, ne ikona a slovo** (#218, `.rchip`). Do #218 chip nesl symbol stavu
/// a k němu slovo (`2 nálezy`, `čisté`), což je v pruhu, kam se vedle vejde ještě proužek
/// průběhu, dvakrát tolik místa než `● php-review 2`. Barvu stavu nese puntík; co se stalo,
/// říká celou větou nápověda. Slovo zůstává jen tam, kde **není co počítat** (`neběželo`,
/// `selhalo`, `nejisté`) — nula by u nich tvrdila, že reviewer doběhl a nic nenašel.
struct ReviewerChipsView: View {
    let chips: [ReviewerChip]
    /// Reviewery, jejichž nálezy jsou schované.
    @Binding var muted: Set<String>
    /// Pustit znovu jen tohohle revieweera (#149). `nil` = odsud se nespouští (náhledy, testy).
    var rerun: ((String) -> Void)?
    /// Běží nad tímhle PR review? Dokud běží, nejde spustit nic dalšího — je to jedna úloha
    /// na PR, viz `AppStore.RunningReview`.
    var isReviewing = false

    /// Zkrácená jména do úzké kapsle (#182). Počítá se z **celé** sady naráz: zkrátit se smí
    /// jen to, co po zkrácení zůstane jednoznačné vůči ostatním.
    private var shortNames: [String: String] {
        Policy.shortReviewerNames(of: chips.map(\.skill))
    }

    var body: some View {
        let names = shortNames
        HStack(spacing: 7) {
            ForEach(chips) { chip in
                button(chip, name: names[chip.skill] ?? chip.skill)
            }
        }
    }

    private func button(_ chip: ReviewerChip, name: String) -> some View {
        let isMuted = muted.contains(chip.skill)
        return Button {
            if isMuted { muted.remove(chip.skill) } else { muted.insert(chip.skill) }
        } label: {
            HStack(spacing: 6) {
                icon(chip.state)
                // **Jeden řádek.** Kapsle je vedle proužku průběhu, který si o místo řekne
                // taky — bez tohohle se `php-review` zalomí uvnitř kapsle na dva řádky
                // a celý pruh povyroste.
                Text(verbatim: name)
                    .font(.subheadline)
                    .lineLimit(1)
                if let label = Self.label(chip.state) {
                    Text(verbatim: label)
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                }
                // Nálezy dorazily, ale ne všechny — bez tohohle vypadá neúplný výsledek
                // jako úplný.
                if chip.warning != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.stale)
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .padding(.vertical, 3)
            // Podklad je u všech stavů **stejný**, jak ho má návrh: co se stalo, nese puntík.
            // Tónovaná výplň (červená u selhání, oranžová u nálezů) dělala z řady kapslí
            // druhou barevnou škálu vedle té, kterou nesou samotné tečky.
            .background(Palette.chrome, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.line))
            .opacity(isMuted ? 0.45 : 1)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // Podrobnost (stderr, důvod nejistoty) visí na nápovědě: kliknutí patří filtru,
        // který se používá mnohem častěji.
        .help(help(chip, isMuted: isMuted))
        // Puntík je barva a **barva sama nestačí** — od #218 už stav nenese ani slovo, takže
        // je odečítání jediné místo, kde se „čisté“ pozná od „selhalo“.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.skill)
        .accessibilityValue(Self.spokenState(chip.state))
        .contextMenu { rerunItem(chip) }
    }

    /// Opakování jednoho revieweera (#149).
    ///
    /// **Kontextové menu, ne druhé tlačítko v chipu.** Chip je malý a jeho kliknutí už patří
    /// filtru, který se používá mnohem častěji; ikonka navíc by se do něj mačkala a trefovala
    /// by se hůř než ta, kterou by nahradila. Že tam menu je, říká nápověda.
    ///
    /// Dokud nad PR běží review, je položka **zakázaná, ne schovaná**: důvod je vidět
    /// o kousek vedle (chip se spinnerem) a za chvíli sám zmizí — kdežto menu, které se občas
    /// neobjeví, vypadá jako závada. Tatáž úvaha jako u tlačítka `Odpovědět` ve vlákně.
    @ViewBuilder private func rerunItem(_ chip: ReviewerChip) -> some View {
        if let rerun {
            Button(chip.state == .notStarted ? "Pustit jen tohohle revieweera" : "Pustit znovu jen tohohle revieweera") {
                rerun(chip.skill)
            }
            .disabled(isReviewing)
        }
    }

    /// Puntík (`.rchip .sw`), u běžícího revieweera spinner — ten je jediný stav, který se
    /// v čase mění, a nehybná tečka by o něm tvrdila, že je hotovo.
    @ViewBuilder private func icon(_ state: ReviewerChip.State) -> some View {
        switch state {
        case .running:
            ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 7, height: 7)
        default:
            Circle()
                .fill(Self.color(state))
                .frame(width: 7, height: 7)
        }
    }

    /// Co stojí za jménem. `nil` = nic — u běžícího revieweera mluví spinner a číslo by nemělo
    /// co říct.
    ///
    /// **Počet je jen tam, kde běh doběhl a dopočítal se.** `0` u nedoběhlého běhu by znamenalo
    /// „nic nenašel“, což je přesně to tvrzení, které data neunesou.
    nonisolated static func label(_ state: ReviewerChip.State) -> String? {
        switch state {
        case .notStarted: "neběželo"
        case .running: nil
        case .clean: "0"
        case .findings(let count): "\(count)"
        case .inconclusive: "nejisté"
        case .failed: "selhalo"
        case .timedOut(let count): count > 0 ? "timeout \(count)" : "timeout"
        case .interrupted(let count): count > 0 ? "přerušeno \(count)" : "přerušeno"
        }
    }

    /// Stav větou pro odečítání. Vidět je jen barva puntíku a číslo, takže tohle je jediné
    /// místo, kde se stav dá přečíst.
    nonisolated static func spokenState(_ state: ReviewerChip.State) -> String {
        switch state {
        case .notStarted: "neběželo"
        case .running: "běží"
        case .clean: "čisté, žádný nález"
        case .findings(let count): Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")
        case .inconclusive: "nejisté"
        case .failed: "selhalo"
        case .timedOut(let count):
            count > 0 ? "timeout, \(Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů"))" : "timeout"
        case .interrupted(let count):
            count > 0 ? "přerušeno, \(Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů"))" : "přerušeno"
        }
    }

    /// Barva puntíku. Z palety návrhu, ne systémová: chipy stojí vedle kapsle stavu PR, která
    /// jde z `--ok`, a dvě různé zelené vedle sebe vypadají jako dva různé významy.
    nonisolated static func color(_ state: ReviewerChip.State) -> Color {
        switch state {
        case .clean: Palette.ok
        case .findings: Palette.find
        case .failed: Palette.crit
        case .inconclusive, .timedOut, .interrupted: Palette.stale
        case .notStarted, .running: Palette.ink3
        }
    }

    /// Nápověda chipu: co se stalo, **co to stálo** a co udělá kliknutí.
    ///
    /// Cena (#148) se bere z uloženého záznamu, takže je tady i po restartu — osa v tabu
    /// `Průběh` je jen v paměti, takže po něm ukáže „zatím se nic nedělo“ a uložená cena by
    /// jinak neměla čtenáře.
    private func help(_ chip: ReviewerChip, isMuted: Bool) -> String {
        var action = isMuted ? "Zobrazit nálezy tohohle revieweera" : "Skrýt nálezy tohohle revieweera"
        // Bez téhle věty se o opakování nikdo nedozví: kontextové menu na chipu není nic,
        // co by šlo uhodnout.
        if rerun != nil {
            action += "\nPravým tlačítkem: pustit znovu jen jeho, bez ostatních."
        }
        let usage = chip.usage.flatMap(RunUsageText.summary(of:))
        // Stav slovem je od #218 v nápovědě **vždycky**, ne jen u poruch: v kapsli po něm
        // zbyl puntík a číslo, takže `čisté` a `selhalo` se jinak liší jen odstínem tečky.
        let headline = "\(chip.skill) — \(Self.spokenState(chip.state))"
        return [headline, detail(of: chip), usage, action]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    /// Podrobnost k tomu, jak běh dopadl. `nil` u stavů, ke kterým není co dodat — samotné
    /// „čisté“ je v hlavičce nápovědy a druhá věta o tomtéž je šum.
    private func detail(of chip: ReviewerChip) -> String? {
        if let warning = chip.warning { return warning }
        switch chip.state {
        case .failed(let detail): return detail
        case .inconclusive(let reason): return reason
        case .timedOut: return "Session nedoběhla v limitu; co stihla nahlásit, je vidět."
        case .interrupted:
            return "Session skončila s aplikací (pád nebo zabití). Nálezy jsou dotažené "
                + "z transcriptu, takže je jich tolik, kolik jich do té chvíle dorazilo."
        default: return nil
        }
    }
}
