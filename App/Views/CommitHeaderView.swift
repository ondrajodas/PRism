import SwiftUI

/// Hlavička rozkliknutého commitu (`.chead` z návrhu, sekce 19, #317).
///
/// Nese to, co se ze seznamu nedozvíš: **tělo zprávy**, přesný čas, počet souborů a `+X −Y` —
/// a **cestu zpět**. Čísla jsou ze staženého diffu, tedy zadarmo; seznam je nést nemůže, protože
/// je odpověď GitHubu nenese (#316).
///
/// **Sbaluje se tělo zprávy, ne celá hlavička.** Zbytek jsou tři řádky pevné výšky, kdežto tělo
/// roste bez omezení — a hlavička sbalená na pruh s tlačítkem by přestala odpovídat na „na co se
/// to koukám“, což je jediný důvod, proč nad diffem vůbec je. Ve sbaleném stavu tedy zůstává cesta
/// zpět, titulek, sha, odkaz na GitHub, autor, čas i počty; zmizí jen odstavce pod titulkem.
///
/// **Jedna tichá věta o tom, že tu není kam kliknout.** Kdo přijde ze `Změněných souborů`, bude do
/// řádku chtít kliknout — a zjišťovat pokusem, že se nic neděje, je dražší než ji přečíst. Odkaz
/// v ní vede tam, kde to jde, takže to není omluva, ale rozcestník.
struct CommitHeaderView: View {
    let commit: PullRequestCommit
    /// `2 ze 7` — kolikátý je v nakresleném seznamu. `nil` = nedá se říct.
    var position: String?
    /// Počet souborů a `+X −Y`. `nil`, dokud diff nedorazil **a u prázdného diffu** — nula souborů
    /// vedle `+0 −0` vypadá jako spočítané prázdno, kdežto tady je to stav, který má vlastní větu
    /// o kus níž.
    var facts: CommitDiffFacts?
    /// Adresa commitu na GitHubu. `nil` = nedá se složit, tlačítko se pak nekreslí.
    var url: URL?
    /// Je vidět tělo zprávy? Drží to store globálně (`AppStore.isCommitMessageExpanded`), protože
    /// `@State` v detailu PR přetéká mezi pull requesty.
    @Binding var isMessageExpanded: Bool
    let back: () -> Void
    /// Skok do `Změněných souborů` — cíl té tiché věty.
    let showFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            backLink
            title
            message
            meta
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 13)
        // **Šířka se zužuje o vlastní odsazení** (#220): pod hlavičkou visí celý diff, takže
        // pružné `maxWidth` by nad ním přidalo úroveň vyjednávání navíc.
        .narrowingWidth(by: 36)
        .filling(alignment: .leading)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    /// `‹ Commity · 2 ze 7`. Zkratka je v nápovědě, ne v popisku — `⎋` vedle textu by z cesty
    /// zpět udělalo druhou lištu.
    private var backLink: some View {
        Button(action: back) {
            HStack(spacing: 6) {
                Text(verbatim: "‹ Commity")
                    .font(.system(size: 11.5))
                if let position {
                    Text(verbatim: position)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                        .monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.accentLink)
        .help(Policy.shortcutHelp("Zpátky na seznam commitů", .backFromCommit))
    }

    /// Zpráva, sha a odkaz ven.
    ///
    /// **Sha je vpravo, ne hned za titulkem, jak ho má návrh** (`.chead .t` má `flex-wrap`, který
    /// SwiftUI nemá). Vpravo je to zároveň **totéž místo, kde stálo v řádku seznamu**, takže
    /// přepnutím obsahu se kapsle nehne — a v úzkém okně se titulek nemá s čím prát.
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: commit.subject.isEmpty ? "(commit bez zprávy)" : commit.subject)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(commit.subject.isEmpty ? Palette.ink2 : Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            shaPill
            if let url {
                Link("otevřít na GitHubu ↗", destination: url)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
            }
        }
    }

    /// Kapsle se zkráceným sha — a **klikací, protože sha se kopíruje** do issue a do commit
    /// messages. Návrh vedle ní kreslí ještě `⧉ kopírovat sha`; dva prvky pro jednu věc by se
    /// v úzkém okně praly o místo s titulkem, takže kopíruje sama kapsle a říká to nápovědou.
    private var shaPill: some View {
        Button { Clipboard.copy(commit.sha) } label: {
            Text(verbatim: commit.shortSha)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Palette.raised, in: .rect(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.lineSoft, lineWidth: 1) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Zkopírovat celý sha: \(commit.sha)")
    }

    /// Přepínač a pod ním tělo zprávy. **U jednořádkové zprávy se nekreslí nic** — ani přepínač,
    /// protože sbalovat prázdno nemá co říct.
    @ViewBuilder private var message: some View {
        let text = Policy.commitMessageBody(of: commit)
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                messageToggle(text)
                if isMessageExpanded { messageBody(text) }
            }
        }
    }

    /// `⌄ Tělo zprávy` / `› Tělo zprávy · 6 řádků` — tentýž tvar jako přeskočené checky
    /// (`ChecksView`) a sbalené vlákno (`ThreadBubbleView`).
    ///
    /// **Vlastní řádek, ne holá šipka u linky vlevo.** Šipka sama by ušetřila těch patnáct bodů,
    /// které řádek v rozbaleném stavu stojí, jenže ve sbaleném by po zprávě nezbylo nic, na co se
    /// dá kliknout — a přepínač, na který se nedá přijít, je stejně dobrý jako žádný. Popisek
    /// zároveň nese počet řádků, tedy jediný údaj o tom, co je schované.
    ///
    /// **Není součástí těla**: tělo má `textSelection(.enabled)`, protože se z něj kopírují odkazy
    /// na issue, a `Button` kolem vybíratelného textu výběr sebere.
    private func messageToggle(_ text: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isMessageExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isMessageExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.ink3)
                    .frame(width: 9)
                Text(verbatim: Policy.commitMessageToggle(text, expanded: isMessageExpanded))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isMessageExpanded ? "Sbalit tělo zprávy a nechat víc místa diffu" : "Rozbalit tělo zprávy")
    }

    /// Tělo zprávy pod titulkem — mono, s linkou vlevo (návrh: `.chead .body`).
    ///
    /// **Vybíratelné**: je v něm odkaz na issue nebo příkaz, který se kopíruje dál. Zalamuje se,
    /// takže `fixedSize` na výšku — bez něj by se dlouhý odstavec uřízl na jednu řádku.
    private func messageBody(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Rectangle().fill(Palette.line).frame(width: 2)
            Text(verbatim: text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Autor, kdy, kolik souborů, `+X −Y` — a vpravo ta tichá věta.
    ///
    /// **`ViewThatFits`, protože návrh se v úzkém okně nevejde**: `.chead .meta` má v CSS
    /// `flex-wrap`, který SwiftUI nemá, takže se místo zalomení uvnitř řádku nabídnou dvě podoby —
    /// na jednom řádku a s větou pod ním. Tentýž vzorec jako u pruhu záložek (#316).
    private var meta: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                factLine
                Spacer(minLength: 12)
                readOnlyNote
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) { factLine; Spacer(minLength: 0) }
                readOnlyNote
            }
        }
    }

    @ViewBuilder private var factLine: some View {
        AvatarView(login: commit.authorName, url: commit.avatarURL, size: 18)
        Text(verbatim: commit.authorName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
        if let committedAt = commit.committedAt {
            // **Relativně, jako všude jinde v okně** — návrh tu má `12. 8. 2026 11:32`, ale dva
            // způsoby, jak v jednom tabu napsat „kdy“, jsou horší než odchylka od jedné buňky
            // návrhu (tentýž závěr jako u řádku seznamu, #316). Přesný čas je v nápovědě, protože
            // tady je to ten údaj, kvůli kterému se do commitu chodí.
            Text(committedAt, format: .relative(presentation: .named))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .help(committedAt.formatted(date: .long, time: .shortened))
        }
        if let facts {
            Text(verbatim: "·")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
            Text(verbatim: facts.files)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .monospacedDigit()
                .lineLimit(1)
            Text(verbatim: "+\(facts.additions)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.ok)
            Text(verbatim: "−\(facts.deletions)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.crit)
        }
    }

    /// „Jen ke čtení“ (návrh: `.ronote`). Odkaz přepne do `Změněných souborů` — kdo sem přišel
    /// s tím, že chce komentovat, se tím dostane tam, kde to jde.
    /// **Text a tlačítko zůstávají dva prvky, ne jeden slitý.** `accessibilityElement(children:
    /// .combine)` by z věty a odkazu udělalo jeden popisek — a odkaz by se ve VoiceOveru hůř
    /// hledal, případně by nešel aktivovat vůbec (nález Copilota). Věta se tedy přečte jako věta,
    /// tlačítko jako akce; jeho vlastní popisek je proto celý, ne jen ten skloňovaný konec, který
    /// samostatně nedává smysl.
    private var readOnlyNote: some View {
        HStack(spacing: 4) {
            Text(verbatim: "Jen ke čtení — nález i rozdělaný komentář patří do")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
            Button("Změněných souborů", action: showFiles)
                .buttonStyle(.accentLink)
                .font(.system(size: 11.5))
                .accessibilityLabel("Otevřít tab Změněné soubory")
        }
        .lineLimit(1)
    }
}

#Preview {
    CommitHeaderView(
        commit: PullRequestCommit(
            sha: "5e2b1aa31f6c0a2a7f2f0a1b3c4d5e6f70819293",
            message: """
                feat: cache secrets for the lifetime of the request

                Každý požadavek si sáhne do Vaultu za každým klíčem zvlášť —
                u konfigurace s deseti secrety to je deset kol po síti.
                """,
            authorName: "Odin Uv",
            authorLogin: "odinuv",
            avatarURL: nil,
            committedAt: Date(timeIntervalSinceNow: -3 * 86_400),
            isMerge: false
        ),
        position: "2 ze 7",
        facts: CommitDiffFacts(files: "3 soubory", additions: 64, deletions: 18),
        url: URL(string: "https://github.com/keboola/vault/commit/5e2b1aa"),
        isMessageExpanded: .constant(true),
        back: {},
        showFiles: {}
    )
    .frame(width: 900)
}
