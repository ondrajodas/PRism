import SwiftUI

/// Souřadnice pull requestu pod titulkem (#174).
///
/// Odpovídá na otázku, která se do #174 v okně zodpovědět nedala a chodilo se kvůli ní do
/// prohlížeče: **kam se to merguje**. Na tu druhou — proti čemu platí nálezy na obrazovce —
/// odpovídá `StaleHeadView` níž, protože se ukazuje jen občas.
struct PullRequestHeaderView: View {
    let pullRequest: PullRequestSummary
    /// Načtený detail. `nil` = ještě nedorazil, takže větve ani hlavu neukazujeme; hádat je
    /// horší než je chvíli nemít.
    var detail: PullRequest?
    /// Checky (#209). Souhrn patří **do hlavičky**, ne jen do tabu `Přehled`: „dá se to
    /// mergnout“ je otázka, kterou má okno zodpovědět bez přepínání, a při čtení diffu se
    /// do `Přehledu` nechodí.
    var checks: [PullRequestCheck] = []
    /// Čí PR to je (#330, kreslí se od #334). Na vlastním stojí za stavem pilulka `moje PR`, jak ji
    /// má návrh (sekce 22) — a je to jediné místo v hlavičce, které tu informaci nese.
    var ownership: PullRequestOwnership = .theirs
    /// Odkud se záložka vzala (#531). Mimo zdroje za stavem stojí pilulka `mimo zdroje ·
    /// jen ke čtení`, jak ji má návrh (sekce 40) — u PR ze zdrojů se nekreslí nic.
    var origin: PullRequestOrigin = .sources

    var body: some View {
        HStack(spacing: 9) {
            state
            outsideSources
            mine
            if let detail, !detail.headRef.isEmpty, !detail.baseRef.isEmpty {
                merge(detail)
            }
            separator
            // **Bez čísla** (#218). To se od #218 sází vedle titulku, velké a tlumené, jak ho
            // má návrh; tady by byla druhá kopie téhož — a `owner/repo#4` je tvar, ve kterém
            // číslo nikdo nehledá.
            Text(verbatim: pullRequest.repo.description)
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
            // Tečka jde **před** každou položkou, ne za ní: souhrn checků se u PR bez CI
            // nekreslí, a tečka za ním by pak visela ve vzduchu.
            checksChip
            separator
            Link("otevřít na GitHubu", destination: pullRequest.url)
        }
        .font(.callout)
    }

    /// `mimo zdroje · jen ke čtení` (#531) — pilulka z návrhu (`.pill.idle`), jen na záložce,
    /// kterou si člověk otevřel odkazem.
    ///
    /// **Tlumená trojice, ne barva ze škály**: není to porucha ani nález, je to **konstatování,
    /// odkud ta záložka je**. Barevná kapsle vedle plného stavu PR by z hlavičky udělala druhý
    /// semafor — tentýž důvod, proč je `moje PR` vedle ní jen mint na patnácti procentech.
    ///
    /// **Za stavem, před autorem**, jak to kreslí návrh: stav PR je pořád první věc, kvůli které
    /// se člověk na hlavičku dívá, a odkud PR je, je odpověď na tu druhou otázku v pořadí.
    ///
    /// Text i to, jestli se kreslí, rozhoduje `Policy.originNote(_:)` — ne `if` tady.
    @ViewBuilder private var outsideSources: some View {
        if let note = Policy.originNote(origin) {
            Text(verbatim: note)
                .designPill(tint: Palette.ink2, background: Palette.raised)
                .help("Tenhle pull request není v tvých zdrojích — otevřel sis ho odkazem, takže není ve frontě, na kartách ani v odznaku. Review na něm jde pustit ručně.")
        }
    }

    /// `moje PR` (#334) — pilulka z návrhu (`.pill.mint`), jen na vlastním pull requestu.
    ///
    /// **Mint schválně**: je to konstatování stavu, se kterým se nic nedělá (viz `Palette.mint`) —
    /// vlastní PR není porucha ani nález. Vedle plné kapsle stavu stojí jako tlumená, aby zůstalo
    /// jedno plné pole v pruhu, jak to má návrh.
    ///
    /// Na cizím PR **nic**, ne pilulka „cizí PR“: hlavička by nesla údaj, který platí u devadesáti
    /// procent řádků, tedy šum. Že je PR vlastní, je odchylka od běžného stavu, a ta se pojmenovává.
    @ViewBuilder private var mine: some View {
        if ownership == .mine {
            Text("moje PR")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.mint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Palette.mint.opacity(0.15), in: .capsule)
                .help("Tenhle PR jsi psal ty — review se odsud neodesílá, místo verdiktu se z nálezů skládá zadání pro agenta")
        }
    }

    /// Tečka mezi souřadnicemi, jak ji má návrh (`.pr-meta`). Sama o sobě neříká nic, takže
    /// ji odečítání nemá číst.
    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(Palette.ink3)
            .accessibilityHidden(true)
    }

    /// Stav PR jako **plná kapsle** (#218, `.state-chip`): puntík, slovo a barva na podkladu,
    /// ne tlumený odznak.
    ///
    /// Do #218 to byl text v barvě stavu na patnáctiprocentní výplni — tedy nejtišší prvek
    /// pruhu, přestože je to údaj, kvůli kterému se na hlavičku dívám první. Návrh ho má jako
    /// jediné plné pole v celém pruhu.
    private var state: some View {
        HStack(spacing: 5) {
            Circle()
                .frame(width: 6, height: 6)
            Text(verbatim: pullRequest.state.czechLabel)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        // Text v barvě **podkladu okna** (`--panel`), ne bíle: v tmavém režimu je bílá na
        // zelené oslnivá a návrh na ni v obou režimech sází barvu plochy.
        .foregroundStyle(Palette.surface)
        .background(stateTint, in: .capsule)
    }

    /// `autor chce sloučit větev → base`. Větve jsou v mono, protože je to identifikátor,
    /// který se čte po znacích a občas kopíruje.
    private func merge(_ detail: PullRequest) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: pullRequest.author)
                .fontWeight(.medium)
            Text("chce sloučit")
            branch(detail.headRef)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(Palette.ink3)
            branch(detail.baseRef)
        }
        .foregroundStyle(Palette.ink2)
    }

    private func branch(_ name: String) -> some View {
        Text(verbatim: name)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Palette.raised, in: .rect(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.lineSoft) }
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    /// Barva kapsle. Všechny čtyři stavy jdou z palety návrhu — systémové `.green` a `.red`
    /// by v plné kapsli s textem v barvě plochy vyšly příliš světle, a `.purple` s `.secondary`
    /// by do neutrálů posunutých do modrofialové nesedly vůbec.
    private var stateTint: Color {
        switch pullRequest.state {
        case .open: Palette.ok
        case .draft: Palette.ink3
        // Fialová z návrhu je jen jedna a je to akcent; mergnutý PR je jediné místo, kde ji
        // nese stav, a plete se s ní jen `Spustit review` o řádek výš.
        case .merged: Palette.accent
        case .closed: Palette.crit
        }
    }
}

/// Hlava PR a sha, proti které platí nálezy (#174).
///
/// Kreslí se **jen když se ty dvě rozejdou**. Dokud se rovnají, je to trivia, která by
/// v hlavičce zabírala řádek; jakmile se rozejdou, je to ta nejdůležitější věc na obrazovce,
/// protože všechno pod ní mluví o kódu, který na větvi už není.
struct StaleHeadView: View {
    let head: String
    let findingsHead: String
    /// Co o těch nálezech řekla kontrola nových commitů (#150). `.none` = neběžela a řádek pak
    /// mluví jen o sha, jako do #150.
    var recheck: Policy.RecheckReport = .none

    var body: some View {
        // Věta o kontrole patří **pod** řádek o sha, ne za něj: mluví o týchž nálezech, ale je
        // delší, a v jednom řádku by se v úzkém okně ořezala zrovna ona.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.stale)
                    .font(.caption)
                Text("Nálezy jsou proti")
                sha(findingsHead)
                Text(", hlava PR je")
                sha(head)
            }
            .help("Co je na obrazovce, platí ke staršímu commitu. Nové review je proti aktuální hlavě.")
            recheckLine
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Co kontrola zjistila — nebo že už neplatí.
    ///
    /// Zastaralá kontrola **nemlčí**: odznaky u nálezů zmizely (`Policy.recheck(of:head:)` je
    /// nevydá), takže bez téhle věty by vypadalo, že kontrola nikdy neběžela — a pustila by se
    /// podruhé za peníze, aniž by kdo věděl, že první výsledek existoval.
    @ViewBuilder private var recheckLine: some View {
        switch recheck {
        case .none:
            EmptyView()
        case .outdated(let againstHeadSha):
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.caption2)
                Text("Kontrola nálezů běžela proti")
                sha(againstHeadSha)
                Text(verbatim: "— pro tenhle commit neplatí, pusť ji znovu.")
            }
        case .current(let tally):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.caption2)
                Text(verbatim: Self.label(of: tally))
                Text(tally.finishedAt, format: .relative(presentation: .named))
                    .foregroundStyle(.tertiary)
            }
            .help(Self.hint(of: tally))
        }
    }

    /// Věta o počtech. Skládá se z hotových čísel, takže `nonisolated static` — testuje se bez
    /// kreslení a rozhodování zůstává v `Policy`.
    ///
    /// **Nezodpovězené nálezy se vyjmenují.** Bez nich by „3 vyřešené“ nad pěti nálezy vypadalo,
    /// že ty dva zbylé platí — a to kontrola neřekla.
    ///
    /// Skloňuje se přes `Plural.czech` všude, kde se tvar mění. `pořád platí` a `bez odpovědi`
    /// jsou nesklonné obraty (`1 pořád platí`, `2 pořád platí`), takže u nich není co skloňovat —
    /// zbytek jde tabulkou tvarů, protože jazyk aplikace je čeština a `1 nejasných` praští do očí
    /// hned (nálezem Copilota na #150).
    nonisolated static func label(of tally: Policy.RecheckTally) -> String {
        var parts: [String] = []
        if tally.resolved > 0 {
            parts.append(Plural.czech(
                tally.resolved,
                one: "vyřešený",
                few: "vyřešené",
                many: "vyřešených"
            ))
        }
        if tally.stillApplies > 0 { parts.append("\(tally.stillApplies) pořád platí") }
        if tally.unclear > 0 {
            parts.append(Plural.czech(
                tally.unclear,
                one: "nejasný",
                few: "nejasné",
                many: "nejasných"
            ))
        }
        if tally.unanswered > 0 { parts.append("\(tally.unanswered) bez odpovědi") }
        guard !parts.isEmpty else { return "Kontrola nálezů neodpověděla na nic" }
        return "Kontrola nálezů: " + parts.joined(separator: ", ")
    }

    /// Nápověda k větě: odkud to je a co z toho **neplyne**.
    ///
    /// Že kontrola nedoběhla, se do věty nevejde, a mlčet o tom nejde: běh zabitý po dvou
    /// odpovědích za zbytek nemluví.
    nonisolated static func hint(of tally: Policy.RecheckTally) -> String {
        let base = "Tvrzení kontroly nových commitů, ne fakt — nález sundá jedině tvoje odmítnutí."
        switch tally.outcome {
        case .finished: return base
        case .timedOut: return "Kontrola nedoběhla (timeout), takže za zbytek nemluví. " + base
        case .interrupted: return "Kontrola skončila s aplikací, takže za zbytek nemluví. " + base
        case .failed(let detail): return "Kontrola spadla: \(detail) " + base
        }
    }

    private func sha(_ value: String) -> some View {
        Text(verbatim: String(value.prefix(7)))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
}

#Preview {
    let id = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)
    let summary = PullRequestSummary(
        id: id,
        title: "chore: modernize dependencies",
        author: "odinuv",
        url: URL(string: "https://github.com/keboola/vault/pull/85")!,
        updatedAt: Date(),
        state: .open
    )

    return VStack(alignment: .leading, spacing: 10) {
        PullRequestHeaderView(
            pullRequest: summary,
            detail: PullRequest(
                id: id,
                title: summary.title,
                author: "odinuv",
                headSha: "9c1de0212ab",
                baseSha: "4f2ac9188cd",
                headRef: "chore/deps-2026",
                baseRef: "main",
                url: summary.url,
                updatedAt: Date(),
                state: .open
            )
        )
        StaleHeadView(head: "9c1de0212ab", findingsHead: "4f2ac9188cd")
    }
    .padding()
    .frame(width: 700)
}


extension PullRequestHeaderView {
    /// Souhrn checků jedním chipem. **Barva podle nejhoršího** — dvanáct zelených a jeden
    /// červený je červený stav. Bez checků se nekreslí nic: PR bez CI je běžná věc a prázdný
    /// chip by tvrdil, že se něco nepovedlo.
    /// **Chip zůstává i po #215**, kdy se seznam checků odstěhoval do vlastního tabu: „je to
    /// zelené“ se musí dát přečíst i při čtení diffu, tedy z hlavičky, která je vidět ve všech
    /// tabech. Od #215 je to navíc **jediné** místo o checcích mimo tab — souhrn v `Přehledu`
    /// odešel s ním, protože tři místa o téže věci jsou o dvě moc.
    @ViewBuilder fileprivate var checksChip: some View {
        let summary = Policy.summary(of: checks)
        // `worst` a první část poměru jsou obojí neprázdné právě u neprázdné sady, takže se
        // ptáme na obojí a nikde nedosazujeme náhradní hodnotu.
        if let worst = summary.worst, let headline = ChecksText.parts(of: summary).first {
            separator
            HStack(spacing: 4) {
                Image(systemName: symbol(of: worst))
                    .font(.system(size: 10))
                Text(verbatim: headline)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(ChecksText.color(of: worst))
            .help("Kontroly na GitHubu — podrobnosti jsou v tabu Kontroly")
        }
    }

    /// **S kolečkem**, na rozdíl od seznamu v tabu: chip stojí v řadě dalších kapslí, kde
    /// obtažený symbol drží tvar. Barva je proti tomu společná (`ChecksText.color`) — dvě
    /// zelené v jednom okně by znamenaly jednu věc.
    private func symbol(of outcome: PullRequestCheck.Outcome) -> String {
        switch outcome {
        case .passed: "checkmark.circle"
        case .failed, .cancelled: "xmark.circle"
        case .running: "circle.dashed"
        case .skipped: "minus.circle"
        }
    }
}
