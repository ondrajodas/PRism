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
            Text(verbatim: tickText)
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
    private func summarySentence(_ dashboard: Dashboard) -> String {
        guard dashboard.queue.pullRequests > 0 else {
            return store.lastSuccess == nil
                ? "Načítám frontu…"
                : "Fronta je prázdná — nikdo po tobě zrovna nechce review."
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

    /// Kdy se to naposledy načetlo a kdy se to zeptá znovu. Čas příštího tiku je **absolutní**,
    /// ne odpočet: odpočet by znamenal překreslovat dashboard každou vteřinu kvůli údaji, na
    /// který se nikdo nedívá.
    private var tickText: String {
        guard let last = store.lastSuccess else { return "zatím se nenačetlo" }
        var text = "poslední tik \(clock(last))"
        if let next = store.nextPoll { text += " · další tik \(clock(next))" }
        return text
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Karty

    private func cards(_ dashboard: Dashboard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            card(caption: "Ve frontě", value: "\(dashboard.queue.pullRequests)") {
                Text(verbatim: "napříč " + Plural.czech(
                    dashboard.queue.repositories,
                    one: "repozitářem",
                    few: "repozitáři",
                    many: "repozitáři"
                ))
            }
            card(
                caption: "Blokuje",
                value: "\(dashboard.blocking.pullRequests)",
                isAlarm: dashboard.blocking.pullRequests > 0
            ) {
                if let detail = dashboard.blocking.detail {
                    Text(verbatim: detail).lineLimit(1)
                } else {
                    Text("nic nezastavuje merge")
                }
            }
            card(
                caption: "Rozdělaná review",
                value: "\(dashboard.drafts.pullRequests)",
                hasAccentRail: dashboard.drafts.pullRequests > 0
            ) {
                draftsFoot(dashboard.drafts)
            }
            spendCard
        }
    }

    /// Věta pod počtem rozdělaných review. **Tři různé stavy, tři různá tvrzení**: draft z doby
    /// před #181 razítko nemá, a „nejstarší leží 0 minut“ by si ho vymyslelo.
    @ViewBuilder private func draftsFoot(_ drafts: Dashboard.DraftsCard) -> some View {
        if drafts.pullRequests == 0 {
            Text("nic nerozepsaného")
        } else if let oldest = drafts.oldest {
            Text("nejstarší leží \(oldest, format: .relative(presentation: .named))")
                .lineLimit(1)
        } else {
            Text("čeká na dopsání")
        }
    }

    /// Karta. `foot` je věta pod číslem — vždycky nějaká, protože prázdné místo pod velkým
    /// číslem vypadá jako chybějící údaj.
    private func card(
        caption: String,
        value: String,
        isAlarm: Bool = false,
        hasAccentRail: Bool = false,
        @ViewBuilder foot: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: caption.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Palette.ink3)
            Text(verbatim: value)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .monospacedDigit()
                .foregroundStyle(isAlarm ? Color.red : Palette.ink)
            foot()
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.chrome, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                // Návrh míchá červenou do barvy linky, ne přes pozadí: obrys má být vidět jako
                // varování, ne jako druhá čára navíc.
                .strokeBorder(isAlarm ? Color.red.mix(with: Palette.line, by: 0.6) : Palette.line, lineWidth: 1)
        }
        // Proužek nahoře jen u rozdělaných review — je to jediná karta, která mluví o **mojí**
        // práci, ne o tom, co přišlo zvenčí.
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

    /// Útrata za dnešek. **Nenačtená není nulová** — `0,00 $` by tvrdilo, že se dneska nic
    /// neutratilo, což je nad nepřečteným souborem to samé jako u nenačtené fronty. Značku `≥`
    /// u neúplného součtu skládá `RunUsageText`, tedy totéž místo jako ve stavovém řádku.
    private var spendCard: some View {
        card(caption: "Dneska stálo", value: store.dailySpend.map(RunUsageText.spent) ?? "—") {
            SpendSparkline(days: store.spendHistory)
        }
    }

    // MARK: - Dva sloupce

    private func columns(_ dashboard: Dashboard) -> some View {
        // Poměr z návrhu (`1.45fr 1fr`), ne pevná šířka: pravý sloupec drží legendu a akce,
        // a ty se v proužku číst nedají.
        ProportionalColumns(ratios: [1.45, 1], spacing: 16) {
            block("Fronta", more: "podle závažnosti") { queueRows }
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
    @ViewBuilder private var queueRows: some View {
        let entries = store.dashboardQueue
        if entries.isEmpty {
            Text(verbatim: RailSection.queue.emptyExplanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button { open(entry.id) } label: {
                        PullRequestRow(
                            pullRequest: entry.pullRequest,
                            reviewState: entry.state,
                            hasDraft: entry.hasDraft,
                            row: entry.row
                        )
                        // Vlevo nic: proužek stavu má sedět na hraně bloku, jak ho kreslí návrh.
                        .padding(.trailing, 13)
                        .padding(.vertical, 5)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if entry.id != entries.last?.id {
                        Rectangle().fill(Palette.lineSoft).frame(height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder private func reviewerLegend(_ reviewers: [ReviewerShareOfFindings]) -> some View {
        if reviewers.isEmpty {
            Text("Zatím neběžel žádný reviewer.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        } else {
            VStack(spacing: 9) {
                ForEach(reviewers) { share in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ReviewStateAppearance.color(of: share.findings > 0 ? .findings : .clean))
                            .frame(width: 8, height: 8)
                        Text(verbatim: share.reviewer)
                            .font(.system(size: 12))
                            .lineLimit(1)
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
