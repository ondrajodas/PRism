import SwiftUI

/// Potvrzení merge (#465) — poslední obrazovka před tím, než se něco stane `main`u.
///
/// **Dvě kliknutí, dvě různá tlačítka**, jako u odeslání review (#68): `Mergnout…` v panelu jen
/// otevře tenhle sheet, teprve tlačítko tady zavolá publisher. A **bez výchozí akce** — poslední
/// klik před nevratnou věcí je klik, ne `Enter` (tatáž úvaha jako #68 a #413).
///
/// Ochrana stojí na **úplném výpisu toho, co se stane**, ne na opisování jména repa: co se do čeho
/// slévá, jakou metodou, kolik commitů a s jakým titulkem. Kde ten výpis nemůže být úplný, je to
/// napsané — tělo squash commitu skládá GitHub ze slévaných commitů, takže se **neslibuje**, že je
/// tady vidět celé.
///
/// **Nebydlí v detailu PR, ale v `ContentView`** — tatáž past jako u `ReviewSubmission` a o stupeň
/// horší: mergnutý PR ze zdroje `author:@me` na příštím tiku **vypadne**, takže by se sheet
/// zavěšený na detailu ztratil zrovna nad hláškou, ze které se člověk dozví, jak to dopadlo.
struct MergeSheet: View {
    let submission: MergeSubmission
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { content.padding(16) }
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 300, idealHeight: 360)
        // Zavřít okno uprostřed volání by znamenalo nevědět, jestli se mergovalo. `gh` má
        // třicetivteřinový timeout, takže je to čekání ohraničené.
        .interactiveDismissDisabled(submission.state == .merging)
    }

    // MARK: - Hlavička

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mergnout pull request?")
                .font(.headline)
            // `verbatim` a ruční skládání: `Text("…#\(number)")` by číslo PR prohnalo locale
            // a z #21663 udělalo „#21 663“.
            Text(verbatim: submission.pullRequest.id.description)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Tohle se nedá vzít zpět z aplikace.")
                .font(.callout)
                .foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Co se stane

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Co se stane")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                row("větev", "\(plan.head) → \(plan.base)")
                // **Metoda z konstanty payloadu**, ne opsaná: kdyby to byl literál, dala by se
                // změnit v payloadu a v potvrzení by zůstalo staré slovo.
                row("metoda", MergeRequest.method)
                row("commitů", "\(plan.commits) → 1")
                row("titulek", plan.commitTitle)
                // Hlava je **podmínka volání**, ne údaj: na commit pushnutý mezi otevřením sheetu
                // a kliknutím odpoví GitHub `409` a nemergne nic. Patří to sem, protože je to
                // jediné místo, kde se dá zkontrolovat, **co** se mergne.
                row("hlava", String(plan.headSha.prefix(7)))
            }
            // **Co ve výpisu není, se přizná** — a stojí to **pod** celým výpisem, ne mezi jeho
            // řádky: je to věta o něm, ne další řádek. `commit_message` se neposílá, takže tělo
            // složí GitHub ze slévaných commitů, a věta „vypsané je všechno, co se stane“ by bez
            // tohohle tvrdila víc, než co je vidět.
            Text(verbatim: bodyNotice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ caption: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Text(verbatim: value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var plan: MergePlan { submission.plan }

    /// Věta o těle squash commitu. **Skloňuje se** — „ze zpráv 1 commitů“ je zrovna ta chyba,
    /// kvůli které `Plural.czech` existuje.
    private var bodyNotice: String {
        let commits = Plural.czech(plan.commits, one: "commitu", few: "commitů", many: "commitů")
        return "Tělo squash commitu složí GitHub ze zpráv \(commits)."
    }

    // MARK: - Patička

    private var footer: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 12)
            buttons
        }
        .padding(16)
    }

    @ViewBuilder private var status: some View {
        switch submission.state {
        case .ready:
            EmptyView()
        case .merging:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Merguju…").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: error.userDescription)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(Palette.crit)
                // Že se **nic nestalo**, musí být vidět — a stejně tak že to jisté není. Je to
                // tatáž dvojice vět jako u review a rozhoduje o ní `mightHaveReachedGitHub`,
                // takže věta a zakázané tlačítko říkají totéž.
                Text(verbatim: aftermath(of: error))
                    .font(.caption)
                    .foregroundStyle(error.mightHaveReachedGitHub ? Palette.find : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .merged(let merged):
            Label {
                Text(verbatim: "Mergnuto jako \(merged.sha.prefix(7)).")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(Palette.ok)
        }
    }

    private func aftermath(of error: PublishError) -> String {
        error.mightHaveReachedGitHub
            ? "Zkontroluj PR na GitHubu — nevím, jestli se mergovalo."
            : "Na pull requestu se nic nezměnilo."
    }

    @ViewBuilder private var buttons: some View {
        switch submission.state {
        case .merged:
            Link("otevřít na GitHubu", destination: submission.pullRequest.url)
                .font(.callout)
            Button("Zavřít", action: close)
                .keyboardShortcut(.cancelAction)
        default:
            Button("Zrušit", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(submission.state == .merging)
            mergeButton
        }
    }

    /// Tlačítko je pojmenované **akcí** a **není výchozí**: `.keyboardShortcut` na něm schválně
    /// žádný není, takže `Enter` nic nemergne. `.borderedProminent` je vzhled, ne klávesa.
    ///
    /// **Sheet se po úspěchu nezavírá sám**, na rozdíl od odeslaného review. Tam je za sheetem
    /// vidět, že review odešlo (draft zmizel z panelu i z řádku); tady PR ze seznamu teprve
    /// **vypadne**, takže by zavřený sheet nechal člověka koukat na tab, který se přestal kreslit,
    /// a jediná zpráva o výsledku by zmizela s ním.
    private var mergeButton: some View {
        // Popisek se skládá **do `String`u**, ne interpolací v literálu: literál by šel do
        // `LocalizedStringKey` a identifikátor PR by se v něm prohnal formátováním.
        Button(mergeLabel) {
            Task { await submission.merge() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!submission.canMerge)
    }

    /// Na tlačítku stojí **co se stane a s čím**, ne „OK“. Po selhání se text **nemění** na
    /// „Zkusit znovu“ — akce zůstává tatáž a to, že první pokus nevyšel, stojí vedle v patičce.
    private var mergeLabel: String { "Mergnout \(submission.pullRequest.id)" }
}
