import SwiftUI

/// Jedna dráha v tabu `Průběh` (#242, `.lane`).
///
/// Fáze vedle sebe, protože otázka je **srovnávací**: kdo je hotový, kdo běží a kdo spadl. Karta
/// se svislým seznamem událostí na to neodpovídala — muselo se scrollovat a pamatovat si, kde kdo
/// byl. Podrobný výpis událostí tím ale nezmizel: od #325 visí pod fázemi jako **druhá vrstva**
/// (`StepFeedView`), protože „co reviewer doopravdy čte“ je jediná odpověď na otázku, jestli se
/// koukal tam, kam měl.
struct ReviewerLaneView: View {
    let lane: ReviewerLane
    /// Zkrácené jméno skillu. Počítá se z celé sady naráz (`Policy.shortReviewerNames`), takže
    /// ho dráha dostává hotové — zkrátit se smí jen to, co zůstane jednoznačné vůči ostatním.
    let shortName: String
    /// Pustí **jen tohohle** revieweera znovu (#149). `nil` = nejde to (běží jiný běh).
    var rerun: (() -> Void)?
    /// Zkopíruje příkaz k vložení do terminálu. `nil` = neví se, proti čemu se diffuje, takže by
    /// zkopírovaný příkaz nebyl spustitelný.
    ///
    /// **Closure, ne hotový `String`**: příkaz nese celý prompt, takže by se skládal při každém
    /// překreslení tabu, i když se na tlačítko nikdy neklikne.
    var copyCommand: (() -> Void)?
    /// Sbalený, nebo rozbalený výpis kroků (#325). **Drží to tab**, ne tohle view: dráhy jsou
    /// v `LazyVStack`u, takže `@State` uvnitř se odrolováním zahodí — a výpis by se sám zavřel
    /// zrovna u běžícího revieweera.
    let feed: StepFeedState
    let toggleFeed: () -> Void
    /// Otevře přepis celého transcriptu (#327). `nil` = dráha nemá `session_id` nebo pracovní strom,
    /// takže se tlačítko nekreslí — viz `StepFeedView.showRawSession`.
    var showRawSession: (() -> Void)?
    /// Pustí `claude --resume …` v zásuvce s terminálem (#453, #460). `nil` = **není co obnovit,
    /// nebo v okně není zásuvka** — v obou případech se tlačítko nekreslí a rozhoduje o tom
    /// `Policy.terminalSession(of:)` se `AppStore.hasTerminalDrawer`, ne `if` tady.
    var resumeInDrawer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            phases
            if let last = ReviewerLaneText.last(of: lane) {
                Text(verbatim: last)
                    .font(.callout)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            // Jak přírůstek dopadl (#517) — **pod větou o běhu, ne místo ní**: „doběhlo“ je
            // o session, tohle o nálezech. Cena stojí na vlastním řádku, protože srovnání
            // s prvním kolem je druhá věc, ne pokračování věty o nálezech.
            if let increment = lane.increment?.tally,
               let summary = ReviewerLaneText.increment(increment) {
                incrementLine(summary, saving: ReviewerLaneText.incrementSaving(of: lane))
            }
            // Přeskočeno routingem (#518) — věta a tlačítko, ne jen kapsle v hlavičce: kdyby
            // tady nic nebylo, přeskočená dráha by vypadala jako porucha, ze které není cesta ven.
            if case .skipped(let patterns) = lane.state { skippedBlock(patterns) }
            if let failure = lane.failure { failureBlock(failure) }
            if feed != .none {
                StepFeedView(
                    lane: lane,
                    state: feed,
                    toggle: toggleFeed,
                    showRawSession: showRawSession
                )
            }
        }
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(spacing: 9) {
            Text(verbatim: shortName)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .help(lane.skill)
            statePill
            // Přírůstek (#517) — kapsle a za ní rozsah. **Vedle stavu, ne místo něj**: `doběhlo`
            // a `přírůstek` odpovídají na jiné otázky (jak to skončilo × nad čím to běželo)
            // a slít je do jedné kapsle by znamenalo, že se jedna z nich nedozví.
            if let increment = lane.increment {
                Text(verbatim: ReviewerLaneText.incrementLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Palette.accent.opacity(0.15), in: .capsule)
                    .foregroundStyle(Palette.accent)
                    .help(ReviewerLaneText.incrementHelp(increment.range))
                Text(verbatim: ReviewerLaneText.incrementRange(increment.range))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help(ReviewerLaneText.incrementHelp(increment.range))
            }
            // Proč se šlo na **celý** diff, i když by se čekal přírůstek (#517). Bez téhle věty
            // by se rozhodnutí `Policy` nikde nečetlo — a to je stav, který `CLAUDE.md` zakazuje:
            // buď to zobraz, nebo nedrž. Kapsli to nedostává schválně: není to stav běhu, ale
            // vysvětlení, a `celý diff` je navíc to, co bylo do #517 normální.
            if let reason = lane.wholeReason {
                Text(verbatim: "celý diff — \(ReviewerLaneText.wholeReason(reason))")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help(ReviewerLaneText.wholeReasonHelp(reason))
            }
            // Dráha po skillu, který v nastavené sadě není. Nezmizí (to by zahodilo doběhlé
            // review), ale nesmí se tvářit, že do dnešní sady patří.
            if !lane.isConfigured {
                Label("mimo sadu", systemImage: "slash.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help("Tenhle skill není v nastavené sadě pro tohle repo — dráha je ze zaznamenaného běhu, ne z dnešního nastavení.")
            }
            // Proč se nepustil (#518). **Vedle kapsle, ne pod dráhou**: `přeskočeno` bez vzorů
            // je stav bez důvodu a v tabu s pěti dráhami se nedá poznat, které pravidlo to bylo.
            // Nápověda nese totéž doslova, protože v úzkém panelu se řádek ořeže.
            if case .skipped(let patterns) = lane.state {
                Text(verbatim: ReviewerLaneText.routingSkip(patterns: patterns))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help(ReviewerLaneText.routingSkip(patterns: patterns))
            }
            // Zadání, které nedorazilo celé (#345). Musí to být poznat **na dráze**, ne až
            // v souboru: review bez textu issue vypadá v okně stejně jako to s ním, a nález,
            // který se váže k zadání, se tak nemá čím nestat. Popisek je krátký schválně —
            // který díl chyběl, řekne nápověda; hlavička nese už jméno, stav a cenu.
            if let gap = lane.intentGap {
                Label(ReviewerLaneText.intentGapLabel, systemImage: "doc.badge.ellipsis")
                    .font(.caption)
                    .foregroundStyle(Palette.stale)
                    .lineLimit(1)
                    .help(ReviewerLaneText.intentGap(gap))
            }
            // Hlavička tvrdí, který skill běžel. Když si session načetla jiný, musí to říct —
            // jinak je to text, co tvrdí víc, než data unesou.
            if let loaded = lane.loadedSkill {
                Label("běžel \(loaded)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.stale)
                    // Jen to, co je jisté: detekce hlásí **jakoukoli** neshodu, takže tvrdit
                    // příčinu by bylo hádání vydávané za zjištění.
                    .help("Session si načetla jiný skill, než je nastavený (`\(lane.skill)`).")
            }
            Spacer(minLength: 8)
            // Přeskočený běh nic nestál (#518), a je to **jistota, ne odhad** — session se
            // nespustila. `RunUsage` na to není: tam nula znamená „tolik nahlásila session“.
            if case .skipped = lane.state {
                Text(verbatim: ReviewerLaneText.freeRun)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .monospacedDigit()
                    .help("Session se nespustila, takže tenhle reviewer nic nestál.")
            }
            if let usage = ReviewerLaneText.usage(of: lane) {
                Text(verbatim: usage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .monospacedDigit()
                    .help("Cena, trvání a počet kol modelu, jak je nahlásila session (`result` event).")
            }
            if let sessionID = lane.sessionID {
                resume(sessionID)
                // `▶` vedle `⧉`, ne místo něj (#453, potvrzeno #460): kdo si session pouští jinde
                // (iTerm, tmux, jiný stroj), potřebuje text, ne cizí plochu. Jsou to dvě akce, ne
                // dvě podoby jedné.
                if let resumeInDrawer { drawer(sessionID, action: resumeInDrawer) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Souhrn přírůstku a k němu cena proti prvnímu kolu (#517).
    ///
    /// Cena je **volitelná a `nil` se nedoplňuje**: `RunUsage` má všechna pole volitelná, protože
    /// zabitá session `result` event nepošle — nula by tvrdila, že běh byl zdarma.
    private func incrementLine(_ summary: String, saving: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: summary)
                .font(.callout)
                .foregroundStyle(Palette.ink2)
            if let saving {
                Text(verbatim: saving)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .monospacedDigit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Věta a `Pustit přesto` pod přeskočenou dráhou (#518).
    ///
    /// **Bez vlastního podkladu**, na rozdíl od bloku spadlé session: přeskočení není porucha, tak
    /// nemá co svítit. Tlačítko je `.bordered`, ne `.borderedProminent` — hlavní akce v tabu to
    /// není, jen cesta ven z rozhodnutí, které padlo správně.
    ///
    /// `rerun == nil` znamená „něco běží“, takže se tlačítko nekreslí — a **věta se s ním mění**:
    /// dvojtečka, za kterou nic nestojí, vypadá jako nedopsaný text (změřeno offscreen renderem).
    @ViewBuilder private func skippedBlock(_ patterns: [String]) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: ReviewerLaneText.runAnywayNote(hasButton: rerun != nil))
                .font(.callout)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let rerun {
                Button(ReviewerLaneText.runAnyway, systemImage: "play.circle", action: rerun)
                    .buttonStyle(.bordered)
                    .font(.caption)
                    .help(ReviewerLaneText.runAnywayHelp(patterns: patterns))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var statePill: some View {
        Text(verbatim: ReviewerLaneText.state(lane.state))
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(stateTint.opacity(0.15), in: .capsule)
            .foregroundStyle(stateTint)
    }

    private var stateTint: Color {
        switch lane.state {
        // Nejtišší z odznaků: nic se nestalo, takže nemá co přitahovat oko. `ink2` u `queued` je
        // proti tomu o odstín víc — tam se něco děje, jen ne tady.
        case .notStarted, .missingProgress: Palette.ink3
        // `ink2` jako `queued`, tedy neutrální kapsle `.pill.idle` z návrhu (sekce 46): není to
        // porucha ani výsledek. O odstín silnější než `nespuštěno` schválně — o tomhle
        // revieweerovi se **rozhodlo**, kdežto na ten druhý jen nedošlo.
        case .skipped: Palette.ink2
        case .queued, .stopped: Palette.ink2
        case .running: Palette.accent
        case .finished: Palette.ok
        case .timedOut, .interrupted: Palette.stale
        case .failed: Palette.crit
        }
    }

    /// Levná náhrada vestavěného terminálu: session se dá otevřít v tom svém.
    ///
    /// **Zůstává i vedle `▶`** (#453) a nejsou to dvě podoby jedné akce: kdo si session pouští
    /// jinde — v iTermu, v tmuxu, na jiném stroji —, potřebuje text, ne cizí okno.
    private func resume(_ sessionID: String) -> some View {
        Button("Zkopírovat resume", systemImage: "doc.on.doc") {
            Clipboard.copy(Policy.resumeCommand(sessionID: sessionID))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
        .help(ReviewerLaneText.copyResume(sessionID: sessionID))
    }

    /// Týž příkaz i s režimem povolení, rovnou puštěný — `▶` z návrhu, sekce 35, poznámka 112.
    ///
    /// **Od #460 míří do zásuvky, ne do `Terminal.app`**: session je odteď v okně, tak není důvod
    /// odcházet. Do #459 tady stálo, že vestavěný terminál to nebude, protože by se z okna dal
    /// spustit `gh pr merge` i `git push`; obojí je pořád pravda a rozhodnutí vyměnit tu záruku
    /// za funkci padlo u #459 — kapsle `plná práva` v hlavičce zásuvky to říká na obrazovce.
    private func drawer(_ sessionID: String, action: @escaping () -> Void) -> some View {
        Button(ReviewerLaneText.resumeInDrawer, systemImage: "play.fill", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .help(ReviewerLaneText.resumeInDrawerHelp(sessionID: sessionID))
    }

    // MARK: - Fáze

    /// Fáze v poměru, ne rovným dílem: `prochází kód` je to, v čem běh tráví většinu času, takže
    /// dostává nejvíc místa. Šířky počítá `ProportionalColumns`, aby se nevyjednávaly na každé
    /// úrovni (#220).
    private var phases: some View {
        ProportionalColumns(ratios: lane.phases.map(ratio(of:)), spacing: 3) {
            ForEach(lane.phases, id: \.self) { phase in
                phaseChip(phase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private func ratio(of phase: ReviewerLane.Phase) -> Double {
        phase.title == ReviewerLane.Title.code ? 2.6 : 1
    }

    private func phaseChip(_ phase: ReviewerLane.Phase) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: phase.title)
                .lineLimit(1)
            if let detail = phase.detail {
                Text(verbatim: detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let mark = mark(of: phase.state) {
                Image(systemName: mark).font(.system(size: 8))
            }
        }
        .font(.system(size: 10.5, weight: phase.state == .running ? .semibold : .regular))
        .foregroundStyle(tint(of: phase.state))
        .padding(.horizontal, 8)
        // Chip **vyplní svůj podíl** (`.ph { flex }`), jinak jsou mezi fázemi mezery a dráhy se
        // nedají porovnat — a porovnání je jediný důvod, proč fáze stojí vedle sebe. `.infinity`
        // je tady bezpečné (a #220 to nezakazuje): `ProportionalColumns` navrhuje **konkrétní**
        // šířku, takže se nevyjednává, jen se roztáhne na to, co dostal.
        .frame(maxWidth: .infinity)
        .frame(height: 23)
        .background(background(of: phase.state), in: .rect(cornerRadius: 5))
        .accessibilityElement(children: .combine)
        // Stav **té fáze**, ne celé dráhy: ten by u všech fází přečetl totéž.
        .accessibilityValue(ReviewerLaneText.phase(phase.state))
    }

    /// Značka za popiskem. **`idle` nemá žádnou** — fáze, na kterou nedošlo, není ani hotová,
    /// ani rozbitá, a jakýkoli symbol by o ní tvrdil, že se něco stalo. Totéž platí o `unknown`:
    /// tam se neví, jak dopadla, takže značka by si vybírala za nás.
    private func mark(of state: ReviewerLane.PhaseState) -> String? {
        switch state {
        case .done: "checkmark"
        case .failed: "xmark"
        case .stopped: "minus"
        case .running, .idle, .unknown: nil
        }
    }

    private func tint(of state: ReviewerLane.PhaseState) -> Color {
        switch state {
        case .done: Palette.ok
        case .running: Palette.find
        case .failed: Palette.crit
        case .stopped: Palette.stale
        case .idle, .unknown: Palette.ink3
        }
    }

    private func background(of state: ReviewerLane.PhaseState) -> Color {
        switch state {
        case .idle, .unknown: Palette.raised
        default: tint(of: state).opacity(0.16)
        }
    }

    // MARK: - Spadlá session

    /// Důvod, konec logu a co s tím.
    ///
    /// **`čisté` a `spadlo` se nesmí slít** — do #242 se v panelu lišily jen barvou odznaku, protože
    /// na důvod ani na `stderr` nebylo v kartě místo. Přes celou šířku je, takže je vidět, na čem
    /// to skončilo, i to, že nálezy z tohohle revieweera **nejsou žádné**.
    private func failureBlock(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session skončila chybou, takže z tohohle revieweera nálezy nejsou — což není totéž jako čisto.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // `stderr` celý a k vybrání: je to jediné, z čeho se pozná, co dělat dál.
            Text(verbatim: detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.chrome, in: .rect(cornerRadius: 6))
            HStack(spacing: 8) {
                if let rerun {
                    Button("Pustit znovu", systemImage: "arrow.clockwise", action: rerun)
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                }
                if let copyCommand {
                    Button("Zkopírovat příkaz", systemImage: "doc.on.doc", action: copyCommand)
                    .buttonStyle(.bordered)
                    .font(.caption)
                    // Nesmí to slibovat zápis toho, co běželo: `baseSha` i model se od minula
                    // mohly změnit, takže je to příkaz, jakým by se reviewer spustil teď.
                    .help("Zkopíruje příkaz, jakým by se tenhle reviewer spustil teď — k vložení do terminálu.")
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.crit.opacity(0.06))
        .overlay(alignment: .leading) { Rectangle().fill(Palette.crit).frame(width: 3) }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }
}
