import SwiftUI

/// Potvrzení merge (#465) — poslední obrazovka před tím, než se něco stane `main`u.
///
/// **Dvě kliknutí, dvě různá tlačítka**, jako u odeslání review (#68): `Mergnout…` v panelu jen
/// otevře tenhle sheet, teprve tlačítko tady zavolá publisher. A **bez výchozí akce** — poslední
/// klik před nevratnou věcí je klik, ne `Enter` (tatáž úvaha jako #68 a #413).
///
/// Ochrana stojí na **úplném výpisu toho, co se stane**, ne na opisování jména repa: co se do čeho
/// slévá, jakou metodou, kolik commitů a s jakým titulkem. Kde ten výpis nemůže být úplný, je to
/// napsané — tělo commitu skládá GitHub, takže se **neslibuje**, že je tady vidět celé; od #556 se
/// ale říká **z přečteného nastavení repozitáře**, co v něm bude, ne z domněnky.
///
/// **Řádek `metoda` je od #556 nabídka, ne opsané slovo** — a leží **v tom výpisu**, ne v políčku
/// nad ním. Je to součást payloadu: co je v tom řádku vybrané, to odejde. Zůstávají u toho dvě
/// věci, na kterých #465 stálo: mergne se pořád **jedním** kliknutím na pojmenované tlačítko
/// (picker není druhý krok) a **s metodou se přepíšou i ostatní řádky** — počet commitů, titulek
/// i věta o těle —, takže se nedá vybrat metodu a přečíst si k ní čísla té předchozí.
///
/// **Nebydlí v detailu PR, ale v `ContentView`** — tatáž past jako u `ReviewSubmission` a o stupeň
/// horší: mergnutý PR ze zdroje `author:@me` na příštím tiku **vypadne**, takže by se sheet
/// zavěšený na detailu ztratil zrovna nad hláškou, ze které se člověk dozví, jak to dopadlo.
/// Od chvíle, kdy se po úspěšném mergi zavírá i **záložka** (#465), by ho to zabilo ještě dřív —
/// hned v tom průchodu, ve kterém merge doběhl.
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
        .frame(minWidth: 460, idealWidth: 520, minHeight: 300, idealHeight: 380)
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
                row("větev", "\(proposal.head) → \(proposal.base)")
                methodRow
                // **Řádky, které se s metodou mění, se z ní taky skládají** (#556): počet commitů
                // i titulek berou `plan`, tedy payload vybrané metody. Dokud vybraná není, není
                // co vypsat — a nechat tam čísla od nevybrané metody by bylo tvrzení, které si
                // nikdo nevyžádal.
                // **Ztlumené je to, co není hodnota payloadu** — u obou řádků, ne jen u titulku:
                // `podle metody` je věta o nevybrané metodě, ne číslo, které odejde. Zákres je
                // kreslí oba v `--ink-3`.
                row("commitů", commitsLine, muted: submission.method == nil)
                row("titulek", titleLine, muted: plan?.commitTitle == nil)
                // Hlava je **podmínka volání**, ne údaj: na commit pushnutý mezi otevřením sheetu
                // a kliknutím odpoví GitHub `409` a nemergne nic. Patří to sem, protože je to
                // jediné místo, kde se dá zkontrolovat, **co** se mergne. Na metodě nezávisí.
                row("hlava", String(proposal.headSha.prefix(7)))
            }
            // **Když výchozí metoda tady nejde, stojí to nad tou větou a pod výpisem** — a je to
            // výstraha, ne popisek: `Mergnout` je v tom stavu zakázané, takže bez ní by to bylo
            // zašedlé tlačítko bez odpovědi (tatáž úvaha jako u výstrahy v panelu).
            if let warning = Policy.mergeMethodWarning(
                default: proposal.defaultMethod,
                in: proposal.repository
            ) {
                warningBox(warning)
            }
            // **Co ve výpisu není, se přizná** — a stojí to **pod** celým výpisem, ne mezi jeho
            // řádky: je to věta o něm, ne další řádek. `commit_message` se neposílá u žádné
            // metody, takže tělo složí GitHub — a od #556 se z přečteného nastavení repozitáře
            // říká, **z čeho**. Věta „vypsané je všechno, co se stane“ by bez tohohle tvrdila víc,
            // než co je vidět.
            //
            // Druhá věta (jen po přepnutí) říká, že přepnutí je **jednorázové**. Bez ní by picker
            // vypadal jako zkratka do nastavení a člověk by čekal, že si to okno bude pamatovat.
            if let notice = bodyNotice {
                Text(verbatim: notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Nabídka metod (#556)

    /// Řádek `metoda` — **pilulky ve výpisu payloadu**, ne políčko ve formuláři nad ním.
    ///
    /// Nepovolená metoda **z nabídky nezmizí**, jen se nedá vybrat: zmizet by znamenalo, že se
    /// nedá poznat rozdíl mezi „repo to nepustí“ a „tuhle metodu GitHub nemá“. Kreslí se zašedlá,
    /// přeškrtnutá a s poznámkou `nejde` za řadou.
    private var methodRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("metoda")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.captionWidth, alignment: .leading)
            // `HStack` s `wrap`em by v 520 bodech nebyl potřeba — tři pilulky se vejdou —, takže
            // se sází řada. Kdyby metod přibylo, je to místo, kde se to pozná.
            //
            // **Nabídka se skládá jednou**, ne zvlášť pro řadu a zvlášť pro poznámku `nejde`: dvě
            // volání téže funkce v jednom těle jsou dvě odpovědi na jednu otázku.
            HStack(spacing: 6) {
                let options = Policy.mergeMethodOptions(in: proposal.repository)
                ForEach(options) { methodPill($0) }
                // Slovo je za **celou řadou**, ne u každé pilulky: přeškrtnutí je vidět na té
                // jedné, kdežto tohle je věta o nabídce.
                if options.contains(where: { !$0.isSelectable }) {
                    Text("nejde")
                        .font(.caption2)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Jedna pilulka. Vybraná je `.pill.run` z návrhu (akcent na slabém akcentu), nevybraná
    /// `.pill.idle` — sazbu drží `designPill`, ne tohle view (#348).
    ///
    /// **Zakázaná pilulka není `Button` s `.disabled`**, ale text: tlačítko, na které se nedá
    /// kliknout, hlásí čtečce akci, která neexistuje — a `nejde` je vedle řady napsané slovy.
    @ViewBuilder private func methodPill(_ option: Policy.MergeMethodOption) -> some View {
        if option.isSelectable {
            Button {
                submission.method = option.method
            } label: {
                Text(verbatim: option.method.displayName)
                    .designPill(tint: pillTint(of: option.method), background: pillFill(of: option.method))
            }
            .buttonStyle(.plain)
            // Ostatní řádky výpisu se přepnutím **změní**, takže to nesmí být tichá volba: bez
            // téhle nápovědi by se dalo přepnout a nevšimnout si, že se s tím přepsal i titulek.
            .help("Mergnout metodou \(option.method.displayName) — platí jen pro tenhle merge")
        } else {
            Text(verbatim: option.method.displayName)
                .strikethrough()
                .designPill(tint: Palette.ink3, background: Palette.raised)
                .opacity(0.55)
                .help("Repozitář tuhle metodu nepovoluje")
        }
    }

    private func pillTint(of method: MergeMethod) -> Color {
        submission.method == method ? Palette.accent : Palette.ink2
    }

    private func pillFill(of method: MergeMethod) -> Color {
        submission.method == method ? Palette.accentWeak : Palette.raised
    }

    /// Výstraha z návrhu (`.warnbox`) — **tatáž sazba jako v panelu**, aby se nedaly rozeznat dva
    /// druhy výstrahy nad jednou akcí.
    private func warningBox(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Ikona je jen vizuální, takže se z accessibility stromu schová — jinak ji čtečka
            // přečte jako jméno symbolu před větou, která to samé říká slovy (nález z #465).
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.stale)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Palette.stale.opacity(0.11), in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.stale.opacity(0.4))
        }
    }

    /// Šířka popisku řádku — **jedno místo**, protože ji vedle řádků payloadu bere i řádek
    /// s nabídkou metod. Dvě čísla by znamenala nabídku odsazenou jinak než výpis nad ní.
    private static let captionWidth: CGFloat = 66

    private func row(_ caption: String, _ value: String, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.captionWidth, alignment: .leading)
            Text(verbatim: value)
                .font(.system(.callout, design: .monospaced))
                // Ztlumené je to, co **není hodnota payloadu**: `podle metody` (nic není vybráno)
                // a `neposílá se` u rebase. Kdyby to bylo stejně černé jako titulek, čtlo by se to
                // jako hodnota, která odejde.
                .foregroundStyle(muted ? Palette.ink3 : Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var proposal: MergeProposal { submission.proposal }

    /// Payload vybrané metody. `nil` = **nic není vybráno** (výchozí metodu repo nepovoluje).
    private var plan: MergePlan? { submission.plan }

    /// Řádek `commitů`. **`podle metody` místo čísel**, dokud vybráno není: nechat tam číslo od
    /// nevybrané metody by bylo tvrzení, které si nikdo nevyžádal.
    private var commitsLine: String {
        guard let method = submission.method else { return "podle metody" }
        return Policy.mergeCommitsLine(method: method, commits: proposal.commits)
    }

    /// Řádek `titulek`. Tři různé odpovědi, a každá znamená něco jiného: hodnota, která odejde;
    /// `neposílá se` u rebase (žádný commit tam nevzniká); `podle metody`, dokud není vybráno.
    private var titleLine: String {
        guard let plan else { return "podle metody" }
        return plan.commitTitle ?? "neposílá se — rebase žádný commit nevytváří"
    }

    /// Věta o **těle** commitu, a po přepnutí i věta o tom, že přepnutí platí jen tady.
    ///
    /// `nil` = nic není vybráno, takže se o těle nedá říct nic — a co s tím, stojí ve výstraze nad
    /// tím. Skládá to `Policy` z **přečteného nastavení repozitáře** (#556): do té doby tu stálo,
    /// že tělo složí GitHub ze zpráv commitů, což je pravda jedině v repu s `COMMIT_MESSAGES`.
    private var bodyNotice: String? {
        guard let method = submission.method else { return nil }
        let body = Policy.mergeBodyNotice(
            method: method,
            commits: proposal.commits,
            base: proposal.base,
            in: proposal.repository
        )
        guard let note = Policy.mergeMethodOverrideNote(
            selected: method,
            default: proposal.defaultMethod
        ) else { return body }
        return body + " " + note
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
    /// **Po úspěchu se sheet zavírá sám**, jako u odeslaného review — a spolu s ním i **záložka
    /// toho PR** (`AppStore.pullRequestWasMerged`, #465).
    ///
    /// Do #465 tady stálo, že se nezavírá: mergnutý PR ze seznamu vypadne, takže by zavřený sheet
    /// nechal člověka koukat na tab, který se přestal kreslit. **Tím, že se zavírá i ta záložka,
    /// ten důvod padl** — za sheetem není mrtvý tab, ale okno přepnuté na sousední záložku nebo
    /// domů.
    ///
    /// **Pořadí drží `merge()`, ne tohle view**: úklid (a v něm zavření záložky) běží uvnitř něj,
    /// takže se sheet nemá jak zavřít dřív než záložka pod ním. Úklid u toho **čeká na síť**, takže
    /// mezi přepnutím stavu a zavřením je průchod, ve kterém patička kreslí zelené
    /// `Mergnuto jako …` — potvrzení bez umělé pauzy, tatáž konstrukce jako u review.
    private var mergeButton: some View {
        // Popisek se skládá **do `String`u**, ne interpolací v literálu: literál by šel do
        // `LocalizedStringKey` a identifikátor PR by se v něm prohnal formátováním.
        Button(mergeLabel) {
            Task {
                await submission.merge()
                // **Až po úspěchu, ne po kliknutí.** Po `409`, `405` i po spadlé síti zůstává
                // sheet otevřený: je to jediné místo, kde je vidět, co GitHub odmítl a jestli se
                // dá zkusit znovu.
                if submission.closesItself { close() }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!submission.canMerge)
    }

    /// Na tlačítku stojí **co se stane a s čím**, ne „OK“. Po selhání se text **nemění** na
    /// „Zkusit znovu“ — akce zůstává tatáž a to, že první pokus nevyšel, stojí vedle v patičce.
    private var mergeLabel: String { "Mergnout \(submission.pullRequest.id)" }
}
