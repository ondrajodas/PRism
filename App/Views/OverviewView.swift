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
                descriptionCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Na rozdíl od diffu tady selekce **je**: není to líný seznam tisíců `Text`ů, ale
        // několik odstavců, a hlavní věc, kterou s cizím komentářem chci udělat, je zkopírovat
        // si z něj kus.
        .textSelection(.enabled)
    }

    // MARK: - Popis PR

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: pullRequest.author)
                    .font(.callout.weight(.semibold))
                Text(verbatim: pullRequest.state.czechLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                Text(pullRequest.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link(destination: pullRequest.url) {
                    Label("Otevřít na GitHubu", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
            descriptionBody
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    /// Popis se **renderuje** (`MarkdownText`) — je to Markdown a jako holý text s `##`
    /// a `- [x]` vypadá popis PR nečitelně.
    @ViewBuilder private var descriptionBody: some View {
        if let description, !description.isEmpty {
            MarkdownText(text: description)
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
