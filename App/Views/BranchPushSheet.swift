import SwiftUI

/// Potvrzení přetlačení větve (#466) — poslední obrazovka před tím, než se přepíše historie větve
/// na remote.
///
/// **Dvě kliknutí, dvě různá tlačítka**, jako u merge (#465) a odeslání review (#68): `Force push…`
/// v panelu jen otevře tenhle sheet, teprve tlačítko tady zavolá pusher. A **bez výchozí akce** —
/// poslední klik před nevratnou věcí je klik, ne `Enter`.
///
/// **Proč sheet, a ne pojmenované tlačítko v panelu:** návrh (sekce 36) kreslí `Force push`
/// jako tlačítko v patičce sheetu **nad vypsaným výsledkem**, a to i pro konfliktní cestu (#467).
/// Kdyby bezkonfliktní cesta měla tlačítko v panelu, byly by z toho dva tvary téhož potvrzení a #467
/// by ho musel stěhovat. Do panelu se navíc nevejde ani výstraha o lease — má 300 bodů.
/// #467 pak do tohohle sheetu jen **přidá** obsah: co s konflikty udělala session a diff toho, co
/// vzniklo.
///
/// **Nebydlí v detailu PR, ale v `ContentView`** — tatáž past jako u merge. Sheet zavěšený na
/// detailu zmizí, jakmile se pod ním záložka přestane kreslit, a to je zrovna ta chvíle, kdy je
/// v něm vidět, jak to dopadlo.
struct BranchPushSheet: View {
    let submission: BranchPushSubmission
    let close: () -> Void
    /// Zahodit, co leží v cache. Zavře sheet — dál už není co potvrzovat.
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { content.padding(16) }
            Divider()
            footer
        }
        // **Bez `ideal*`, a je to vědomé.** SwiftUI u sheetu `idealWidth` **zahodí**, dokud k němu
        // není `presentationSizing(.fitted)` (změřeno u #327, druhý výskyt v `CodeTextSheet`) —
        // takže `idealWidth: 520` tvrdilo šířku, kterou sheet nikdy nedostal, a otevíral se
        // v podlaze 460. Zamítnuto přidat `.fitted`: byla by to **nezměřená** změna velikosti
        // sheetu, který takhle člověk už proklikal a 460 mu stačilo — a rozměr sheetu se
        // v harnessu ověřit nedá. Zůstává tedy podlaha, která platí, místo ideálu, který ne.
        // Tentýž vzor má `MergeSheet` z #465; sahat na velikost cizí hotové obrazovky sem nepatří.
        .frame(minWidth: 460, minHeight: 320)
        // Zavřít okno uprostřed volání by znamenalo nevědět, jestli se pushovalo.
        .interactiveDismissDisabled(submission.state == .pushing)
        // **Zavření visí na stavu, ne na tlačítku** (#466, z proklikání). Rozhoduje o tom
        // `closesItself`, tedy tentýž typ, který ví, co se stalo — takže se zavírá **jedině po
        // úspěchu**: po odmítnutém leasu, `409`, timeoutu ani spadlé síti se stav na `.pushed`
        // nedostane a sheet zůstane otevřený, protože je to jediné místo, kde je ta chyba vidět.
        //
        // Proč na stavu a ne za `await push()`: `push()` čeká i na úklid, a ten čeká na hlavu pull
        // requestu (změřeno 1,45–2,16 s) — sheet by nad hotovým pushem visel několik sekund.
        .onChange(of: submission.state) { _, _ in
            if submission.closesItself { close() }
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Force push?")
                .font(.headline)
            // `verbatim` a ruční skládání: `Text("…#\(number)")` by číslo PR prohnalo locale
            // a z #21663 udělalo „#21 663“.
            Text(verbatim: submission.pullRequest.id.description)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            // **Věta o mechanismu, ne o aktuálním stavu remote.** Do #466 tu stálo „Do remote se
            // zatím nesáhlo.“ — a přestávalo to být pravda, jakmile push běžel nebo doběhl,
            // protože hlavička v sheetu **zůstává ve všech stavech**. U `timedOut` by navíc
            // tvrdila jistotu, kterou nemáme (`aftermath` u něj schválně říká „nevím, jestli push
            // doběhl“). Popis kroku platí v každém stavu; co se stalo s remote, říká patka.
            Text("Rebase je hotový v kopii repa. Force push je druhý krok.")
                .font(.callout)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Co odejde

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Co odejde")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    row("větev", plan.branch)
                    row("commitů", "\(submission.replayed)")
                    // Obojí ze **snímku**, ne z aktuálního detailu: co je vidět, to odejde.
                    row("nová hlava", String(plan.sha.prefix(7)))
                    // Hlava, na kterou čeká lease. Je to **podmínka volání**, ne údaj — proto je
                    // ve výpisu a proto o ní mluví i výstraha pod ním.
                    row("lease čeká", String(plan.expectedRemoteSha.prefix(7)))
                }
            }
            commitList
            leaseWarning
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Výstraha o pojistce. **Sazba `.warnbox` z návrhu**, tatáž jako v panelu — je to tentýž druh
    /// věty, jen na jiném místě.
    private var leaseWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Ikona je jen vizuální, takže se z accessibility stromu schová: čtečka by ji přečetla
            // jako jméno symbolu před větou, která to samé říká slovy.
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.stale)
                .accessibilityHidden(true)
            // Věta je z `Policy`, ne opsaná tady: kdyby ji sázel sheet i panel každý po svém,
            // rozešly by se.
            Text(verbatim: submission.leaseWarning)
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

    private func row(_ caption: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(verbatim: value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var plan: BranchPushPlan { submission.plan }

    // MARK: - Patička

    private var footer: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 12)
            buttons
        }
        .padding(16)
    }

    /// Které commity odejdou — **titulky, ne jen počet** (#466, z proklikání).
    ///
    /// `Co odejde` výš říká *kolik*; potvrzení u nevratné akce má být místo, kde se přečte **celý**
    /// payload, a u merge (#465) to tak je. Seznam je ze **snímku po rebasu**, takže sha jsou ta
    /// nová — dají se po pushi porovnat s GitHubem.
    ///
    /// **Titulek se zalamuje, sha ne.** Sheet je široký jako `minWidth` (`idealWidth` u něj SwiftUI
    /// zahodí, viz `body`), takže se dlouhý titulek musí vejít **zalomením** — rozšířit sheet kvůli
    /// cizímu textu nejde. `fixedSize(vertical:)` je to, co zalomení dovolí; bez něj by se titulek
    /// ořezal na jednu řádku a z „co odejde“ by zbyla polovina věty.
    ///
    /// **Sha je `monospaced` a nezalamuje se** — je to sedm znaků, které se čtou po znaku.
    @ViewBuilder private var commitList: some View {
        let list = Policy.pushedCommitList(submission.commits)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(list.shown, id: \.sha) { commit in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: commit.shortSha)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(verbatim: commit.title)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            // **Zbytek se počítá, neořezává potichu.** Rozhoduje `Policy`, ne tenhle výpis.
            if list.hidden > 0 {
                Text(verbatim: "a další \(Plural.czech(list.hidden, one: "commit", few: "commity", many: "commitů"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch submission.state {
        case .ready:
            EmptyView()
        case .pushing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Pushuju…").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: error.sentence)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                // **Odmítnutý lease není červený.** Znamená, že pojistka zabrala a nic se
                // nepřepsalo — je to výsledek, ne porucha, a barva to má říkat dřív než text.
                .foregroundStyle(error == .leaseRejected ? Palette.stale : Palette.crit)
                Text(verbatim: aftermath(of: error))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        // **Úspěch se tady nekreslí, a je to schválně**: na `.pushed` se sheet zavírá, takže by
        // to byl stav, který nikdo neuvidí. Výsledek nese **panel** hláškou `Hotovo — force push
        // poslal N commitů.`, kterou store nastavuje **dřív** než začne úklid — takže je na
        // obrazovce od chvíle, kdy sheet zmizí.
        case .pushed:
            EmptyView()
        }
    }

    /// Co z chyby plyne o stavu remote. **Tři různé věty, ne jedna**, a dělí se podle toho, co se
    /// o remote doopravdy **ví**.
    ///
    /// Dvě opravy po revizi, obě ze stejné třídy („text tvrdí víc, než data unesou“):
    ///
    /// - **`leaseRejected` nesmí říkat „na větvi se nic nezměnilo“.** Vedle věty z `error.sentence`
    ///   („Větev se na GitHubu mezitím pohnula…“) to vyznělo protichůdně, protože každá mluví
    ///   o jiné změně — ta první o cizím pushi, tahle o tom našem. Říká se proto výslovně, že to
    ///   **náš** push nepřepsal.
    /// - **`failed` patří k nejistým, ne do `default`u.** Byla to neznámá chyba od `gitu`
    ///   v košíku, který tvrdil „nic se nezměnilo“ — u nevratné akce zrovna to tvrzení nesmí padnout
    ///   naslepo. Jistotu máme jedině u chyb z **pre-flightu** (cizí PR, fork, mimo cache, zavřený
    ///   PR, vypnutá brána): tam se `git push` **nespustil**, takže se nezměnit nemohlo nic.
    private func aftermath(of error: BranchSyncError) -> String {
        switch error {
        case .leaseRejected:
            "Tvůj push větev nepřepsal — pojistka zabrala. Načti pull request znovu."
        case .timedOut, .interrupted, .failed:
            "Zkontroluj větev na GitHubu — nevím, jestli push doběhl."
        default: "Na větvi se nic nezměnilo — push se ani nespustil."
        }
    }

    /// **Bez větve pro `.pushed`**: na ten stav se sheet zavírá, takže tlačítka pod hotovým pushem
    /// by nikdo neviděl. Do #466 tu stál `Zavřít` a odkaz na GitHub — obojí zmizelo s tím, že se
    /// zavírá samo.
    @ViewBuilder private var buttons: some View {
        switch submission.state {
        default:
            // **Zahodit se dá i odsud**, ne jen z panelu: sheet je to místo, kde je vidět, co
            // v cache leží, takže je to zrovna ta chvíle, kdy se člověk rozhodne to nepushovat.
            Button("Zahodit rebase") {
                discard()
                close()
            }
            .disabled(submission.state == .pushing)
            Button("Zrušit", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(submission.state == .pushing)
            pushButton
        }
    }

    /// Tlačítko je pojmenované **akcí** a **není výchozí**: `.keyboardShortcut` na něm schválně
    /// žádný není, takže `Enter` nic nepřetlačí. `.borderedProminent` je vzhled, ne klávesa.
    /// Popisek je `Force push` z návrhu (sekce 36), aby se nerozešel s tím, co #467 kreslí.
    private var pushButton: some View {
        Button("Force push") {
            // **Zavírá se na přechodu stavu, ne po dokončení `push()`** — a je to změna
            // z proklikání. `push()` totiž čeká i na úklid po pushi, a ten od té doby čeká na
            // hlavu pull requestu (1,45–2,16 s změřeno) a pak tahá detail: sheet by nad hotovým
            // pushem visel několik sekund a vypadalo by to, že se zavřít nechce. Úklid běží dál
            // ve svém `Task`u — ten není vázaný na životnost view, takže dismiss ho nezruší.
            Task { await submission.push() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!submission.canPush)
    }
}
