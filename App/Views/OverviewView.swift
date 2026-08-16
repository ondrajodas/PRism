import SwiftUI

/// Tab `Přehled`: **jak to teď stojí** — popis PR, fakta a co se změnilo od minule.
///
/// Vzniklo to proto, že s M6 přibyl obsah, který v diffu nemá kde být — popis PR, komentáře
/// pod PR, review ostatních a vlákna, jejichž řádek v aktuálním diffu není. Nacpat ho do
/// spodního pruhu vedle kódu znamená čít ho v úzkém sloupci pod něčím, s čím nesouvisí.
///
/// **Konverzace se od #183 stěhovala do vlastního tabu.** Jsou to dvě různé otázky a v jednom
/// scrollu se ta druhá četla tak, že se přes první přerolovalo. Vlákna *s kotvou* zůstávají
/// bublinami u kódu; jediný domov konverzace se tím nedělí, jen posunul.
struct OverviewView: View {
    /// Popis PR. `nil` = detail se ještě nenačetl, což je jiný stav než „autor nic nenapsal“.
    var description: String?
    /// Fakta o PR do dlaždic (#198). Prázdná = řádek se nekreslí.
    var facts: PullRequestFacts = PullRequestFacts(tiles: [])
    /// Co přibylo od poslední návštěvy (#173). Prázdné = nic, nebo se ještě nenačetla
    /// konverzace; banner se v obou případech nekreslí.
    var changes: VisitChanges = .none
    /// Proti čemu se změny počítají.
    var lastVisit: Date?
    /// Zastaraly nálezy nebo rozdělané review? Tvrzení o **uložených datech**, ne o časové ose,
    /// takže ho počítá store.
    var isStale = false
    /// Nová hlava PR, pokud se od minule posunula — viz `SinceLastVisitView`.
    var movedHead: String?
    var rerun: (() -> Void)?
    /// „Přečteno“ — viz `SinceLastVisitView`.
    var dismissChanges: (() -> Void)?

    let pullRequest: PullRequestSummary

    var body: some View {
        ScrollView {
            content
        }
        // Na rozdíl od diffu tady selekce **je**: není to líný seznam tisíců `Text`ů, ale
        // několik odstavců, a hlavní věc, kterou s cizím komentářem chci udělat, je zkopírovat
        // si z něj kus.
        .textSelection(.enabled)
    }

    /// Obsah bez `ScrollView`u — **`internal` schválně, kvůli měření** (#291).
    ///
    /// Přes `body` se přetečení šířky změřit nedá: `ScrollView` je na macOS `NSScrollView`, takže
    /// si obsah na svou šířku **ukrojí**. Rozbitý stav pak na renderu vypadá skoro jako opravený —
    /// jen mu chybí pravá hrana karty a poslední prvek v hlavičce je odříznutý, což je přesně to,
    /// co #291 hlásilo z běžící aplikace. Bez scrollu se přetečení nakreslí a dá se spočítat.
    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Posunutá hlava se počítá jako změna i bez událostí: po rebase jsou commity
            // starší než moje návštěva, takže se do `changes` nedostanou, ale kód je jiný.
            if !changes.isEmpty || movedHead != nil {
                SinceLastVisitView(
                    changes: changes,
                    since: lastVisit,
                    isStale: isStale,
                    movedHead: movedHead,
                    rerun: rerun,
                    dismiss: dismissChanges
                )
            }
            // Dlaždice **nad popisem** (#280, návrh sekce 18): popis PR je libovolně dlouhý —
            // u pracovních PR běžně padesát řádků — kdežto fakta jsou tři čísla a dvě sha.
            // Pod popisem se k nim tedy scrolluje přes prózu, jejíž délku neurčujeme my, a jedno
            // z nich (`Nálezy proti`) odpovídá na otázku „platí to, co v okně vidím?“. Odpověď
            // na ni nepatří za odrolování. Boxíky jsou přehled, popis je čtení.
            //
            // Do #280 to bylo obráceně, s odůvodněním „popis je to, co autor chce, aby se
            // přečetlo“. Nezrušilo se to proto, že by to bylo špatně, ale proto, že pořadí
            // řeší **cenu za odrolování**, a ta je nesouměrná: fakta jsou vždycky krátká,
            // popis vždycky ne.
            if !facts.isEmpty {
                PullRequestFactsView(facts: facts)
            }
            descriptionCard
            // **Kontroly tady nejsou vůbec** (#215). Do #215 to byl seznam (#209), pak chvíli
            // souhrn — a nakonec ani ten: tab `Kontroly` na tu otázku odpovídá celou
            // a „je to zelené“ nese chip v hlavičce PR, který je vidět ve všech tabech.
            // Souhrn tu byl třetí místo o téže věci. Vyžádané při zkoušení, viz specifikace.
        }
        // **Odsazení se musí odečíst z předávané šířky** (#220), jinak karty dostanou šířku celého
        // tabu a přetečou o těch 16 bodů na každé straně — tatáž dvojice řádků, jakou má osa
        // konverzace. Chybělo to od #279 (`filling()` v sazbě Markdownu), viz #291.
        .narrowingWidth(by: 32)
        .padding(16)
        // **Pružně, ne `filling()`**: tohle je hranice, na které o šířce rozhoduje `ScrollView`,
        // a jedna úroveň vyjednávání nic nestojí. `frame(width:)` by navíc přetečení uvnitř
        // **schoval** — tvrdý rámec drží svůj rozměr i nad dítětem, které se do něj nevejde, takže
        // by se šířka `Přehledu` přestala dát změřit (`OverviewWidthTests`).
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Popis PR

    /// Karta s popisem podle návrhu (sekce 03, `.desc`): **hlavička oddělená linkou**, ne blok
    /// šedi. Popis PR bývá dlouhý — půl obrazovky jednolitého podkladu se čte hůř než plocha
    /// s obrysem, ve které je vidět, kde začíná a končí.
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            descriptionHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }

            descriptionBody
                // **Zúžení jde před odsazení** (#220), jako u karty v konverzaci: sazba Markdownu
                // si od #279 bere šířku z prostředí (`filling()`), takže bez tohohle řádku věří,
                // že má celou kartu, a přeteče o obě třináctky. Zvenčí to vypadalo, že karta není
                // ukončená — #291.
                .narrowingWidth(by: 26)
                .padding(.horizontal, 13)
                .padding(.top, 11)
                .padding(.bottom, 13)
                // **Pružně, ne `filling()`** — a je to podmínka měřitelnosti, ne ušetřený řádek:
                // `frame(width:)` z `filling()` drží svůj rozměr i nad dítětem, které se do něj
                // nevejde, takže by zúžení o čtyři řádky výš mohlo zmizet a karta by zvenčí
                // vypadala v pořádku, jen by jí sazba ležela na pravém obrysu. Vyzkoušené vložením
                // regrese: s `filling()` tady zůstaly `OverviewWidthTests` zelené i po smazání
                // `narrowingWidth(by: 26)`.
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
    }

    /// Hlavička karty: kdo, v jakém stavu, kdy naposled a odkaz na GitHub.
    ///
    /// **Dvě podoby, ne zkracování na sílu** (#291). Se správnou šířkou (o 26 bodů užší, než jakou
    /// karta měla po #279) se čtyři údaje v úzkém tabu na jeden řádek nevejdou — a `HStack` je
    /// nakrájí tak, že v hlavičce zbyde `ote…` z pilulky a osamocené `r` z `minulý rok`. Naměřeno
    /// renderem ve 320 bodech, což je tab v okně na jeho minimu (700) s vytaženým panelem.
    ///
    /// `ViewThatFits` proto vezme celou variantu, dokud se vejde, a jinak tu **bez relativního
    /// času**: ze čtyř údajů je nejméně potřebný a stejný údaj nese i řádek ve frontě a hlavička
    /// PR nad tabem. Vypadnout celý je čitelnější než zbytek slova.
    private var descriptionHeader: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(showsAge: true)
            headerRow(showsAge: false)
        }
    }

    private func headerRow(showsAge: Bool) -> some View {
        HStack(spacing: 8) {
            // Kolečko s iniciálami, jak ho má návrh — hlavička bez něj vypadá jako
            // odstavec, ne jako něčí příspěvek. **Bez adresy obrázku** (`url: nil`): shrnutí
            // PR z vyhledávání nese jen jméno autora, ne odkaz na avatar, a dotahovat ho
            // zvlášť by bylo volání navíc na tik. Iniciály tedy nejsou dočasný stav, ale
            // to, co se tu kreslí vždycky.
            AvatarView(login: pullRequest.author, url: nil, size: 18)
            Text(verbatim: pullRequest.author)
                .font(.system(size: 12, weight: .semibold))
            Text(verbatim: pullRequest.state.czechLabel)
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.raised, in: .capsule)
            if showsAge {
                Text(pullRequest.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
            Link(destination: pullRequest.url) {
                Label("Otevřít na GitHubu", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11.5))
                    // **`lineLimit` z řádku pod `Link` nedosáhne** — změřeno renderem: odkaz se
                    // zalomil na `Otevřít na / GitHub / u`, i když ho celý řádek měl zakázaný.
                    // Musí být tady, uvnitř.
                    .lineLimit(1)
            }
            // Odkaz ustupuje **poslední**: je to jediná věc v hlavičce, na kterou se dá kliknout,
            // takže popisek na půl slova je horší než zkrácené jméno autora. Pružný zůstává
            // schválně — v tabu stlačeném pod ~130 bodů (panel vytažený na maximum v minimálním
            // okně) se musí umět zkrátit, jinak by kartu roztlačil a byla by z toho zpátky #291.
            .layoutPriority(1)
        }
        // Zalomení uvnitř slova je v hlavičce vždycky horší než tři tečky: `otevře/ný` v pilulce
        // není odznak, ale dva odznaky pod sebou.
        .lineLimit(1)
    }

    /// Popis se **renderuje** (`MarkdownText`) — je to Markdown a jako holý text s `##`
    /// a `- [x]` vypadá popis PR nečitelně.
    @ViewBuilder private var descriptionBody: some View {
        if let description, !description.isEmpty {
            // Písmo z návrhu: próza 12,5, nadpisy si `MarkdownText` odvodí. Popis PR je
            // nejdelší souvislý text v okně, takže o stupeň menší než zbytek — jinak
            // z něj na obrazovku padne polovina.
            MarkdownText(text: description, size: 12.5)
        } else if description == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Načítám popis…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Text("Autor k PR nic nenapsal.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

}

/// Kolik se toho do stránek konverzace nevešlo, po částech.
///
/// Vlastní typ, ne tři parametry: do view se to předává na jednom místě a součet „něco chybí“
/// musí být jeden výraz, ne `||` opakované v každém volajícím.
struct ConversationShortfall: Hashable, Sendable {
    var reviews = 0
    var comments = 0
    var threads = 0
    /// Časová osa **bez počtu** (#171).
    ///
    /// Je to jediná část konverzace, u které se nedá říct kolik: `timelineItems` s `itemTypes`
    /// vrací `totalCount` bez ohledu na filtr, takže zbývá `hasNextPage`. Mlčet o tom nejde —
    /// chybějící push se od „nic se nestalo“ nepozná — ale číslo si nesmíme vymyslet.
    var events = false

    init(reviews: Int = 0, comments: Int = 0, threads: Int = 0, events: Bool = false) {
        self.reviews = reviews
        self.comments = comments
        self.threads = threads
        self.events = events
    }

    init(_ conversation: Conversation) {
        self.init(
            reviews: conversation.reviews.missing,
            comments: conversation.comments.missing,
            threads: conversation.threads.missing,
            events: conversation.events.isTruncated
        )
    }

    var any: Bool { reviews > 0 || comments > 0 || threads > 0 || events }

    /// Věta o tom, co chybí — po částech, protože „něco se nevešlo“ nedává důvod jít na
    /// GitHub, kdežto „12 komentářů“ ano.
    var summary: String {
        var parts: [String] = []
        if comments > 0 {
            parts.append(Plural.czech(comments, one: "komentář", few: "komentáře", many: "komentářů"))
        }
        if reviews > 0 {
            parts.append(Plural.czech(reviews, one: "review", few: "review", many: "review"))
        }
        if threads > 0 {
            parts.append(Plural.czech(threads, one: "vlákno", few: "vlákna", many: "vláken"))
        }
        // Bez počtu, protože ho neznáme — „část historie“ je všechno, co se dá poctivě říct.
        if events {
            parts.append("část historie")
        }
        return "Nevešlo se: \(parts.joined(separator: ", "))"
    }
}
