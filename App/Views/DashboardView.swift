import SwiftUI

/// Startovní obrazovka (#181) — co dneska hoří.
///
/// Do #181 bylo po spuštění vidět „Vyber pull request“. Fronta přitom odpovídá na tři otázky —
/// kolik toho je, co blokuje a co jsem si nedodělal — a všechna ta čísla už v aplikaci byla,
/// jen roztroušená po stavovém řádku a po řádcích seznamu.
///
/// Rozměry a mezery jsou z návrhu doslova; kdo je mění, mění návrh.
struct DashboardView: View {
    @Bindable var store: AppStore
    /// Otevře PR jako záložku — kliknutí do fronty je tu hlavní pohyb.
    let open: (PRIdentifier) -> Void

    /// Ptá se potvrzení na hromadné spuštění. Jediná akce v okně, která z jednoho kliknutí
    /// utratí víc než jednu session, takže se u ní zastavíme.
    @State private var isConfirmingBulkRun = false

    /// Karta pod kurzorem (#371) — rozsvěcuje jí rámeček a šipku v akcentu.
    ///
    /// **`nil` je „nikde“, ne „`Dneska stálo`“**: karta bez cíle hover vůbec nehlásí, takže se do
    /// tohohle stavu nedostane a nemá čím zesvětlit rámeček.
    @State private var hoveredCard: DashboardCard?
    /// Patka bloku pod kurzorem (#371), klíčovaná sekcí, do které vede — dvě patky, dvě sekce.
    @State private var hoveredFooter: RailSection?

    var body: some View {
        // **Jednou za překreslení.** `Policy.dashboard` projde všechny záznamy i jejich běhy,
        // takže getter volaný z každé karty zvlášť by tu práci udělal osmkrát za sebou.
        let dashboard = store.dashboard
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                head(dashboard)
                cards(dashboard)
                columns(dashboard)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .background(Palette.surface)
        .confirmationDialog(bulkRunQuestion, isPresented: $isConfirmingBulkRun) {
            Button("Spustit") { store.startReviewsForNotReviewed() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Každé z nich utratí vlastní session Claude Code. Souběžně jich poběží \(store.configuration.global.maxConcurrentReviews), zbytek počká ve frontě.")
        }
    }

    // MARK: - Hlavička

    private func head(_ dashboard: Dashboard) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: greeting)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.5)
                Text(verbatim: summarySentence(dashboard))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            tick
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink3)
        }
    }

    /// Pozdrav podle denní doby. Je to jediné místo v aplikaci, které mluví na člověka —
    /// dashboard se otevírá jako první věc a „Fronta“ nad prázdnou obrazovkou zní jako chybová
    /// hláška.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<10: "Dobré ráno."
        case 10..<18: "Dobrý den."
        default: "Dobrý večer."
        }
    }

    /// Věta pod pozdravem. Skládá se z **toho, co je**, ne z šablony: nad prázdnou frontou by
    /// „0 pull requestů čeká, 0 blokuje“ znělo jako porucha, kdežto je to nejlepší možný stav.
    ///
    /// **Dvě věty od #332** — fronta a vlastní PR —, jak je kreslí návrh (sekce 21). Do #332 tu
    /// druhá chybět musela: dokud karta `Čeká na mě` počítala i vlastní PR, mluvily by obě věty
    /// o týchž pull requestech a rozpor mezi dvěma čísly v jedné hlavičce je horší než chybějící
    /// věta. Teď jsou to dvě různé množiny, takže se nemají o co přetahovat.
    ///
    /// **Nenačtená fronta druhou větu nedostane.** „Načítám frontu…“ je stav, ve kterém se o mojí
    /// práci nedá tvrdit nic — a nula nad nenačtenými daty je ta nebezpečná strana.
    private func summarySentence(_ dashboard: Dashboard) -> String {
        guard store.lastSuccess != nil else { return "Načítám frontu…" }
        return [queueSentence(dashboard), ownSentence(dashboard.mine)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// První věta — o frontě. Prázdná fronta je nejlepší možný stav, takže se o ní mluví takhle
    /// a ne nulou.
    private func queueSentence(_ dashboard: Dashboard) -> String {
        guard dashboard.queue.pullRequests > 0 else {
            return "Fronta je prázdná — nikdo po tobě zrovna nechce review."
        }
        // `Plural.czech` číslo píše samo, takže se před něj nesmí vypsat podruhé.
        var sentence = Plural.czech(
            dashboard.queue.pullRequests,
            one: "pull request čeká na review",
            few: "pull requesty čekají na review",
            many: "pull requestů čeká na review"
        )
        if dashboard.blocking.pullRequests > 0 {
            sentence += ", " + Plural.czech(
                dashboard.blocking.pullRequests,
                one: "z nich blokuje",
                few: "z nich blokují",
                many: "z nich blokuje"
            )
        }
        return sentence + "."
    }

    /// Druhá věta — o vlastních PR. `nil`, když na tah nečeká žádné: „na nula vlastních čeká tvůj
    /// tah“ je hlášení o ničem a pozdrav má být krátký.
    ///
    /// Mluví o **tahu**, ne o počtu otevřených PR, takže sedí s větou pod číslem na kartě
    /// `Moje PR` — a nemluví o „nálezech“, jak to má návrh: `awaitingMove` počítá i nevyřešená
    /// cizí vlákna, takže by to tvrdilo víc, než data unesou.
    ///
    /// Číslo se píše **číslicí**, i když návrh má „Na dvou vlastních“: zbytek okna čísla nevypisuje
    /// slovy (`napříč 4 repozitáři`, `2 mají co předat agentovi`) a dvě různá pravidla v jedné
    /// hlavičce by byla vidět.
    private func ownSentence(_ mine: Dashboard.MineCard) -> String? {
        guard mine.awaitingMove > 0 else { return nil }
        return "Na " + Plural.czech(
            mine.awaitingMove,
            one: "vlastním",
            few: "vlastních",
            many: "vlastních"
        ) + " je co předat agentovi."
    }

    /// Kdy se to naposledy načetlo a kolik zbývá do příštího tiku — `poslední tik 09:41 ·
    /// za 43s znovu`.
    ///
    /// **Odpočet, ne absolutní čas** (#237, otáčí rozhodnutí z #181). Námitka, kvůli které tu
    /// absolutní čas stál — že odpočet znamená překreslovat dashboard každou vteřinu — neplatí:
    /// vteřiny si odtiká `DashboardCountdown` sám ve svém `TimelineView`, a tělo dashboardu se
    /// u toho nepřepočítává.
    ///
    /// Cena je vidět tady: text se skládá ze **dvou kusů**, protože ten druhý musí zůstat
    /// samostatné view. Kdyby se odpočet vpsal do interpolace, ztratil by se ten mechanismus
    /// a vteřiny by tikaly jen tak často, jak se dashboard překresluje. Slova kolem čísla
    /// (`za … znovu`) drží `DashboardCountdown`, ne tenhle řetězec — bez mezery mezi číslem
    /// a jednotkou (#260).
    ///
    /// **Poslední tik zůstává absolutní** — je to bod v minulosti, na kterém se nic neodpočítává.
    @ViewBuilder private var tick: some View {
        switch DashboardTick(
            lastSuccess: store.lastSuccess,
            nextPoll: store.nextPoll,
            isRefreshing: store.isRefreshing,
            now: .now
        ) {
        case .never:
            Text("zatím se nenačetlo")
        case .idle(let last):
            Text(verbatim: "poslední tik \(clock(last))")
        case .countdown(let last, let deadline):
            HStack(spacing: 0) {
                Text(verbatim: "poslední tik \(clock(last)) · ")
                DashboardCountdown(deadline: deadline)
            }
        case .polling(let last):
            // Věta o tom, co se děje, ne odpočet přes nulu. Do „ptám se…“ se to překlopí ve
            // chvíli, kdy dotaz opravdu začne — příznak v `PollState` je observovatelný,
            // kdežto hodiny ve `now` výš platí jen k poslednímu přepočtu.
            Text(verbatim: last.map { "poslední tik \(clock($0)) · ptám se…" } ?? "ptám se…")
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Karty

    /// Pět karet (#331). **`Ve frontě` se jmenuje `Čeká na mě`**, protože s vlastními PR by staré
    /// jméno mluvilo o dvou různých druzích práce naráz — a popisek pod číslem má říkat, čí je tah.
    ///
    /// **Čtyři z pěti vedou do své sekce** (#371); `Dneska stálo` nikam, protože nemá kam. Kam která
    /// vede, rozhoduje `Policy.destination(of:)` — proto se karta identifikuje výčtem, ne popiskem.
    private func cards(_ dashboard: Dashboard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            card(.queue, caption: "Čeká na mě", value: "\(dashboard.queue.pullRequests)") {
                Text(verbatim: "napříč " + Plural.czech(
                    dashboard.queue.repositories,
                    one: "repozitářem",
                    few: "repozitáři",
                    many: "repozitáři"
                ))
            }
            card(
                .blocking,
                caption: "Blokuje",
                value: "\(dashboard.blocking.pullRequests)",
                isAlarm: dashboard.blocking.pullRequests > 0
            ) {
                if let detail = dashboard.blocking.detail {
                    Text(verbatim: detail)
                } else {
                    Text("nic nezastavuje merge")
                }
            }
            card(
                .mine,
                caption: "Moje PR",
                value: "\(dashboard.mine.pullRequests)",
                hasAccentRail: dashboard.mine.pullRequests > 0
            ) {
                mineFoot(dashboard.mine)
            }
            card(
                .drafts,
                caption: "Rozdělaná review",
                value: "\(dashboard.drafts.pullRequests)"
            ) {
                draftsFoot(dashboard.drafts)
            }
            spendCard
        }
    }

    /// Věta pod počtem vlastních PR. **Tři různé stavy, tři různá tvrzení** — jako u rozdělaných.
    ///
    /// Nesledovaný zdroj se **nesmí** slít s „nic k předání“: nula bez zdroje je údaj o nastavení,
    /// ne o mojí práci, a uklizený stůl nad nenastavenou aplikací je ta nejhorší možná odpověď
    /// (viz `Dashboard.MineCard.isTracked`).
    @ViewBuilder private func mineFoot(_ mine: Dashboard.MineCard) -> some View {
        if !mine.isTracked {
            Text("zdroj vlastních PR chybí v nastavení")
        } else if mine.awaitingMove == 0 {
            Text("nic nečeká na tvůj tah")
        } else {
            Text(verbatim: Plural.czech(
                mine.awaitingMove,
                one: "má co předat agentovi",
                few: "mají co předat agentovi",
                many: "má co předat agentovi"
            ))
        }
    }

    /// Věta pod počtem rozdělaných review. **Tři různé stavy, tři různá tvrzení**: draft z doby
    /// před #181 razítko nemá, a „nejstarší leží 0 minut“ by si ho vymyslelo.
    @ViewBuilder private func draftsFoot(_ drafts: Dashboard.DraftsCard) -> some View {
        if drafts.pullRequests == 0 {
            Text("nic nerozepsaného")
        } else if let oldest = drafts.oldest {
            Text("nejstarší leží \(oldest, format: .relative(presentation: .named))")
        } else {
            Text("čeká na dopsání")
        }
    }

    /// Karta. `foot` je věta pod číslem — vždycky nějaká, protože prázdné místo pod velkým
    /// číslem vypadá jako chybějící údaj.
    ///
    /// **Klikatelná je jen ta, která má kam vést** (#371). Karta bez cíle nedostane ani tlačítko,
    /// ani šipku, ani ukazováček, ani hover — karta, po které se nic nestane, je lež o tom, co okno
    /// umí, a `cursor: pointer` je z toho ta nejtišší část.
    @ViewBuilder private func card(
        _ card: DashboardCard,
        caption: String,
        value: String,
        isAlarm: Bool = false,
        hasAccentRail: Bool = false,
        @ViewBuilder foot: () -> some View
    ) -> some View {
        let destination = Policy.destination(of: card)
        let face = face(
            card,
            caption: caption,
            value: value,
            isAlarm: isAlarm,
            hasAccentRail: hasAccentRail,
            isClickable: destination != nil,
            foot: foot
        )
        if let destination {
            Button { store.show(destination) } label: { face }
                .buttonStyle(.plain)
                // `pointerStyle`, ne `NSCursor.push()`/`pop()` — když view zmizí uprostřed hoveru,
                // druhá půlka páru se nikdy nezavolá; tatáž úvaha jako v `AccentLinkButtonStyle`.
                .pointerStyle(.link)
                // Zápis jen na změnu, jako v `PullRequestTabBar`: odchod z karty nesmí přepsat
                // hover, který si mezitím vzala sousední.
                .onHover { hoveredCard = $0 ? card : (hoveredCard == card ? nil : hoveredCard) }
                .help(destination.help)
        } else {
            face
        }
    }

    /// Kresba karty. Vyčleněná z `card(_:…)`, aby se dala položit do tlačítka i vedle něj beze
    /// změny — jinak by klikatelná a neklikatelná karta byly dvě podoby jedné věci.
    private func face(
        _ card: DashboardCard,
        caption: String,
        value: String,
        isAlarm: Bool,
        hasAccentRail: Bool,
        isClickable: Bool,
        @ViewBuilder foot: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: caption.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Palette.ink3)
                // **Šipka si drží místo, nekreslí se přes popisek** (#371). V návrhu je šipka
                // absolutně umístěná, takže by se v užším okně `ROZDĚLANÁ REVIEW` zalomilo pod ni —
                // a s tím by narostla výška celé řady karet. Jeden řádek je tatáž úvaha jako u věty
                // pod číslem (#331): popisek je popisek, co se nevejde, se zkrátí.
                .lineLimit(1)
                .padding(.trailing, isClickable ? Self.arrowRoom : 0)
            Text(verbatim: value)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .monospacedDigit()
                .foregroundStyle(isAlarm ? Color.red : Palette.ink)
            foot()
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                // **Jeden řádek, a je to tady, ne u každé věty** (nález Copilota na #331). Do #331
                // si `lineLimit(1)` nasazovaly jen některé věty, takže se karta v úzkém okně
                // zlomila právě v tom stavu, který ho zapomněl — a s ní i výška celé řady karet.
                // Věta pod číslem je popisek, ne odstavec; co se nevejde, se zkrátí.
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.chrome, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                // Návrh míchá červenou do barvy linky, ne přes pozadí: obrys má být vidět jako
                // varování, ne jako druhá čára navíc.
                .strokeBorder(border(card, isAlarm: isAlarm, isClickable: isClickable), lineWidth: 1)
        }
        // Šipka vpravo nahoře (`.card.go .goto`) — jediný trvalý signál, že karta někam vede;
        // rámeček v akcentu je až na hover. Kreslí se **jen u karty s cílem**, ne u všech.
        .overlay(alignment: .topTrailing) {
            if isClickable {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(hoveredCard == card ? Palette.accent : Palette.ink3)
                    // `top: 12`, `right: 13` z návrhu (`.card.go .goto`).
                    .padding(.top, 12)
                    .padding(.trailing, 13)
            }
        }
        // Proužek nahoře jen u karty `Moje PR` (#331). Do té doby ho měla `Rozdělaná review` jako
        // „jediná karta, která mluví o mojí práci“ — od #331 to není pravda a návrh (sekce 21) ho
        // překreslil právě takhle: dva akcentové proužky vedle sebe by přestaly znamenat, která
        // karta je ta o mně.
        .overlay(alignment: .top) {
            if hasAccentRail {
                LinearGradient(
                    colors: [Palette.accent, Palette.accent2],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Barva obrysu karty. **Hover přebíjí alarm**, jak to má návrh (`.card.go:hover` má vyšší
    /// specificitu než `.card.alarm`): pod kurzorem je červená karta pořád ta, na kterou se dá
    /// kliknout, a dvě barvy naráz obrys nakreslit neumí.
    ///
    /// Na `isClickable` se ptá **i tady**, ne jen u šipky: karta bez cíle hover nehlásí, takže by se
    /// do toho stavu neměla jak dostat — ale spoléhat se na to znamená, že by ji rozsvítil první, kdo
    /// ten zápis přidá jinde. Pravidlo „`Dneska stálo` nemá hover stav“ patří k obrysu, ne k zapisovateli.
    private func border(_ card: DashboardCard, isAlarm: Bool, isClickable: Bool) -> Color {
        if isClickable, hoveredCard == card { return Palette.accent }
        return isAlarm ? Color.red.mix(with: Palette.line, by: 0.6) : Palette.line
    }

    /// Kolik místa si šipka bere z popisku karty: `12` bodů glyfu a `13` odsazení z návrhu, tedy
    /// dost na to, aby se popisek zkrátil dřív, než se pod ni dostane.
    private static let arrowRoom = 25.0

    /// Útrata za dnešek. **Nenačtená není nulová** — `0,00 $` by tvrdilo, že se dneska nic
    /// neutratilo, což je nad nepřečteným souborem to samé jako u nenačtené fronty. Značku `≥`
    /// u neúplného součtu skládá `RunUsageText`, tedy totéž místo jako ve stavovém řádku.
    private var spendCard: some View {
        card(.spend, caption: "Dneska stálo", value: store.dailySpend.map(RunUsageText.spent) ?? "—") {
            SpendSparkline(days: store.spendHistory)
        }
    }

    // MARK: - Dva sloupce

    private func columns(_ dashboard: Dashboard) -> some View {
        // Poměr z návrhu (`1.45fr 1fr`), ne pevná šířka: pravý sloupec drží legendu a akce,
        // a ty se v proužku číst nedají.
        ProportionalColumns(ratios: [1.45, 1], spacing: 16) {
            // **Dva bloky pod sebou, ne jeden** (#331): u cizího PR je moje práce přečíst
            // a odpovědět, u vlastního opravit a pushnout. Mezera 16 je z návrhu (`gap: 16px`),
            // tedy jiná než 12 uvnitř pravého sloupce.
            VStack(spacing: 16) {
                block("Čeká na moje review", more: "podle závažnosti") { queueRows }
                block("Moje PR") { ownRows }
            }
            VStack(spacing: 12) {
                block("Nálezy podle reviewera", more: "7 dní") { reviewerLegend(dashboard.reviewers) }
                block("Co teď") { actions(dashboard.drafts.pullRequest) }
            }
        }
    }

    /// Blok s hlavičkou. `more` je popisek vpravo v hlavičce — v návrhu je to odkaz, tady
    /// **jen popisek**: obojí, co by pod ním bylo (jiné řazení, jiné okno), je vlastní issue,
    /// a šipka nad akcí, která nikam nevede, je horší než žádná.
    private func block(
        _ title: String,
        more: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: title)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                if let more {
                    Text(verbatim: more)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
            content()
        }
        .background(Palette.chrome, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Fronta v dashboardu je **týž řádek jako v seznamu** (#172), ne druhá varianta: dvě
    /// podoby téhož by se rozešly a člověk by se v jedné z nich hledal. Pořadí je ale jiné —
    /// podle závažnosti, ne podle času (`Policy.byUrgency`).
    ///
    /// **Jen cizí PR** (#332), tedy tatáž množina jako karta `Čeká na mě`. Do #332 tu byl celý
    /// seznam a vlastní PR byl na dashboardu vidět dvakrát.
    ///
    /// **Nejvýš pět řádků** (#371) — strop i patku skládá `Policy.dashboardBlock`, tady se jen
    /// kreslí. Karta `Čeká na mě` nad blokem počítá dál celou frontu: strop je o kresbě.
    @ViewBuilder private var queueRows: some View {
        rows(
            Policy.dashboardBlock(store.dashboardQueue, of: .theirs),
            emptyExplanation: RailSection.queue.emptyExplanation
        )
    }

    /// Moje PR v dashboardu (#331) — **tytéž řádky, jen druhá množina**, seřazené stejnou
    /// funkcí. Prázdný stav mluví o vlastní práci, ne o frontě; že chybí zdroj nebo login, řekne
    /// sekce v railu (`Policy.ownListEmptyReason`) — na kartě to nese věta pod číslem.
    @ViewBuilder private var ownRows: some View {
        rows(
            Policy.dashboardBlock(store.dashboardOwnPullRequests, of: .mine),
            emptyExplanation: RailSection.mine.emptyExplanation
        )
    }

    @ViewBuilder private func rows(_ block: DashboardBlock, emptyExplanation: String) -> some View {
        if block.rows.isEmpty {
            Text(verbatim: emptyExplanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        } else {
            let entries = block.rows
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    let ownership = store.ownership(of: entry.pullRequest)
                    // Kolik zbývá předat (#334) a co od minule přibylo (#335) — **jeden report**,
                    // tatáž otázka jako u odznaku v railu, takže i tatáž funkce; jinak by blok tvrdil
                    // jiné číslo než rail vedle. **Jen u vlastních PR**: skládá položky zadání a
                    // u cizího řádku se nekreslí ani pilulka, ani novinky, takže by to byla práce za
                    // odpověď, kterou nikdo nepřečte — a oba bloky kreslí týž
                    // `rows(_:emptyExplanation:)`.
                    let handoff = ownership == .mine ? store.handoffReport(for: entry.id) : .never
                    Button { open(entry.id) } label: {
                        PullRequestRow(
                            pullRequest: entry.pullRequest,
                            reviewState: entry.state,
                            hasDraft: entry.hasDraft,
                            row: entry.row,
                            // Čte se **tady**, ne v řádku: řádek store nemá. Vlastní PR má vpravo
                            // `Prompt →` (#331), ať je v kterémkoli z obou bloků.
                            ownership: ownership,
                            // Akce od #333, tatáž jako v seznamu. Celý řádek je tu `Button`, který
                            // PR otevírá — takže i kdyby klik spadl na řádek pod tlačítkem, vede to
                            // na týž PR, jen bez rozloženého panelu. Němá akce z toho nevznikne.
                            openPrompt: { store.openAgentPrompt(in: entry.id) },
                            pending: handoff.pending,
                            activity: handoff.activity
                        )
                        // Vlevo nic: proužek stavu má sedět na hraně bloku, jak ho kreslí návrh.
                        .padding(.trailing, 13)
                        .padding(.vertical, 5)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if entry.id != entries.last?.id { separator }
                }
                if let footer = block.footer {
                    // **Čára je tady, a jedna** (#371): patka svou vlastní horní linku nemá, protože
                    // by se sečetla s tou pod posledním řádkem. V mockupu z toho bylo 1 px + 1 px
                    // = 2 px (změřeno sondou nad `getComputedStyle`), tady by to bylo totéž.
                    separator
                    footerRow(footer)
                }
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(Palette.lineSoft).frame(height: 1)
    }

    /// Patka bloku (`.block > .more-rows`) — `Zobrazit všech 13 ve frontě +8 →`.
    ///
    /// **Není to řádek fronty**, jen cesta do ní: nekreslí se jako `PullRequestRow`, nepočítá se do
    /// řádků bloku a vede tam, kam karta nad blokem. Text i počet skládá `Policy`, tady se kreslí.
    private func footerRow(_ footer: DashboardBlock.Footer) -> some View {
        Button { store.show(.section(footer.section)) } label: {
            HStack(spacing: 6) {
                Text(verbatim: footer.title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(verbatim: footer.rest)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
            }
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            // Hover je `Palette.raised` = `--panel-3` v návrhu. Do #384 tam stálo nedefinované
            // `var(--hover)`, takže hodnota se z návrhu vzít nedala a vybral ji tenhle řádek;
            // od #384 je návrh srovnaný na `--panel-3` a shoda je jedna ku jedné.
            .background(hoveredFooter == footer.section ? Palette.raised : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover {
            hoveredFooter = $0 ? footer.section : (hoveredFooter == footer.section ? nil : hoveredFooter)
        }
        // Nápověda jde přes `DashboardDestination`, ne vlastní větou: patka vede tam, kam karta nad
        // blokem, takže má i říkat totéž.
        .help(DashboardDestination.section(footer.section).help)
    }

    @ViewBuilder private func reviewerLegend(_ reviewers: [ReviewerShareOfFindings]) -> some View {
        if reviewers.isEmpty {
            Text("Zatím neběžel žádný reviewer.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        } else {
            // Zkrácená jména (#182): `superpowers:requesting-code-review` se do sloupce nevejde
            // a zalomí legendu na dva řádky. Celé id zůstává v nápovědě.
            let names = Policy.shortReviewerNames(of: reviewers.map(\.reviewer))
            VStack(spacing: 9) {
                ForEach(reviewers) { share in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2)
                            // Nula zeleně **jen když je z čeho soudit** (#383): reviewer, který
                            // v okně neměl jediný průkazný běh, dostane šedou jako díl proužku
                            // u řádku — zelený puntík vedle nuly je tvrzení o čistotě.
                            .fill(ReviewStateAppearance.color(of: Self.legendOutcome(of: share)))
                            .frame(width: 8, height: 8)
                        Text(verbatim: names[share.reviewer] ?? share.reviewer)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .help(share.reviewer)
                        Spacer(minLength: 8)
                        Text(verbatim: "\(share.findings)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Palette.ink2)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
        }
    }

    /// Barva puntíku v legendě reviewerů — **tatáž škála jako díl proužku u řádku** (#383), aby
    /// dashboard a fronta netvrdily o jednom reviewerovi každý něco jiného.
    ///
    /// `nonisolated static`, ať se to dá otestovat bez kreslení: je to jediný `if` nad tím, co
    /// legenda ukazuje, a přesně ten se u #383 pletl.
    nonisolated static func legendOutcome(of share: ReviewerShareOfFindings) -> ReviewerShare.Outcome {
        if share.findings > 0 { return .findings }
        return share.isConclusive ? .clean : .inconclusive
    }

    // MARK: - Co teď

    /// Akce, které dávají smysl **teď** — a jen ty. Řádek na akci, která by nic neudělala
    /// („pustit review na nic“), by z bloku udělal seznam možností, ne návrh dalšího kroku.
    @ViewBuilder private func actions(_ draft: PRIdentifier?) -> some View {
        let notReviewed = store.pullRequestsNotReviewed.count
        if notReviewed == 0 && draft == nil {
            Text("Nic nečeká — fronta je vyřízená.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        } else {
            VStack(spacing: 0) {
                if notReviewed > 0 {
                    action(
                        symbol: "play.fill",
                        title: "Pustit review na vše, co neběželo",
                        shortcut: "⌘⇧R",
                        key: KeyEquivalent("r"),
                        isLast: draft == nil
                    ) { isConfirmingBulkRun = true }
                }
                if let draft {
                    action(
                        symbol: "square.and.pencil",
                        title: "Dopsat review pro \(draft.repo.name)#\(draft.number)",
                        shortcut: "⌘⇧D",
                        key: KeyEquivalent("d"),
                        isLast: true
                    ) { open(draft) }
                }
            }
        }
    }

    /// Jeden řádek akce. Zkratka je opravdová (`keyboardShortcut`), ne jen nakreslený chip —
    /// popiska klávesy, která nic nedělá, je lež o tom, co okno umí.
    private func action(
        symbol: String,
        title: String,
        shortcut: String,
        key: KeyEquivalent,
        isLast: Bool,
        run: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: run) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                        .frame(width: 18)
                    Text(verbatim: title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: shortcut)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line, lineWidth: 1)
                        }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: [.command, .shift])
            if !isLast {
                Rectangle().fill(Palette.lineSoft).frame(height: 1)
            }
        }
    }

    private var bulkRunQuestion: String {
        let count = store.pullRequestsNotReviewed.count
        return "Spustit review na " + Plural.czech(
            count,
            one: "pull requestu",
            few: "pull requestech",
            many: "pull requestech"
        ) + "?"
    }
}

/// Sloupcový graf útraty za posledních pár dní (#181).
///
/// **Dnešek je zvýrazněný**, ostatní dny jsou tlumené: karta mluví o dnešku a graf je kontext,
/// ne druhé číslo. Den bez útraty zůstává v řadě jako **čárka o jednom bodu** — nulová výška by
/// z něj udělala prázdné místo a sloupce by přestaly znamenat dny.
struct SpendSparkline: View {
    let days: [DaySpend]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days) { day in
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(Palette.accent)
                    .opacity(day.id == days.last?.id ? 1 : 0.45)
                    .frame(height: height(of: day))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.fullHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Útrata za posledních \(days.count) dní")
    }

    /// Výška podle nejdražšího dne v okně. Kdyby se škálovalo podle absolutní částky, byl by
    /// graf u levného týdne plochý a nedalo by se z něj nic přečíst.
    ///
    /// **Podlaha je jeden bod, ne nula** — i den, ve kterém se neutratilo nic, musí být v řadě
    /// vidět, jinak se nedá spočítat, kolikátý zleva je dnešek.
    private func height(of day: DaySpend) -> Double {
        let peak = days.map(\.spend.cost).max() ?? 0
        guard peak > 0 else { return Self.floorHeight }
        return max(Self.floorHeight, Self.fullHeight * day.spend.cost / peak)
    }

    private static let fullHeight = 26.0
    private static let floorHeight = 1.0
}
