import SwiftUI

/// Tab `Průběh` (#242, `.lanes`): dráha na revieweera, ne sloupec karet pod sebou.
///
/// **Nahrazuje `ReviewTimelineView`**, který kreslil jeden dlouhý seznam událostí přes všechny
/// reviewery. Ten odpovídal na „co se dělo“, ale ne na „kdo kde je“ — a v panelu o 300 bodech se
/// z něj nedalo přečíst ani jedno. Události zůstávají, jen se z hlavního obsahu staly podrobnosti
/// pod rozbalením každé dráhy.
struct ReviewProgressView: View {
    let lanes: [ReviewerLane]
    /// Pustí jednoho revieweera znovu (#149). `nil` = nejde to, typicky protože něco běží.
    var rerun: ((String) -> Void)?
    /// Zkopíruje do schránky příkaz, jakým by se ten reviewer spustil teď. `nil` = neví se, proti
    /// čemu se diffuje, takže by příkaz nebyl spustitelný a tlačítko se nekreslí.
    var copyCommand: ((String) -> Void)?
    /// Otevře přepis surové session té dráhy (#327). `nil` = odsud se to neotevírá.
    ///
    /// Cíl skládá **`Policy`, ne view** (`Policy.rawSessionTarget(of:slug:)`): rozhodnutí „bez
    /// `session_id` a bez pracovního stromu tlačítko není“ je pravidlo, ne `if` v kresbě.
    var showRawSession: ((RawSessionTarget) -> Void)?
    /// Pustí session té dráhy v zásuvce s terminálem (#453, #460). `nil` = odsud se to nepouští —
    /// ať už proto, že to volající neumí, nebo že v okně žádná zásuvka není.
    ///
    /// Cíl skládá **`Policy`, ne view** (`Policy.terminalSession(of:)`), ze stejného důvodu jako
    /// u `showRawSession`: „bez `session_id` a bez pracovního stromu tlačítko není“ je pravidlo.
    var resumeInDrawer: ((TerminalSession) -> Void)?
    /// Pustí **celé** odložené review teď (#519). `nil` = nejde to (něco běží), nebo to volající
    /// neumí. Bez parametru na dráhu, protože odklad platí na celý běh — viz `ReviewerLaneView`.
    var runNow: (() -> Void)?
    /// „Teď“ pro větu `poběží 23:00` (#519). **Předává se od storu** (`AppStore.time`), aby se
    /// dráha nemohla rozejít s hodinami, ze kterých se o odkladu rozhodovalo. Výchozí `Date()` je
    /// jen pro sondy a náhledy — v aplikaci ho přebíjí `ReviewProgressView`.
    var now = Date()
    /// `owner/repo#412` do podtitulku sheetu.
    var slug = ""

    /// Které dráhy mají rozbalený výpis kroků (#325).
    ///
    /// **Patří to tabu, ne dráze**: dráhy jsou v `LazyVStack`u, takže `@State` uvnitř `ReviewerLaneView`
    /// se odrolováním zahodí a výpis by se sám zavřel — u běžícího revieweera tedy zrovna tam, kam
    /// se člověk díval. Klíčem je jméno skillu, jako u všeho ostatního v tabu, takže to **smí**
    /// přetéct mezi pull requesty; je to tatáž úvaha jako u `mutedReviewers` v detailu PR.
    ///
    /// Přepnutím tabu se to zapomene, a to je v pořádku: běžící dráha se rozbalí sama a jediné, co
    /// se tím ztratí, je ručně otevřený výpis doběhlé dráhy — jeden klik. Do storu to proto nepatří.
    @State private var expansion = StepFeedExpansion()

    /// Zkrácená jména reviewerů. Počítá se z **celé** sady naráz, protože zkrátit se smí jen to,
    /// co zůstane jednoznačné vůči ostatním.
    private var shortNames: [String: String] {
        Policy.shortReviewerNames(of: lanes.map(\.skill))
    }

    /// Kdo právě běží. **Jediné, na co se automatické rozbalení váže** — proto se z toho počítá
    /// klíč pro `onChange`, ne z celých drah: ty se mění při každé události, kdežto tohle jen
    /// tehdy, když někdo začne nebo skončí.
    private var runningSkills: Set<String> {
        Set(lanes.filter { $0.state == .running }.map(\.skill))
    }

    var body: some View {
        Group {
            if lanes.isEmpty {
                empty
            } else {
                ScrollView {
                    content
                }
            }
        }
        // `initial: true` kvůli prvnímu otevření tabu při běžícím review: bez něj by se výpis
        // rozbalil teprve tehdy, až někdo doběhne nebo začne.
        .onChange(of: runningSkills, initial: true) { _, _ in
            expansion = Policy.stepFeedExpansion(expansion, lanes: lanes)
        }
    }

    /// Dráhy bez `ScrollView`u — **`internal` schválně, kvůli měření** (#294), stejně jako
    /// u `OverviewView` (#291): `NSScrollView` si obsah na svou šířku ukrojí, takže by se přesah
    /// nenakreslil a rozbitá šířka by od opravené nešla poznat. Prázdný stav ve scrollu není,
    /// takže se měří přímo z `body`.
    @ViewBuilder var content: some View {
        LazyVStack(alignment: .leading, spacing: 11) {
            ForEach(lanes) { lane in
                ReviewerLaneView(
                    lane: lane,
                    shortName: shortNames[lane.skill] ?? lane.skill,
                    rerun: rerun.map { rerun in { rerun(lane.skill) } },
                    copyCommand: copyCommand.map { copy in { copy(lane.skill) } },
                    feed: Policy.stepFeed(of: lane, expansion: expansion),
                    toggleFeed: { expansion = Policy.toggledStepFeed(expansion, of: lane.skill) },
                    showRawSession: rawSession(of: lane),
                    resumeInDrawer: drawer(of: lane),
                    // Jen na odložené dráze: `runNow` je akce nad **celým** během, takže by se
                    // pod doběhlou dráhou nakreslilo tlačítko, které s ní nemá co dělat.
                    runNow: lane.isDeferred ? runNow : nil,
                    now: now
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Akce, která dráze otevře přepis surové session. `nil` = není co otevřít.
    private func rawSession(of lane: ReviewerLane) -> (() -> Void)? {
        guard let showRawSession, let target = Policy.rawSessionTarget(of: lane, slug: slug) else {
            return nil
        }
        return { showRawSession(target) }
    }

    /// Akce, která dráze pustí session v zásuvce (#453, #460). `nil` = není co obnovit.
    private func drawer(of lane: ReviewerLane) -> (() -> Void)? {
        guard let resumeInDrawer, let session = Policy.terminalSession(of: lane) else {
            return nil
        }
        return { resumeInDrawer(session) }
    }

    /// **Ne `ContentUnavailableView`** (#182): ten se vystředí, nadpis vysází na velikost titulku
    /// a nad text vloží prázdno přes půl okna. Je to vysvětlivka — patří nahoru a drobným písmem.
    ///
    /// Věta říká **nastavení, ne „zatím se nic nedělo“**: od té doby, co dráhu dostane každý
    /// nastavený reviewer, se sem dá dojít jedině s prázdnou sadou skillů. „Zatím se nic nedělo“ by
    /// nad prázdným nastavením vypadalo jako čekání na běh, který se nemá čím spustit.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pro tohle repo není nastavený žádný reviewer.")
            Text("Dráha se kreslí na každý skill z nastavené sady. Dokud je prázdná, není co spustit ani co ukazovat — sada se mění v nastavení, globálně nebo jen pro tohle repo.")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}
