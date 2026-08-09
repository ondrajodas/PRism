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
    var indent: Double = DiffLineView.contentInset(for: .unified)
    /// Odpovídání a vyřešení (#73). `nil` = bublina je jen ke čtení, což je stav, ve kterém se
    /// staví v testech skládání řádků a v náhledech.
    var actions: ThreadActions?
    /// Kolik řádků kontextu má úryvek. `nil` = bublina úryvek nekreslí (u kódu ho nese diff),
    /// číslo = kreslí ho sama, jak to potřebuje osa konverzace (#216).
    var snippetContext: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded {
                if let snippetContext, let snippet = Policy.snippet(of: thread, context: snippetContext) {
                    ThreadSnippetView(snippet: snippet, path: thread.path)
                }
                ForEach(Array(thread.comments.items.enumerated()), id: \.element.id) { index, comment in
                    if index > 0 { Divider() }
                    entry(comment)
                }
                truncationNote
                // Jen v rozbaleném vlákně: ve sbaleném (typicky vyřešeném) je hlavička jeden
                // pruh a pole na odpověď by z něj udělalo to největší v bublině.
                compose
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // **Plocha palety s obrysem**, ne systémová šeď (#216). `.quinary` je neutrální šedá,
        // kdežto okno stojí na neutrálech posunutých do modrofialové — vedle karty komentáře
        // a bloku kontrol to vypadalo jako cizí prvek.
        //
        // **Bez proužku na hraně:** vyřešené vlákno hlásí odznak `vyřešeno` v hlavičce, takže
        // proužek říkal totéž podruhé — a v ose se pletl s proužkem verdiktu u review, který
        // znamená něco jiného.
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
        .clipShape(.rect(cornerRadius: 7))
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
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink3)
                // **Cesta a řádek, ne „1 komentář“** (#216): hlavička vlákna má říct, ke kterému
                // místu se váže — počet je vidět z komentářů pod ní.
                Text(verbatim: location)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .truncationMode(.head)
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

    /// Kde vlákno visí — `soubor:řádek`. U zastaralého je číslo z `originalLine`, protože `line`
    /// mají prázdné právě ta (ověřeno na `cli/cli#13084`: 24 ze 38).
    private var location: String {
        guard let line = thread.line ?? thread.originalLine else { return thread.path }
        return "\(thread.path):\(line)"
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
            // **Jméno vlevo, čas vpravo** (#216), jak to má návrh: slepené k sobě se čtou jako
            // jeden údaj a čas se ztrácí mezi jmény.
            HStack(spacing: 6) {
                AvatarView(login: comment.author, url: nil, size: 18)
                Text(verbatim: comment.author)
                    .font(.system(size: 12, weight: .semibold))
                if isMine(comment) {
                    Text("já")
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: .capsule)
                }
                Spacer(minLength: 8)
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
                Link(destination: comment.url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
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
            MarkdownText(text: comment.body, font: .system(size: 12.5))
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
            // Sloveso je **v tvarech**: „2 komentáře se nevešlo“ je špatně česky.
            Text(verbatim: Plural.czech(
                thread.comments.missing,
                one: "komentář se nevešel",
                few: "komentáře se nevešly",
                many: "komentářů se nevešlo"
            ) + " — otevři vlákno na GitHubu.")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Odpověď (#73)

    /// Pole na odpověď a tlačítka pod ním.
    ///
    /// **Bez potvrzování** — rozhodnutí #73: odpověď je jedna věta v diskuzi, dá se smazat
    /// a potvrzovací sheet u každé by z okna udělal klikačku. Review se potvrzuje proto, že je
    /// to verdikt nad celým PR.
    @ViewBuilder private var compose: some View {
        if let actions {
            VStack(alignment: .leading, spacing: 8) {
                // **Avatar vedle pole a pole na jeden řádek** (#216). Velký box přes celou
                // šířku vypadá jako hlavní věc v bublině, přitom hlavní je ten komentář nad ním.
                HStack(alignment: .top, spacing: 8) {
                    AvatarView(login: viewer, url: nil, size: 18)
                    DraftTextEditor(
                        text: actions.reply(thread),
                        placeholder: "Odpovědět do vlákna…",
                        minHeight: 26,
                        commit: { actions.setReply(thread, $0) }
                    )
                    // Identita per vlákno: bublina je buňka líného seznamu a po odscrollování
                    // se staví znovu, takže bez tohohle by se rozepsaný text mohl objevit
                    // u cizího vlákna. Tatáž past jako u těla review, klíčovaného PR.
                    .id(thread.id)
                    .disabled(state?.isBusy == true)
                }

                controls(actions)
                failureNote
            }
        }
    }

    private func controls(_ actions: ThreadActions) -> some View {
        HStack(spacing: 8) {
            replyButton(actions)
            resolutionButton(actions)
            Spacer(minLength: 8)
            // Počet odpovědí vpravo, jak ho má návrh — z vlákna je pak vidět, kolik toho je,
            // i když je sbalené na jeden komentář.
            if thread.comments.items.count > 1 {
                Text(verbatim: Plural.czech(
                    thread.comments.items.count - 1,
                    one: "odpověď",
                    few: "odpovědi",
                    many: "odpovědí"
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
            if let state, state.isBusy {
                ProgressView().controlSize(.small)
                Text(verbatim: busyLabel(state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Zakázané tlačítko **s důvodem**, ne schované: prázdná odpověď, běžící akce i zakázané
    /// odesílání se dají vysvětlit, kdežto chybějící tlačítko ne.
    private func replyButton(_ actions: ThreadActions) -> some View {
        // **Bez ikony** (#216): návrh má holý popisek. Šipka vedle slova „Odpovědět“ říká
        // totéž podruhé a v řadě dvou tlačítek dělá z bubliny lištu nástrojů.
        Button("Odpovědět") { actions.send(thread) }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 11.5))
            .disabled(actions.block != nil || !hasText(actions) || state?.isBusy == true)
            .help(replyHelp(actions))
    }

    private func replyHelp(_ actions: ThreadActions) -> String {
        if let block = actions.block { return block }
        if !hasText(actions) { return "Napiš odpověď — prázdnou GitHub tiše zahodí." }
        return "Odešle odpověď do vlákna. Nepotvrzuje se, je to jedna věta v diskuzi."
    }

    /// `Vyřešit` / `Znovu otevřít` se kreslí jen tam, kde na to GitHub dává právo
    /// (`viewerCanResolve` / `viewerCanUnresolve`) — tady tlačítko **mizí**, na rozdíl od
    /// odpovědi: chybějící právo se nedá spravit ničím, co je v okně, takže by zakázané
    /// tlačítko jen zabíralo místo a slibovalo akci, která nikdy nepůjde.
    @ViewBuilder private func resolutionButton(_ actions: ThreadActions) -> some View {
        if thread.canToggleResolution {
            Button(thread.isResolved ? "Znovu otevřít" : "Označit jako vyřešené") {
                actions.setResolved(thread, !thread.isResolved)
            }
            .buttonStyle(.bordered)
            .font(.system(size: 11.5))
            .disabled(actions.block != nil || state?.isBusy == true)
            .help(actions.block ?? (thread.isResolved
                ? "Otevře vlákno zpátky na GitHubu"
                : "Označí vlákno na GitHubu za vyřešené"))
        }
    }

    /// Co se nepovedlo, a co s tím.
    ///
    /// **Věta o zachovaném textu jen tam, kde nějaký je** (`keptText`) — u selhaného vyřešení
    /// není co zachraňovat a „text zůstal“ by tvrdilo víc, než se stalo. U odpovědi je naopak
    /// zásadní: bez ní se rozepsaná věta začne psát znovu.
    @ViewBuilder private var failureNote: some View {
        if let state, let failure = state.failure {
            Label {
                Text(verbatim: state.keptText
                    ? "\(failure.userDescription) Text zůstal, dá se zkusit znovu."
                    : failure.userDescription)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.orange)
        }
    }

    private var state: ThreadActionState? { actions?.state(thread) }

    private func hasText(_ actions: ThreadActions) -> Bool {
        !actions.reply(thread).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func busyLabel(_ state: ThreadActionState) -> String {
        switch state {
        case .replying: "odesílám odpověď…"
        case .resolving(let resolved): resolved ? "označuji za vyřešené…" : "otevírám zpátky…"
        // Selhání se hlásí větou pod tlačítky, ne popiskem u spinneru — ten už není vidět.
        case .replyFailed, .resolutionFailed: ""
        }
    }

    // MARK: - Vzhled

    /// Vyřešené vlákno je bledší — je to historie, ne něco k vyřízení. Nemaže se
    /// z pohledu, stejně jako se nemažou zastaralé záznamy nálezů.
    /// Do hlavičky se vejde jeden řádek, takže se konce řádků nahradí mezerou — jinak by
    /// odřádkovaný komentář hlavičku roztáhl a rozvržení bublin by poskakovalo.
    private func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
