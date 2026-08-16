import SwiftUI

/// Tab `Commity` (#316) — co se na PR stalo v kterém kroku.
///
/// **Prohlížeč, ne review.** `Změněné soubory` odpovídají na „co je na PR jinak proti základu“:
/// jeden slitý diff, ze kterého je vidět výsledek, ne cesta. Otázka „proč tenhle řádek zmizel“ má
/// odpověď v jednotlivých commitech a dneska se hledá v prohlížeči.
///
/// **Od nejstaršího**, jak to vrací GitHub — PR se takhle čte jako postup, ne jako hromada.
/// Nepřerovnává se ani podle data: po rebase nebo cherry-picku je datum starší než pořadí a postup
/// by se rozházel.
///
/// **Co v řádku není:** počet souborů ani `+X −Y`. Seznam z GitHubu je nenese (`stats` ani `files`
/// v odpovědi nejsou, ověřeno) a dotahovat je po commitu je N+1 past — u sedmi commitů sedm dalších
/// volání k jedné otevřené záložce. Objeví se až v hlavičce rozkliknutého commitu (#317), kde se
/// spočítají ze staženého diffu zadarmo.
///
/// **Řádek se zatím nedá rozkliknout, a proto se u něj nekreslí šipka.** Návrh (sekce 19) ji má,
/// ale diff commitu je #317; šipka, za kterou se nic nestane, slibuje interakci, která tam není —
/// je to tentýž důvod, proč se v `Kontrolách` nenabízí detail u checku bez čísla jobu.
struct CommitListView: View {
    let commits: [PullRequestCommit]
    /// Hlava PR z detailu. `nil` = detail ještě nedorazil; kdo pilulku `hlava` dostane, rozhoduje
    /// `Policy.headCommit(in:head:)`, ne pozice v poli — po pushnutém commitu by poslední řádek
    /// tvrdil něco, co o něm neplatí.
    var head: String?

    var body: some View {
        ScrollView {
            content
        }
        // Sha a zprávy si člověk kopíruje do issue a do commit messages; je to pár řádků textu,
        // ne líný seznam tisíců `Text`ů jako diff.
        .textSelection(.enabled)
    }

    /// Obsah bez `ScrollView`u — **`internal` schválně, kvůli měření** (#294, #316), stejně jako
    /// u `ChecksView` a `OverviewView`: `NSScrollView` si obsah na svou šířku ukrojí, takže by se
    /// přesah nenakreslil a rozbitá šířka by od opravené nešla poznat.
    @ViewBuilder var content: some View {
        // Hlava se hledá **jednou, do proměnné**, ne z computed property uvnitř `ForEach`e:
        // `Policy.headCommit` je průchod seznamem, takže dotaz na každém řádku je O(n²) — u stropu
        // 250 commitů 62 500 porovnání za každé přeskládání obsahu. Tatáž past jako u obarvování
        // řádku z computed property (#224).
        let head = headCommit
        let last = commits.last?.id
        // **Líný, ne obyčejný `VStack`** — a je to změřené, ne opatrnost: 250 commitů (strop, který
        // GitHub na jeden PR vydá) stálo při každém otevření tabu **346 ms** sazby, líně **54 ms**,
        // a hlavně je ta cena od počtu commitů **nezávislá** (7 → 38 ms, 50 → 63 ms, 250 → 54 ms).
        // Řádky mají pevnou výšku, takže se za to neplatí poskakováním scrollu.
        LazyVStack(alignment: .leading, spacing: 0) {
            headline
            ForEach(commits) { commit in
                row(commit, isHead: commit.id == head?.id)
                if commit.id != last {
                    Rectangle().fill(Palette.lineSoft).frame(height: 1)
                }
            }
        }
        .filling(alignment: .topLeading)
    }

    /// Který řádek nese pilulku `hlava`. Rozhoduje `Policy`, ne pozice v poli.
    private var headCommit: PullRequestCommit? {
        Policy.headCommit(in: commits, head: head)
    }

    /// Pruh nad seznamem (`.cbar`): kolik jich je, v jakém pořadí a která hlava.
    ///
    /// Nadpis zůstává, i když ho pruh záložek nese taky — tady je u něj **počet se správným
    /// skloňováním** a pořadí, tedy dvě věci, které ze samotného slova `Commity` nejdou poznat.
    private var headline: some View {
        let text = Policy.commitsHeadline(count: commits.count)
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                // Počet je tmavý a polotučný, zbytek tlumený (návrh: `.cbar b` má `--ink` a 620).
                Text(verbatim: text.count)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Text(verbatim: "· \(text.detail)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink2)
            }
            // Dvě `Text`y jsou sazba, ne dvě sdělení — čtečce se předává celá věta.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.sentence)
            Spacer(minLength: 8)
            if let headCommit { headMark(headCommit) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Vpravo v pruhu: proti kterému commitu platí nálezy. **Vypíše se jen tehdy, když se ta hlava
    /// v seznamu doopravdy najde** — jinak by věta tvrdila, že je seznam čerstvý.
    private func headMark(_ commit: PullRequestCommit) -> some View {
        HStack(spacing: 6) {
            Text("hlava")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
            Text(verbatim: commit.shortSha)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink3)
        }
        .help("Proti téhle hlavě jsou klíčované nálezy")
    }

    /// Řádek commitu (`.crow`): obrázek autora, první řádka zprávy, autor s časem a sha.
    private func row(_ commit: PullRequestCommit, isHead: Bool) -> some View {
        HStack(alignment: .center, spacing: 11) {
            // **Monogram se bere ze jména, ne z přezdívky**, i když účet známe: dokud obrázek
            // nedorazí (a u `author: null` nedorazí nikdy), je monogram tím, co v kolečku stojí —
            // a `IM` vedle jména `Kumar Prateek` vypadá jako řádek o dvou různých lidech. Je to
            // běžný případ, ne kuriozita: sloučení commituje GitHub pod celým jménem, kdežto
            // `author.login` je přezdívka téhož člověka.
            AvatarView(login: commit.authorName, url: commit.avatarURL, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                subject(commit)
                subtitle(commit, isHead: isHead)
            }
            Spacer(minLength: 8)
            Text(verbatim: commit.shortSha)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Palette.raised, in: .rect(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.lineSoft, lineWidth: 1) }
                .help("Celý sha: \(commit.sha)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// První řádka zprávy. **Sloučení je tlumené** (návrh: `.crow.merge .msg`) — je to krok, který
    /// do PR nepřinesl vlastní změnu, takže nemá tahat oko jako práce autora.
    ///
    /// Prázdná zpráva dostane větu v závorce, ne prázdné místo: prázdný řádek vedle avataru vypadá
    /// jako chyba kreslení, a `Policy` za autora zprávu nevymyslí.
    @ViewBuilder private func subject(_ commit: PullRequestCommit) -> some View {
        let subject = commit.subject
        Text(verbatim: subject.isEmpty ? "(commit bez zprávy)" : subject)
            .font(.system(size: 13, weight: commit.isMerge ? .regular : .medium))
            .foregroundStyle(commit.isMerge || subject.isEmpty ? Palette.ink2 : Palette.ink)
            // Jedna řádka a uříznout — celá zpráva patří do hlavičky rozkliknutého commitu (#317).
            // Bez toho by dlouhý `Merge branch … into …` roztáhl řádek na tři.
            .lineLimit(1)
            .truncationMode(.tail)
            // **Uříznutý text musí jít někde dočíst.** Dokud rozkliknutí commitu není (#317), je
            // tooltip jediná cesta k tělu zprávy — a zároveň jediný důvod, proč model drží celou
            // `message`, ne jen `subject`.
            .help(subject.isEmpty ? "Commit nemá zprávu" : commit.message)
    }

    /// Autor a čas pod zprávou (`.crow .sub`), a k tomu pilulky, které o commitu něco tvrdí.
    private func subtitle(_ commit: PullRequestCommit, isHead: Bool) -> some View {
        HStack(spacing: 7) {
            Text(verbatim: commit.authorName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
            if let committedAt = commit.committedAt {
                Text(verbatim: "·")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
                // **Datum commitu, ne pushnutí** — `pushedDate` GitHub už neplní, viz #171.
                Text(committedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
            // **Sloučení dostane pilulku**: jeho diff je proti prvnímu rodiči a umí vyjít prázdný,
            // takže bez ní by prázdný diff v #317 vypadal jako porucha. Je to tentýž rozdíl jako
            // mezi `čisté` a `spadlo` u review.
            if commit.isMerge { pill("sloučení", tint: Palette.ink2, background: Palette.raised) }
            // **Hlava se pozná, protože proti ní jsou klíčované nálezy** (tvrdá podmínka č. 5).
            // Mátová, ne tichá: je to jediný řádek, o kterém se dá říct, že to, co je v okně
            // vedle, platí zrovna k němu.
            if isHead { pill("hlava", tint: Palette.mint, background: Palette.mint.opacity(0.15)) }
        }
    }

    /// Pilulka v podtitulku řádku (návrh: `.pill.idle`, `.pill.mint`).
    private func pill(_ text: String, tint: Color, background: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
    }
}

#Preview {
    CommitListView(
        commits: [
            PullRequestCommit(
                sha: "a1c9f0431f6c0a2a7f2f0a1b3c4d5e6f70819293",
                message: "chore: bump php-vault-client to 4.2",
                authorName: "Odin Uv",
                authorLogin: "odinuv",
                avatarURL: nil,
                committedAt: Date(timeIntervalSinceNow: -3 * 86_400),
                isMerge: false
            ),
            PullRequestCommit(
                sha: "9f3d7c21f6c0a2a7f2f0a1b3c4d5e6f708192939",
                message: "Merge branch 'main' into chore/deps-2026",
                authorName: "Odin Uv",
                authorLogin: "odinuv",
                avatarURL: nil,
                committedAt: Date(timeIntervalSinceNow: -2 * 86_400),
                isMerge: true
            ),
            PullRequestCommit(
                sha: "e8d4a6031f6c0a2a7f2f0a1b3c4d5e6f70819294",
                message: "refactor: move SecretNotFound into its own file\n\nTělo zprávy se v seznamu nekreslí.",
                authorName: "Petra Malá",
                authorLogin: nil,
                avatarURL: nil,
                committedAt: Date(timeIntervalSinceNow: -3_600),
                isMerge: false
            ),
        ],
        head: "e8d4a6031f6c0a2a7f2f0a1b3c4d5e6f70819294"
    )
    .frame(width: 760, height: 260)
}
