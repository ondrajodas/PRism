import SwiftUI

/// Vlákno konverzace z GitHubu, zavěšené pod svým řádkem.
///
/// Vypadá jinak než bublina nálezu schválně: nález je tvrzení naší aplikace, tohle je to,
/// co napsal člověk. Kdyby se to kreslilo stejně, splynulo by to — a „reviewer nahlásil
/// ztrátu dat“ a „kolega se ptá, proč tady není test“ jsou různě vážné věci.
struct ThreadBubbleView: View {
    let thread: ReviewThread
    /// Přihlášený uživatel — kvůli odlišení mých komentářů. Prázdný, dokud se konverzace
    /// nenačte; pak nic za moje označené není, což je lepší než označit cizí.
    var viewer: String = ""
    var isExpanded = true
    var toggle: (() -> Void)?
    /// Odsazení zleva. Výchozí hodnota míří do sloupce s obsahem vedle čísel řádků, protože
    /// u kódu bublina visí pod svým řádkem. V `Přehledu` (#72) žádná čísla nejsou, takže se
    /// tam předává nula — jinak by vlákno viselo o sto bodů vpravo bez důvodu.
    var indent: Double = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded {
                ForEach(Array(thread.comments.items.enumerated()), id: \.element.id) { index, comment in
                    if index > 0 { Divider() }
                    entry(comment)
                }
                truncationNote
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) { accent }
        .clipShape(.rect(cornerRadius: 8))
        .padding(.leading, indent)   // u kódu do sloupce s obsahem, v Přehledu nula
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Hlavička

    /// Klikací celá, ne jen šipka: sbalené vyřešené vlákno je úzký pruh a trefit se do
    /// deseti bodů šipky je zbytečná práce.
    private var header: some View {
        Button {
            toggle?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if thread.isResolved { resolvedBadge }
                // I ve **sbalené** hlavičce: vyřešené vlákno je sbalené výchozím stavem,
                // takže bez tohohle by useknuté vlákno vypadalo úplné a nebyl by důvod ho
                // otevřít. Utnutá data nesmí vypadat jako úplná ani na jeden pohled.
                if thread.comments.isTruncated { truncationBadge }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(toggle == nil)
    }

    /// Sbalené vlákno musí ze hlavičky říct, co v něm je — jinak není důvod ho otevřít.
    /// Rozbalené hlásí jen počet, protože autoři jsou vidět pod ním.
    private var title: String {
        guard !isExpanded, let first = thread.comments.items.first else {
            // Přes `Plural.czech`, ne ručním `count == 1`: „2 komentářů“ praští do očí
            // a tvary se v okně rozlišují na víc místech, takže patří na jedno.
            return Plural.czech(
                thread.comments.items.count,
                one: "komentář",
                few: "komentáře",
                many: "komentářů"
            )
        }
        return "\(first.author): \(oneLine(first.body))"
    }

    private var resolvedBadge: some View {
        Text("vyřešeno")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.green.opacity(0.18), in: .capsule)
            .foregroundStyle(.green)
    }

    /// Kolik komentářů se do stránky nevešlo. Číslo, ne jen ikona — „chybí něco“ nedává
    /// důvod jít na GitHub, „chybí 12“ ano.
    private var truncationBadge: some View {
        Text(verbatim: "+\(thread.comments.missing)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.18), in: .capsule)
            .foregroundStyle(.orange)
            .help("Další komentáře se nevešly — otevři vlákno na GitHubu.")
    }

    // MARK: - Komentář

    private func entry(_ comment: ThreadComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: comment.author)
                    .font(.caption.weight(.semibold))
                if isMine(comment) {
                    Text("já")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: .capsule)
                }
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link(destination: comment.url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                }
                .help("Otevřít na GitHubu")
            }
            // **Bez `.textSelection(.enabled)`**, i když je to text, který si člověk chce
            // zkopírovat. Bublina je buňka líného seznamu nad diffem a tam je selekce
            // podle CLAUDE.md druhý zdroj nevykreslených řádků — `FindingBubbleView` ho
            // ze stejného důvodu nemá. Kopíruje se z GitHubu, kam vede odkaz výš.
            //
            // Markdown se renderuje: komentáře na GitHubu se v něm píšou a `**takhle**`
            // s dvojitými hvězdičkami se čte špatně.
            MarkdownText(text: comment.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Odpověď je odsazená, ať je z pohledu vidět, co je reakce na co. Strom se z toho
        // nestaví — GitHub vrací vlákno plocho a hloubka by u dvou položek nic nepřinesla.
        .padding(.leading, comment.replyToID == nil ? 0 : 16)
    }

    /// Prázdný `viewer` znamená „nevím“, ne „to jsem já“ — jinak by se u nenačtené
    /// konverzace označilo za moje všechno, co má prázdného autora.
    private func isMine(_ comment: ThreadComment) -> Bool {
        !viewer.isEmpty && comment.author == viewer
    }

    /// Useknuté vlákno nesmí vypadat jako celé — je to totéž pravidlo jako u zahozených
    /// nálezů. Chybí zrovna to, co je ve vlákně nejnovější.
    @ViewBuilder private var truncationNote: some View {
        if thread.comments.isTruncated {
            Text(verbatim: "\(Plural.czech(thread.comments.missing, one: "komentář", few: "komentáře", many: "komentářů")) se nevešlo — otevři vlákno na GitHubu.")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Vzhled

    /// Vyřešené vlákno je bledší — je to historie, ne něco k vyřízení. Nemaže se
    /// z pohledu, stejně jako se nemažou zastaralé záznamy nálezů.
    private var background: some ShapeStyle {
        thread.isResolved ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.quinary)
    }

    private var accent: some View {
        Rectangle()
            .fill(thread.isResolved ? Color.green.opacity(0.5) : Color.secondary.opacity(0.6))
            .frame(width: 3)
    }

    /// Do hlavičky se vejde jeden řádek, takže se konce řádků nahradí mezerou — jinak by
    /// odřádkovaný komentář hlavičku roztáhl a rozvržení bublin by poskakovalo.
    private func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
