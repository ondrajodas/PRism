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
                ? "Poslední volání prošlo v \(time(call.since))."
                : "Nedaří se od \(time(call.since)).")
        }
        if let checkedAt = report.checkedAt {
            lines.append("Stav služby zjišťován v \(time(checkedAt)).")
        }
        return lines.joined(separator: "\n")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
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
