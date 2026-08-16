import SwiftUI

/// Časový limit běhu revieweera v nastavení (#320) — číslo v minutách a **poznámka, když je
/// hodnota v souboru mimo meze**.
///
/// Jedno view pro obě místa, kde se limit nastavuje (globálně na stránce `Review a skilly`, per
/// repo na stránce `Repozitáře`): text o mezích má být jeden. Dvě formulace téhož by se rozešly
/// a z okna by nebylo poznat, že jde o totéž pravidlo.
///
/// **Číslo samotné se ořezává v poli** (`SettingsNumberField`), takže z okna se hodnota mimo meze
/// zapsat nedá. Dostat se tam ale může ručně editovaným `config.json` — a spolknout to nejde:
/// kdo si napíše 120 minut a poběží mu 60, má to vidět, ne se to dozvědět z chování. Text nese
/// **obojí** — co je v souboru a s čím se doopravdy poběží.
struct ReviewTimeoutField: View {
    let label: LocalizedStringKey
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsNumberField(
                label: label,
                value: $minutes,
                range: ReviewTimeout.allowedMinutes,
                step: 5
            )
            if let problem = Policy.reviewTimeoutProblem(in: minutes) {
                complaint(problem.reason)
            }
        }
    }

    /// Hodnota mimo meze. Stejná sazba jako u stížnosti v `ReviewPromptEditor` — je to tentýž
    /// druh sdělení („tohle se nepoužije tak, jak je to napsané“) a má se číst stejně.
    private func complaint(_ reason: String) -> some View {
        Label(reason, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.crit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
