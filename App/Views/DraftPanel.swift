import SwiftUI

/// Tab `Moje review` ve spodním panelu: verdikt, tělo review a seznam řádkových komentářů.
///
/// Je to **domov draftu** — v diffu jsou vidět jen komentáře, které se dají zakotvit, takže
/// tady je jediné místo, kde je vidět celý obsah toho, co se odešle. Komentář na řádku, který
/// v aktuálním diffu není (přišel nový commit), by jinak nešlo ani najít, ani smazat.
///
/// Odeslat se odsud dá, ale **jen otevřením potvrzení** (#68): tlačítko `Odeslat review…`
/// složí `ReviewSubmission` a ukáže sheet, ve kterém je vidět celý payload. Publisher se
/// z tohohle souboru nevolá.
struct DraftPanel: View {
    /// Ke kterému PR panel patří. Není to jen popisek: visí na tom identita editoru těla,
    /// a ta rozhoduje, kam se doručí rozepsaný text při přepnutí PR.
    let pullRequest: PRIdentifier
    let draft: ReviewDraft?
    /// Verdikt, který platí — moje volba, nebo **návrh z nálezů** (#114). `nil` = nevybráno
    /// a není z čeho navrhnout.
    ///
    /// Nebere se z `draft.verdict`: návrh v draftu není (neukládá se), takže by panel ukazoval
    /// „nevybráno“ nad hodnotou, která by odešla.
    var verdict: EffectiveVerdict?
    /// Je draft psaný proti staršímu commitu, než je hlava PR?
    var isStale = false
    /// Je to můj vlastní PR? Pak se návrh nepředvyplňuje a panel to musí vysvětlit.
    var isOwnPullRequest = false
    /// Proč se do draftu nedá psát. `nil` = dá se.
    var unavailable: String?
    /// Věta o návrhu, který složila aplikace (#520). `nil` = žádný návrh se neskládal, nebo se
    /// zahodil — pak se pruh **nekreslí vůbec**, ne prázdný.
    var autoDraftNote: String?
    var autoDraftActions = AutoDraftActions()
    var actions = DraftActions()
    var jump: (ReviewDraftComment) -> Void = { _ in }

    @State private var isConfirmingDiscard = false

    /// Otevřená nabídka emotikonů v těle review (#483). Drží ji panel, protože **on tu nabídku
    /// kreslí** — nad svým `ScrollView`em, ne uvnitř: uvnitř by se ořízla o jeho horní hranu
    /// a tělo review leží zrovna nahoře (změřeno, viz `EmojiSuggestionBox`). Nad panelem je
    /// hlavička, labely a segmenty, tedy dost místa a žádný ořez.
    @State private var emoji = EmojiSuggestionBox()

    /// Výška, kterou panel doopravdy má — z ní se počítá, jestli se obsah ještě vejde.
    /// Jen měření (`onGeometryChange`), takže do rozvržení nezasahuje; `GeometryReader` by
    /// naopak sám zabral místo, a v tomhle okně už to jednou uškodilo.
    @State private var available = 0.0

    /// Obsah **scrolluje, ale jen když se nevejde**.
    ///
    /// Panel je pruh s výškou, kterou si uživatel vytáhne, kdežto draft má svoje minimum
    /// (banner o zastarání, verdikt, dva editory). Bez scrollu obsah v nízkém panelu **přetékal
    /// přes záložky nad sebou** — nahlášené při zkoušení #69, kde banner vyrostl o tlačítko.
    /// Samotné `clipped()` by ho jen schovalo, což je ta horší polovina téhož problému.
    ///
    /// `minHeight` z měřené výšky drží obojí: dokud se obsah vejde, vyplní panel jako dřív
    /// (editor roste s pruhem), a jak přeteče, začne se scrollovat. Zpětná vazba to není —
    /// výška `ScrollView`u přichází od panelu, ne od obsahu.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // **Úplně nahoře, nad bannerem o zastarání** (#520): pruh vysvětluje, **odkud je
                // všechno pod ním**, kdežto banner mluví o tom, že to nejde odeslat. Kdo čte panel
                // shora dolů, potřebuje to v tomhle pořadí — a obojí naráz je legitimní stav.
                if let autoDraftNote {
                    AutoDraftNoteView(note: autoDraftNote, actions: autoDraftActions)
                }
                if isStale { staleBanner }
                if let unavailable { unavailableNote(unavailable) }
                topRow
                if let ownPullRequestNote { unavailableNote(ownPullRequestNote) }
                if let sendBlockNote { unavailableNote(sendBlockNote) }
                if let suggestionOnlyNote { unavailableNote(suggestionOnlyNote) }
                editors
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: available, alignment: .topLeading)
        }
        .onGeometryChange(for: Double.self) { $0.size.height } action: { available = $0 }
        // **Nad `ScrollView`em, ne nad polem** (#483): tělo review je první věc ve scrollu, takže
        // nabídka nad polem by se uřízla o jeho horní hranu. Odsud se kreslí přes hlavičku panelu.
        .emojiMenuAbove { EmojiSuggestionMenu(suggestions: emoji) }
    }

    // MARK: - Hlavička

    /// Zastaralý draft se **nemaže** — jen se nedá odeslat rovnou. Vlastní próza je dražší než
    /// strojový nález, takže se nechává s poctivým příznakem.
    ///
    /// Banner **vlastní tlačítko nemá** (rozhodnuto při zkoušení #69): kontrola kotev je první
    /// stránka okna, které otevře `Zkontrolovat a odeslat…`, takže druhé tlačítko na totéž by
    /// znamenalo, že je jedno z nich pořád k ničemu. Text proto ukazuje na to, které tam je.
    private var staleBanner: some View {
        Label {
            Text(staleText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(Palette.find)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.find.opacity(0.1), in: .rect(cornerRadius: 6))
    }

    /// Věta se mění podle toho, jestli je proti čemu kontrolovat: bez diffu nebo bez známé hlavy
    /// PR se přenést nedá a slibovat cestu, která není, by bylo horší než říct, že se čeká.
    private var staleText: String {
        actions.canTransfer
            // Krátce schválně: co se s tím dělá, říká tlačítko vedle, a delší věta zvedala
            // minimální výšku panelu (banner se roztáhl na tři řádky).
            ? "Review je psané proti staršímu commitu. Kotvy zkontroluješ v okně, které otevře „Zkontrolovat a odeslat…“ — text zůstává, nic se nemaže."
            : "Review je psané proti staršímu commitu, než je teď v PR. Odeslat se takhle nedá — komentáře by sedly na jiný kód. Text zůstává, nic se nemaže."
    }

    private func unavailableNote(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Verdikt a tlačítka **pod sebou** (#182): v panelu 300 bodů širokém se `Změny z návrhu`
    /// vedle `Odeslat review` nevejde a segmentovaný přepínač by se zmáčkl na tři písmena.
    private var topRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            verdictPicker
            if draft != nil {
                HStack(spacing: 8) {
                    sendButton
                    Spacer(minLength: 4)
                    discardButton
                }
            }
        }
    }

    /// Otevře potvrzení, **neodesílá**.
    ///
    /// U zastaralého draftu, který se dá přenést (#69), tlačítko **zakázané není** — jmenuje se
    /// jinak a okno začne kontrolou kotev. Zakázané zůstává tam, kde se s tím v okně nedá nic
    /// udělat (chybí verdikt, prázdný komentář, nepovolené odesílání): oprava patří do panelu.
    private var sendButton: some View {
        Button(sendLabel, systemImage: "paperplane") { actions.send() }
            .buttonStyle(.borderedProminent)
            .font(.callout)
            .disabled(!canOpenSubmission)
            .help(canOpenSubmission
                ? "Ukáže, co přesně odejde na GitHub — odeslat se potvrzuje až tam"
                : actions.sendBlock?.userDescription ?? "")
    }

    private var sendLabel: String {
        needsTransfer ? "Zkontrolovat a odeslat…" : "Odeslat review…"
    }

    /// Zastarání je jediný důvod, se kterým se dá něco udělat **v tom okně** — proto se jím
    /// tlačítko nezakazuje.
    ///
    /// Obojí rozhoduje `Policy`, ne panel: od #151 se na totéž ptá i zkratka `⌘⏎` v detailu PR,
    /// a dvě kopie téhle podmínky by znamenaly, že zkratka otevře okno nad zakázaným tlačítkem.
    private var needsTransfer: Bool {
        Policy.needsTransfer(block: actions.sendBlock, canTransfer: actions.canTransfer)
    }

    private var canOpenSubmission: Bool {
        Policy.canOpenSubmission(block: actions.sendBlock, canTransfer: actions.canTransfer)
    }

    /// Proč se odeslat nedá, větou pod lištou.
    ///
    /// Zastarání se tady **neopakuje**: má vlastní banner nahoře a dvě hlášky o téže věci
    /// pod sebou čtou jako dva různé problémy. Bez draftu není co odesílat a tlačítko není
    /// vidět, takže ani ten důvod nemá co říkat.
    private var sendBlockNote: String? {
        guard draft != nil, let block = actions.sendBlock else { return nil }
        if case .stale = block { return nil }
        return block.userDescription
    }

    /// Předvyplněný návrh **sám review nezakládá** (#114), takže tlačítko odeslat zatím není.
    ///
    /// Návrh se neukládá, takže „draft existuje“ dál znamená „je co poslat“ — na tom stojí
    /// indikátor v řádku seznamu i mazání prázdného draftu. Bez téhle věty by chybějící tlačítko
    /// nad předvyplněným verdiktem vypadalo jako závada; s ní je z ní vidět, že stačí jedno
    /// kliknutí. Ukazuje se jen v tom jednom stavu, kdy je co vysvětlovat.
    private var suggestionOnlyNote: String? {
        guard draft == nil, verdict?.isSuggested == true else { return nil }
        // Neslibuje se, že odeslání **půjde**: brána na repo, zastarání ani neznámá hlava PR
        // odsud vidět nejsou, takže „a půjde odeslat“ by tvrdilo víc, než tahle věta ví.
        return "Návrh je předvyplněný, ale rozdělané review ještě neexistuje — poslat se dá teprve to. Založíš ho kliknutím na verdikt, tělem review nebo komentářem."
    }

    /// Verdikt **předvyplněný návrhem z nálezů** (#114) — do té doby se nepředvyplňoval vůbec.
    ///
    /// Změnilo se to proto, že ochrana proti záměně verdiktu neleží v tom kliknutí, ale za ním:
    /// potvrzovací sheet s úplným výpisem payloadu, tlačítko pojmenované akcí, které **není
    /// výchozí**, a pre-flight na `headSha`. Klik v panelu byl proti tomu duplikát, který
    /// v převažující většině případů opisoval, co aplikace už spočítala. Co se jím chránilo,
    /// zůstalo: z okna je pořád vidět, jestli je hodnota moje volba, nebo návrh.
    ///
    /// Tři tlačítka místo `Pickeru`: ten musí mít vybranou hodnotu, takže by v něm musela být
    /// čtvrtá, falešná („nevybráno“) — a hodnota, kterou GitHubu posílám jako `event`, se od
    /// návrhu aplikace musí dát odlišit na první pohled.
    /// Tři **stejně široká** tlačítka bez předsazeného „Verdikt:“ (#182), jak je má návrh.
    /// V panelu 300 bodů širokém je popisek to jediné, co se do třetiny šířky musí vejít —
    /// a `Verdikt:` před nimi ubíralo místo tomu, co nese význam.
    private var verdictPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(ReviewDraft.Verdict.allCases, id: \.self) { choice in
                    verdictButton(choice)
                }
            }
            if let verdictCaption {
                Text(verbatim: verdictCaption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Popisek za tlačítky. U mojí volby žádný — to říká vyplněné tlačítko se zaškrtnutím.
    private var verdictCaption: String? {
        switch verdict?.origin {
        case .chosen: nil
        case .suggested: "návrh z nálezů"
        case nil: "nevybráno"
        }
    }

    /// **Vybráno je vyplněné a se zaškrtnutím, návrh jen obtažený, nevybráno bez barvy.**
    ///
    /// Je to hodnota, která jde do `event` — tedy to, co GitHub s PR udělá. Rozdíl mezi „aplikace
    /// hádá“ a „rozhodl jsem“ proto nemá stát jen na odstínu: barvy se v tmavém režimu i u
    /// barvosleposti sbíhají a splést si `Vyžádat změny` se `Schválit` je ta nejdražší záměna,
    /// jakou tohle okno umí. Vyplnění se zaškrtnutím zůstává vyhrazené **mé** volbě, takže se
    /// tvar, ikona i popisek za tlačítky mění naráz.
    @ViewBuilder private func verdictButton(_ choice: ReviewDraft.Verdict) -> some View {
        let origin = verdict?.verdict == choice ? verdict?.origin : nil
        let isChosen = origin == .chosen
        let button = Button {
            // Druhé kliknutí volbu ruší — jinak by se vybraný verdikt nedal vzít zpátky
            // a draft by šel zrušit jedině celý. Zrušená volba spadne zpátky na návrh, ne na
            // „nevybráno“: návrh platí, dokud si nevyberu.
            actions.setVerdict(isChosen ? nil : choice)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : choice.symbolName)
                    .imageScale(.small)
                Text(verbatim: choice.shortLabel)
                    .lineLimit(1)
            }
            .font(isChosen ? .callout.weight(.semibold) : .callout)
            // Stejný díl šířky pro každé tlačítko, jak to má návrh (`.vbtn { flex: 1 }`) —
            // jinak si `Schválit` vezme víc než `Změny` a řada vypadá jako překlep.
            .frame(maxWidth: .infinity)
        }
        .disabled(unavailable != nil)
        .help(help(for: choice, origin: origin))

        switch origin {
        case .chosen:
            button.buttonStyle(.borderedProminent).tint(choice.tint)
        case .suggested:
            // Obtažení kreslí `overlay`, ne `tint`: ten u `.bordered` obarví text a to je zase
            // jen odstín. Poloměr sedí na tvar macOS tlačítka — vyladěné na offscreen renderu.
            button
                .buttonStyle(.bordered)
                .tint(choice.tint)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(choice.tint, lineWidth: 1.5)
                }
        case nil:
            button.buttonStyle(.bordered).tint(.secondary)
        }
    }

    /// Nápověda říká, **co se stane** — a u předvyplněného návrhu i to, že ho nikdo nevybral.
    private func help(for choice: ReviewDraft.Verdict, origin: EffectiveVerdict.Origin?) -> String {
        guard origin != .suggested else {
            // Podmíněně („kdyby odešlo“) schválně: jestli odeslat vůbec jde, rozhoduje
            // `Policy.sendBlock`, a to odsud vidět není.
            return "Návrh z nálezů: kdyby review odešlo teď, půjde jako \(choice.rawValue). Kliknutím si verdikt vybereš sám."
        }
        switch choice {
        case .approve: return "Odešle review jako APPROVE"
        case .requestChanges: return "Odešle review jako REQUEST_CHANGES"
        // Že je `COMMENT` na vlastním PR ta **jediná** možnost, patří do `ownPullRequestNote` —
        // ukáže se přesně tam, kde to platí. V nápovědě to od #114 stálo mimo kontext a dalo se
        // přečíst obráceně, totiž že `COMMENT` jinde než na vlastním PR nejde (nález Copilota
        // na #128). Nápověda proto říká jen, co ta volba udělá.
        case .comment: return "Odešle review bez verdiktu (COMMENT) — vědomé „nerozhoduju“"
        }
    }

    /// Na vlastním PR bere GitHub jedině `COMMENT` (změřeno u #62: `APPROVE`
    /// i `REQUEST_CHANGES` vrátí 422), takže se návrh **nepředvyplňuje** (#114).
    ///
    /// Bez téhle věty by chybějící návrh u doběhlého review vypadal jako rozbitá aplikace —
    /// všude jinde se předvyplní. Tlačítka zůstávají povolená schválně: kdo se dívá, víme jen
    /// z načtené konverzace, a tlačítko zakázané podle údaje, který nemusí dorazit, slibuje
    /// méně než chyba od GitHubu, která si o `Jen komentář` řekne sama.
    private var ownPullRequestNote: String? {
        guard isOwnPullRequest else { return nil }
        return "Tohle je tvůj PR: GitHub na něm přijme jedině „Jen komentář“. Schválit ani vyžádat změny na vlastním PR nejde, takže se návrh z nálezů nepředvyplňuje."
    }

    private var discardButton: some View {
        Button("Zahodit review", systemImage: "trash") {
            isConfirmingDiscard = true
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .confirmationDialog(
            "Zahodit rozdělané review?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Zahodit", role: .destructive) { actions.discard() }
            Button("Zpět", role: .cancel) {}
        } message: {
            Text("Tělo, verdikt i všechny řádkové komentáře. Zpátky to nejde.")
        }
    }

    // MARK: - Obsah

    /// Tělo nahoře, komentáře pod ním (#182).
    ///
    /// **Změna proti #66**, kde to bylo vedle sebe: tehdy byl panel nízký pruh přes celé okno,
    /// takže pod sebou by se mezi dvěma věcmi, které se píšou naráz, muselo scrollovat. Od #182
    /// je panel svislý a 300 bodů široký — vedle sebe by na tělo review zbylo míň, než je jeden
    /// řádek věty.
    private var editors: some View {
        VStack(alignment: .leading, spacing: 12) {
            bodyEditor
            comments
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tělo review")
                .font(.caption)
                .foregroundStyle(.secondary)
            DraftTextEditor(
                text: draft?.body ?? "",
                placeholder: "Souhrn k celému PR. Nálezy mimo diff se sem přidají jako odkaz na kód.",
                minHeight: 80,
                // Emotikony s našeptáváním (#483) — druhé ze tří polí. Nabídku kreslí `body`, ne
                // tohle pole: uvnitř `ScrollView`u by se ořízla.
                suggestions: emoji,
                commit: actions.setBody
            )
            .disabled(unavailable != nil)
            // **Identita per PR, ne per draft.** Panel si SwiftUI mezi pull requesty ponechá
            // (stejná pozice ve stromu), takže bez tohohle by přepnutí PR jen změnilo `text`
            // — a rozepsaná věta by se tiše zahodila. S vlastní identitou se editor zahodí
            // a v `onDisappear` doručí, co v něm bylo. Klíčovat draftem nejde: ten vzniká
            // až prvním uložením, takže by se identita měnila **během** psaní.
            .id(pullRequest)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: commentsTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if commentList.isEmpty {
                Text("Komentář přidáš tlačítkem, které se objeví na řádku diffu, nebo převzetím nálezu z bubliny.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                sharedAnchorNote
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commentList) { comment in
                            commentRow(comment)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var commentList: [ReviewDraftComment] { draft?.comments ?? [] }

    /// Dva komentáře na jednom řádku **nedají odpověď**, ale dvě samostatná vlákna.
    ///
    /// Je to jediná věc na téhle obrazovce, kterou se dá čekat a nestane se: člověk připíše
    /// druhý komentář k témuž řádku s tím, že navazuje na první. Změřeno u #73, že GitHub z toho
    /// udělá dvě vlákna — takže než aby to bylo překvapení až na PR, řekne se to tady.
    ///
    /// Odpovídat **jde**, jen až potom: z odeslaného komentáře se stane vlákno a v něm už je
    /// tlačítko `Odpovědět`.
    @ViewBuilder private var sharedAnchorNote: some View {
        let lines = Policy.linesWithSeveralComments(in: draft)
        if lines > 0 {
            Label {
                // Mluví se o **řádcích**, ne o počtu komentářů: dvě různé kotvy po dvou
                // komentářích nejsou „čtyři komentáře na stejném řádku“. Chytil to Copilot.
                Text(verbatim: "\(Plural.czech(lines, one: "Na jednom řádku", few: "Na \(lines) řádcích", many: "Na \(lines) řádcích")) máš víc komentářů — odejdou jako samostatná vlákna, ne jako odpověď. Odpovědět půjde, až review odešleš.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commentsTitle: String {
        commentList.isEmpty
            ? "Komentáře k řádkům"
            : "Komentáře k řádkům · \(commentList.count)"
    }

    private func commentRow(_ comment: ReviewDraftComment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                jump(comment)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // Zepředu, ať zůstane jméno souboru a číslo řádku — stejně jako ve
                        // sloupci `Místo` v tabulce nálezů.
                        Text(verbatim: Policy.location(of: comment))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                        if comment.origin.reviewer != nil {
                            Image(systemName: "text.magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Vznikl převzetím nálezu")
                        }
                    }
                    Text(verbatim: preview(of: comment))
                        .font(.caption)
                        .foregroundStyle(comment.body.isEmpty ? Palette.find : .secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Odskočit na komentář v diffu")

            Button("Vyjmout", systemImage: "trash") {
                actions.removeComment(comment.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Vyjmout komentář z rozdělaného review")
        }
        .padding(.vertical, 6)
    }

    private func preview(of comment: ReviewDraftComment) -> String {
        // „Zahodí se“, ne „neuloží se“: v draftu prázdný komentář chvíli je, jen nepřežije
        // odchod z bubliny ani restart. Tatáž věta je i v bublině a musí říkat totéž.
        guard !comment.body.isEmpty else { return "prázdný — zahodí se" }
        return comment.body.singleLine
    }
}
