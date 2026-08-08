import SwiftUI

/// Stavový řádek na spodku okna: co je špatně vlevo, dostupnost služeb vpravo.
///
/// **Jeden pruh, ne dva** (#31). Hlášky o stavu celé aplikace (rozbitá konfigurace,
/// pozastavený automat, nepřečtené soubory) do té doby visely ve vlastním pruhu; dvě místa
/// na tytéž hlášky znamenají, že se jedno z nich časem přestane plnit.
///
/// Na rozdíl od hlášek je řádek **trvalý** — puntík, který se ukáže jen při problému, je
/// puntík, o kterém nikdo neví, že existuje, a otázku „je to na mojí straně?“ pak nemá kde
/// zodpovědět.
///
/// Pozadí **musí být neprůhledné**: pruh sice místo vyhradí, ale průhledným obsahem
/// prosvítají řádky pod ním a texty se míchají do sebe (naraženo u #25).
struct StatusBarView: View {
    let store: AppStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppNoticesView(store: store)
            Spacer(minLength: 0)
            // Vlevo od útraty a puntíků: souhrn je o **práci**, ne o tom, jestli aplikace funguje.
            // `nil` = nemá se co sčítat (nenačtený seznam, prázdná fronta) — viz `queueSummary`.
            if let summary = store.queueSummary {
                QueueSummaryView(summary: summary)
            }
            // Vedle zvonku a puntíků, protože je to tatáž otázka „co mi to dělá“ — jen se ptá
            // na účet místo na dostupnost.
            if let spend = store.dailySpend {
                DailySpendView(spend: spend)
            }
            // Vlevo od puntíků služeb, protože odpovídá na tutéž otázku („funguje mi to?“),
            // ale službou není — proto zvonek, ne barevná tečka.
            NotificationStatusView(
                last: store.lastDeliveredNotification,
                isEnabled: store.configuration.global.notifications.isEnabled
            )
            ForEach(store.healthReports) { report in
                ServiceHealthDot(report: report)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        // `Divider()` v `overlay` se kreslí **svisle** — orientaci si bere z okolní osy
        // a v overlay žádná není.
        .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 1) }
    }
}

/// Puntík jedné služby. Po hoveru řekne, co se děje a kdy se to zjišťovalo — bez toho je to
/// dekorace.
struct ServiceHealthDot: View {
    let report: ServiceHealthReport

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(tint)
            Text(report.service.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .statusChip()
        .help(tooltip)
        // Puntík je barva a barva sama nestačí — popis nese celý stav i s důvodem.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(report.service.name) — \(report.state.label)")
        .accessibilityValue(tooltip)
    }

    /// Nezjištěno je **prázdné kolečko**, ostatní stavy plné. Šedá plná tečka je od zelené
    /// v úzkém pruhu k nerozeznání, a „nevím“ se nemá tvářit jako odpověď.
    private var symbol: String {
        report.state == .unknown ? "circle" : "circle.fill"
    }

    private var tint: Color {
        switch report.state {
        case .unknown: .secondary
        case .operational: .green
        case .incident: .yellow
        // Bez sítě je červená jako selhání — červená říká „nefunguje“, důvod říká věta.
        case .failing, .offline: .red
        }
    }

    private var tooltip: String {
        var lines = ["\(report.service.name) — \(report.state.label)", report.reason]
        if let call = report.call {
            lines.append(call.succeeded
                ? "Poslední volání prošlo v \(shortTime(call.since))."
                : "Nedaří se od \(shortTime(call.since)).")
        }
        if let checkedAt = report.checkedAt {
            lines.append("Stav služby zjišťován v \(shortTime(checkedAt)).")
        }
        return lines.joined(separator: "\n")
    }
}

/// Kdy se naposledy něco doopravdy ohlásilo (#138).
///
/// **Je vidět vždycky**, i když se ještě nic neohlásilo — ze stejného důvodu jako puntíky
/// služeb: indikátor, který se objeví teprve tehdy, když je co ukázat, je indikátor, o kterém
/// nikdo neví, že existuje, a po startu by se od rozbité aplikace nedal poznat.
///
/// Vidět je **jen čas**, celá věta je v nápovědě. Zadání #138 navrhovalo `naposledy ohlášeno
/// v 21:35` rovnou v řádku, ale ten je úzký a puntíky vedle drží tentýž vzor: krátký popisek
/// v řádku, detail po hoveru.
struct NotificationStatusView: View {
    let last: DeliveredNotification?
    /// Hlavní vypínač z nastavení (#86). Vypnuté notifikace jsou vlastní odpověď: „zatím nic“
    /// by u nich bylo pravda, ale poslalo by hledat poruchu, která žádná není.
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .statusChip()
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notifikace")
        .accessibilityValue(tooltip)
    }

    private var symbol: String {
        guard isEnabled else { return "bell.slash" }
        return last == nil ? "bell" : "bell.badge"
    }

    /// „Zatím nic“ se musí poznat od času — je to zadání #138. Prázdný popisek by obojí slil.
    private var label: String {
        guard isEnabled else { return "vypnuto" }
        guard let last else { return "zatím nic" }
        return shortTime(last.at)
    }

    private var tooltip: String {
        guard isEnabled else {
            return """
                Notifikace jsou vypnuté v nastavení, takže se nic neohlašuje.
                Zapnout je jde v Nastavení → Notifikace.
                """
        }
        guard let last else {
            // Že se čas počítá od spuštění, musí být v nápovědě: bez toho vypadá „zatím nic“
            // po restartu jako porucha, i když se včera ohlašovalo celý den.
            return """
                Od spuštění aplikace se nic neohlásilo.
                Nic se tím netvrdí o tom, jestli notifikace fungují — jen zatím nebylo co říct.
                """
        }
        return """
            Naposledy ohlášeno v \(shortTime(last.at)).
            \(last.title)
            """
    }
}

/// Co dneska stálo review (#148).
///
/// **V řádku je jen cena**, ne trvání ani počet kol. Součet trvání paralelních session totiž
/// neměří nic — tři desetiminutové běhy naráz by daly „30 minut“ za deset uplynulých — a počet
/// kol je trivia. Peníze jsou naopak číslo, které se jinde v aplikaci nedozvím vůbec, a kvůli
/// kterému #148 vzniklo.
///
/// **Vidět je vždycky**, i s nulou, ze stejného důvodu jako zvonek vedle: ukazatel, který se
/// objeví teprve tehdy, když je co ukázat, je ukazatel, o kterém nikdo neví, že existuje.
struct DailySpendView: View {
    let spend: DailySpend

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .statusChip()
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Útrata za dnešek")
        .accessibilityValue(tooltip)
    }

    /// `≥` u součtu, do kterého se nepodařilo započítat všechno — je to **dolní odhad**.
    /// Zabitý běh peníze stál taky, jen jeho cenu nikdo nenahlásil, a součet bez té značky by
    /// se tvářil jako úplný. Tatáž úvaha jako u `droppedFindings`.
    ///
    /// Ne `+` na konci, i když zkrácení jinde v okně značí `+N` (odznak u vlákna): tam je za
    /// znaménkem **číslo**, kdežto samotné `12,35 $+` vypadá jako překlep. `≥` říká „aspoň“
    /// a nic jiného znamenat nemůže.
    private var label: String {
        (spend.unknown > 0 ? "≥ " : "") + RunUsageText.cost(spend.cost)
    }

    private var tooltip: String {
        guard !spend.isEmpty else {
            return """
                Dneska zatím neskončilo žádné review, takže se nic neutratilo.
                Počítá se od půlnoci a přežije to restart.
                """
        }
        var lines = ["Za dnešek \(RunUsageText.cost(spend.cost)) ve \(Plural.czech(spend.runs, one: "běhu", few: "bězích", many: "bězích"))."]
        if spend.unknown > 0 {
            lines.append("""
                \(Plural.czech(spend.unknown, one: "Běh", few: "Běhy", many: "Běhů")) cenu \
                nenahlásily (zabité nebo přerušené), takže skutečná částka je vyšší.
                """)
        }
        lines.append("Ruční i automatická review dohromady; počítá se od půlnoci.")
        return lines.joined(separator: "\n")
    }
}

extension View {
    /// Tiché pozadí kolem položky stavového řádku (#179).
    ///
    /// Pruh nese vedle sebe pět až sedm údajů od různých věcí — fronta, útrata, notifikace,
    /// puntíky služeb — a bez ohraničení splývaly do jedné věty, ve které se hledalo, kde jeden
    /// končí a druhý začíná. Kapsle je **tichá schválně**: má oddělovat, ne přitahovat pozornost,
    /// protože pruh je trvalý a všechno v něm je běžný stav, ne upozornění.
    func statusChip() -> some View {
        padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.35), in: .capsule)
    }
}

/// Čas v jednom tvaru pro celý řádek. Dvě kopie by se rozešly a pruh by ukazoval dva různé
/// formáty vedle sebe.
private func shortTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

#Preview {
    VStack(spacing: 0) {
        Color.clear.frame(height: 40)
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            ServiceHealthDot(
                report: Policy.health(
                    of: .github,
                    from: HealthSignals(lastCall: ServiceCall(since: .now), pageCheckedAt: .now)
                )
            )
            ServiceHealthDot(
                report: Policy.health(
                    of: .claude,
                    from: HealthSignals(
                        lastCall: ServiceCall(since: .now, failure: "claude skončil s kódem 1."),
                        page: StatusPage(
                            watched: [StatusPageComponent(name: "Claude Code", status: "major_outage")],
                            missing: []
                        ),
                        pageCheckedAt: .now
                    )
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
    .frame(width: 520)
}
