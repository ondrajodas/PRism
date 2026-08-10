import SwiftUI

/// Vlákno konverzace z GitHubu, zavěšené pod svým řádkem.
///
/// Vypadá jinak než bublina nálezu schválně: nález je tvrzení naší aplikace, tohle je to,
/// co napsal člověk. Kdyby se to kreslilo stejně, splynulo by to — a „reviewer nahlásil
/// ztrátu dat“ a „kolega se ptá, proč tady není test“ jsou různě vážné věci.
///
/// **Karta z vodorovných pruhů** (#216), jak ji kreslí návrh: hlavička, úryvek, každý komentář
/// a pole na odpověď jsou pásy oddělené linkou, hlavičky na vyvýšené ploše. Do #216 to byl
/// jeden blok s jedním odsazením, ve kterém se úryvek slil s komentářem pod ním.
struct ThreadBubbleView: View {
    /// Kde bublina visí. Rozhoduje o dvou věcech, které se odsud jinak nedají poznat —
    /// co je v hlavičce a jestli se kreslí úryvek kódu.
    enum Placement {
        /// Pod svým řádkem v diffu. Cestu i kód má nad sebou, takže je neopakuje.
        case code
        /// Samostatně na ose konverzace (#183). Nad ní žádný kód není, takže si musí říct
        /// místo sama a úryvek si nakreslit taky.
        case timeline
    }

    let thread: ReviewThread
    /// Přihlášený uživatel — kvůli odlišení mých komentářů. Prázdný, dokud se konverzace
    /// nenačte; pak nic za moje označené není, což je lepší než označit cizí.
    var viewer: String = ""
    var isExpanded = true
    var toggle: (() -> Void)?
    /// Odsazení zleva. Výchozí hodnota míří do sloupce s obsahem vedle čísel řádků, protože
    /// u kódu bublina visí pod svým řádkem. Na ose konverzace (#72, #183) žádná čísla nejsou,
    /// takže se tam předává nula — jinak by vlákno viselo o sto bodů vpravo bez důvodu.
    var indent: Double = DiffLineView.contentInset(for: .unified)
    /// Odpovídání a vyřešení (#73). `nil` = bublina je jen ke čtení, což je stav, ve kterém se
    /// staví v testech skládání řádků a v náhledech.
    var actions: ThreadActions?
    var placement: Placement = .code

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                if let snippet {
                    separator
                    ThreadSnippetView(snippet: snippet, path: thread.path)
                }
                ForEach(Array(thread.comments.items.enumerated()), id: \.element.id) { _, comment in
                    separator
                    entry(comment)
                }
                if thread.comments.isTruncated {
                    separator
                    truncationNote
                }
                compose
            }
        }
        .filling(alignment: .leading)
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
        .padding(.leading, indent)   // u kódu do sloupce s obsahem, na ose nula
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    /// Úryvek kódu k vláknu (#158) — **jen na ose**. U kódu ho kreslit nemá cenu: tentýž kus
    /// souboru je nad bublinou vidět v diffu.
    private var snippet: ThreadSnippet? {
        guard placement == .timeline else { return nil }
        return Policy.snippet(of: thread, context: Policy.timelineSnippetContext)
    }

    /// Linka mezi pruhy karty. `Divider()` bere barvu ze systému, kdežto tady má být
    /// `--line-soft` z palety — jako oddělovače uvnitř ploch všude jinde v okně.
    private var separator: some View {
        Rectangle().fill(Palette.lineSoft).frame(height: 1)
    }

    // MARK: - Hlavička

    /// Klikací celá, ne jen šipka: sbalené vyřešené vlákno je úzký pruh a trefit se do
    /// deseti bodů šipky je zbytečná práce.
    private var header: some View {
        Button {
            toggle?()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink3)
                headline
                // Zastaralé vlákno **musí být poznat**: visí na řádku, který v dnešním diffu
                // není, takže bez odznaku vypadá jako připomínka k dnešnímu kódu. Do #216 to
                // hlásil řádek nad bublinou, který se přesunem dovnitř ztratil.
                if thread.isOutdated { outdatedBadge }
                if thread.isResolved { resolvedBadge }
                // I ve **sbalené** hlavičce: vyřešené vlákno je sbalené výchozím stavem,
                // takže bez tohohle by useknuté vlákno vypadalo úplné a nebyl by důvod ho
                // otevřít. Utnutá data nesmí vypadat jako úplná ani na jeden pohled.
                if thread.comments.isTruncated { truncationBadge }
                Spacer(minLength: 0)
            }
            .narrowingWidth(by: 22)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .filling(alignment: .leading)
            .background(Palette.raised)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(toggle == nil)
    }

    /// Co je v hlavičce napsané, rozhoduje `placement`:
    ///
    /// - **na ose** cesta a řádek. Nad bublinou žádný kód není, takže jinak se nedá poznat,
    ///   o kterém místě je řeč.
    /// - **u kódu** náhled prvního komentáře, když je vlákno sbalené. Cesta je v hlavičce
    ///   souboru o kus výš, takže v každé bublině pod ním by ji okno psalo podruhé — a sbalené
    ///   vlákno naopak musí ze hlavičky říct, co v něm je, jinak není důvod ho otevřít.
    @ViewBuilder private var headline: some View {
        switch placement {
        case .timeline:
            Text(verbatim: location)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .truncationMode(.head)
        case .code:
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
            Text(verbatim: title)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
        }
    }

    /// Kde vlákno visí — `soubor:řádek`. U zastaralého je číslo z `originalLine`, protože `line`
    /// mají prázdné právě ta (ověřeno na `cli/cli#13084`: 24 ze 38).
    private var location: String {
        guard let line = thread.anchorLine else { return thread.path }
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
        // Do hlavičky se vejde jeden řádek, takže se konce řádků nahradí mezerou — jinak by
        // odřádkovaný komentář hlavičku roztáhl a rozvržení bublin by poskakovalo.
        return "\(first.author): \(first.body.singleLine)"
    }

    private var resolvedBadge: some View {
        Text("vyřešeno")
            .font(.system(size: 10.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.green.opacity(0.18), in: .capsule)
            .foregroundStyle(.green)
    }

    /// Podklad je `line`, ne `raised`: odznak leží v hlavičce, která na `raised` už je,
    /// takže ve stejné barvě by zmizel. V návrhu je odznak i pruh `--panel-3` — a právě proto
    /// v něm není odznak vidět.
    private var outdatedBadge: some View {
        Text("zastaralé")
            .font(.system(size: 10.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Palette.line, in: .capsule)
            .foregroundStyle(Palette.ink2)
            .help("Řádek, u kterého vlákno vzniklo, v aktuálním diffu není")
    }

    /// Kolik komentářů se do stránky nevešlo. Číslo, ne jen ikona — „chybí něco“ nedává
    /// důvod jít na GitHub, „chybí 12“ ano.
    private var truncationBadge: some View {
        Text(verbatim: "+\(thread.comments.missing)")
            .font(.system(size: 10.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Palette.stale.opacity(0.18), in: .capsule)
            .foregroundStyle(Palette.stale)
            .help("Další komentáře se nevešly — otevři vlákno na GitHubu.")
    }

    // MARK: - Komentář

    private func entry(_ comment: ThreadComment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // **Jméno vlevo, čas vpravo** (#216), jak to má návrh: slepené k sobě se čtou jako
            // jeden údaj a čas se ztrácí mezi jmény.
            HStack(spacing: 6) {
                AvatarView(login: comment.author, url: nil, size: 16)
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
            .narrowingWidth(by: 22)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .filling(alignment: .leading)
            // Hlavička komentáře **bez linky pod sebou** — na rozdíl od hlavičky celé karty.
            // Uvnitř vlákna je linka oddělovač mezi komentáři, takže druhá hned pod jménem by
            // rozdělila jeden komentář na dva pruhy.
            .background(Palette.raised)

            // **Bez `.textSelection(.enabled)`**, i když je to text, který si člověk chce
            // zkopírovat. Bublina je buňka líného seznamu nad diffem a tam je selekce
            // podle CLAUDE.md druhý zdroj nevykreslených řádků — `FindingBubbleView` ho
            // ze stejného důvodu nemá. Kopíruje se z GitHubu, kam vede odkaz výš.
            //
            // Markdown se renderuje: komentáře na GitHubu se v něm píšou a `**takhle**`
            // s dvojitými hvězdičkami se čte špatně.
            MarkdownText(text: comment.body, font: .system(size: 12.5))
                .narrowingWidth(by: 22)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .filling(alignment: .leading)
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
    private var truncationNote: some View {
        // Sloveso je **v tvarech**: „2 komentáře se nevešlo“ je špatně česky.
        Text(verbatim: Plural.czech(
            thread.comments.missing,
            one: "komentář se nevešel",
            few: "komentáře se nevešly",
            many: "komentářů se nevešlo"
        ) + " — otevři vlákno na GitHubu.")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.stale)
            .narrowingWidth(by: 22)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .filling(alignment: .leading)
    }

    // MARK: - Odpověď (#73)

    /// Pole na odpověď a tlačítka pod ním.
    ///
    /// **Bez potvrzování** — rozhodnutí #73: odpověď je jedna věta v diskuzi, dá se smazat
    /// a potvrzovací sheet u každé by z okna udělal klikačku. Review se potvrzuje proto, že je
    /// to verdikt nad celým PR.
    @ViewBuilder private var compose: some View {
        if let actions {
            separator
            // **Avatar vedle pole a pole na jeden řádek** (#216). Velký box přes celou
            // šířku vypadá jako hlavní věc v bublině, přitom hlavní je ten komentář nad ním.
            HStack(alignment: .top, spacing: 8) {
                AvatarView(login: viewer, url: nil, size: 16)
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
            .padding(.horizontal, 11)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 6) {
                controls(actions)
                failureNote
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 9)
        }
    }

    private func controls(_ actions: ThreadActions) -> some View {
        HStack(spacing: 7) {
            replyButton(actions)
            resolutionButton(actions)
            Spacer(minLength: 8)
            if let state, state.isBusy {
                ProgressView().controlSize(.small)
                Text(verbatim: busyLabel(state))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
            } else if thread.comments.items.count > 1 {
                // Počet odpovědí u pravé hrany, jak ho má návrh — z vlákna je pak vidět,
                // kolik toho je, i bez čtení. Ustoupí tomu, co se právě děje: dva údaje
                // na jednom místě by se přebíjely.
                Text(verbatim: Plural.czech(
                    thread.comments.items.count - 1,
                    one: "odpověď",
                    few: "odpovědi",
                    many: "odpovědí"
                ))
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
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
            .font(.system(size: 11))
            .foregroundStyle(Palette.stale)
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
}
