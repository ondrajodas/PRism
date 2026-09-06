import SwiftUI

/// Sekce `Větev` v pravém panelu (#465) — **pod labely a reviewery**, jak to kreslí návrh
/// (sekce 36).
///
/// Nese **stav** (kam se to slévá, jestli je větev srovnaná a o kolik je pozadu, jak dopadly
/// checky) a k němu **akce, které z toho stavu plynou** — `Mergnout…` (#465) a `Rebase` (#466)
/// v jedné řadě, obě vidět vždycky (mění se jen to, která z nich je hlavní), a nad nimi
/// `Připravit k review` (#482) **přes celou šířku**.
///
/// **Třetí akce do té řady nepatří, a je to změřené** (návrh sekce 37). Zákres tam počítá **279
/// bodů z 278**, tedy o jediný bod ven; **přeměřeno aplikací vychází o pár bodů jinak a rozhoduje
/// to jinde**, ne v zákresu:
///
/// - `TextWidth.miniButton` (tedy řez a odsazení, na kterých `.mini` doopravdy kreslí) dává
///   `Připravit k review` 114/117 b, `Mergnout…` 82/84 a `Rebase` 61/62 podle zdůraznění, takže tři
///   v řadě s dvěma mezerami po 7 jsou **273–274 b**.
/// - Panel má na obsah `contentWidth(inPanelOf:)`, tedy **274 b** ve výchozí šířce 300 (odsazení je
///   13 na stranu, ne 11 jako v CSS zákresu) a **214 b** na podlaze 240.
///
/// Ve výchozí šířce to tedy sedne **přesně na hranu — nula až jeden bod rezervy**, což je pro řadu,
/// ve které se popisky mohou změnit, totéž jako nevejít se. **Na podlaze panelu to přetéká o ~60
/// bodů**, a tam žádné zkrácení popisky nepomůže. Vlastní řádek přes celou šířku je proto jediné
/// místo, kde se akce vejde **při každé šířce** — a shodou okolností i to správné místo: sedí
/// u důvodu, který odklízí.
///
/// **Kreslí se jedině nad draftem** (`Policy.ReadyOffer.absent` všude jinde), takže nad otevřeným,
/// zavřeným ani mergnutým PR není v sekci o řádek víc.
///
/// **Nekreslí se na cizím PR** — rozhoduje o tom `Policy.branchSection`, které vrátí `nil`.
/// Mergnout cizí frontu se odsud nedělá nikdy, takže tam není ani nadpis, natož zašedlé tlačítko;
/// zašedlé s důvodem patří jedině tam, kde se stav **mění** (červený check, větev pozadu, vypnutá
/// brána). Tatáž hranice jako u labelů (#392).
struct PanelBranchView: View {
    let section: Policy.BranchSection
    /// Šířka, kterou má panel na obsah — **spočítaná, ne vyjednaná** (pravidlo #220).
    let contentWidth: Double
    /// Co se právě děje se srovnáním větve (#466). `nil` = nic se nedělo.
    var syncState: BranchSyncState?
    /// Co session nad konflikty zrovna dělá (#467) — **druhý řádek**, ne součást věty o stavu:
    /// mění se při každém kroku session, kdežto stav zůstává.
    var syncActivity: String?
    /// Co se právě děje s metadaty PR (#482). Sekci zajímá **jediný** z jeho případů —
    /// `readyFailed`, tedy věta pod tlačítkem `Připravit k review`; ostatní kreslí blok labelů.
    /// Rozhoduje o tom `MetadataActionState.noticePlace`, ne tenhle panel.
    var actionState: MetadataActionState?
    var actions = BranchActions()

    /// Odsazení bloku bere **z toho typu, který kreslí sekci nad ním**: dvě konstanty by
    /// znamenaly dvě pravdy o jedné šířce a rozešly by se při prvním doladění.
    private static var insetHorizontal: Double { PanelMetadataView.insetHorizontal }
    private static let insetVertical = 11.0
    /// `gap` mezi řádky stavu, výstrahou a řadou akcí — `.pl-sec` z návrhu má `gap: 6px`,
    /// tlačítka pod ním `margin-top: 2px`.
    private static let contentSpacing = 8.0
    private static let rowSpacing = 6.0
    private static let actionSpacing = 6.0

    var body: some View {
        PanelSection(caption: "Větev") {
            VStack(alignment: .leading, spacing: Self.contentSpacing) {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    // Řádky jsou z `Policy` a je jich pevný počet, takže `id: \.offset` nekopíruje
                    // payload ani nesplácne dva stejné texty do jednoho (pravidlo #361).
                    ForEach(Array(section.facts.enumerated()), id: \.offset) { fact in
                        row(fact.element)
                    }
                }
                if !warnings.isEmpty { warning }
                // **Nad řadou akcí, pod výstrahou** (návrh sekce 37): sedí u toho důvodu, který
                // odklízí. Do řady s `Mergnout…` a `Rebase` nepatří — tři tlačítka `.mini` vedle
                // sebe potřebují 273–274 bodů, což je celá šířka obsahu panelu (274 b) a o ~60
                // bodů víc, než na kolik má panel na podlaze (214 b). Čísla a jak se měřila jsou
                // u typu výš.
                if section.ready.isVisible { readySection }
                actionRow
                if let syncState { syncNotice(syncState) }
            }
        }
        .padding(.horizontal, Self.insetHorizontal)
        .padding(.vertical, Self.insetVertical)
        .frame(width: contentWidth + 2 * Self.insetHorizontal, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Řádek stavu: popis vlevo, odpověď vpravo.
    ///
    /// Když se panel zúží, ustoupí **popis** (ořeže se) a odpověď zůstává celá — tatáž úmluva
    /// jako u reviewera, a ze stejného důvodu: kvůli odpovědi se na sekci kouká. Drží to
    /// `fixedSize` na odpovědi.
    private func row(_ fact: Policy.BranchFact) -> some View {
        HStack(spacing: 7) {
            Text(verbatim: fact.text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fact.text)
            Spacer(minLength: 4)
            Text(verbatim: fact.answer)
                .font(.system(size: 11))
                .foregroundStyle(color(of: fact.tone))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.text) — \(fact.answer)")
    }

    /// **Barva ze škály se bere z palety, nikdy ze systému** (#432) — `ok` a `crit` jsou tady
    /// text na tlumeném pozadí panelu, ne výplň ovládacího prvku.
    private func color(of tone: Policy.BranchFact.Tone) -> Color {
        switch tone {
        case .neutral: Palette.ink3
        case .done: Palette.ok
        case .blocked: Palette.crit
        }
    }

    /// Proč to nejde — **v panelu, ne jen v nápovědě pod kurzorem**.
    ///
    /// Zašedlé tlačítko bez věty je otázka, na kterou okno neodpovídá (tatáž úvaha jako u vypnuté
    /// brány, #392). Sazba je `.warnbox` z návrhu, tedy tatáž jako u věty o zastaralých nálezech.
    private var warning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // **Ikona je jen vizuální**, takže se z accessibility stromu schová: bez toho ji čtečka
            // přečte jako jméno symbolu (`exclamationmark.triangle`) před větou, která to samé
            // říká slovy. Nález Copilota na #465.
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.stale)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // Důvodů může být víc a **každý vede jinam**, takže se nesčítají do jedné věty:
                // „červený check“ se opraví pushem, „větev je pozadu“ srovnáním, vypnutá brána
                // v nastavení. Sjednocené je to už v `Policy`, tady se jen sází.
                //
                // **Věty jsou ze dvou výčtů**, protože akce jsou dvě — a co z nich do výstrahy
                // patří, rozhoduje `Policy`, ne view (`syncWarnings`): většina překážek srovnání
                // je v panelu napsaná už jinde, takže vypsat je všechny by znamenalo totéž
                // dvakrát. Řetězce jsou proto pole, ne dva `ForEach`e nad různými typy.
                ForEach(Array(warnings.enumerated()), id: \.offset) { warning in
                    Text(verbatim: warning.element)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // `Spacer`, ne `frame(maxWidth: .infinity)` na textu — pružný rámec v zanořeném stromě
            // stojí ~5,5× na úroveň (#220) a tady stačí jedna mezera, která se roztáhne.
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

    // MARK: - Připravit k review (#482)

    /// Tlačítko, věta pod ním a případná chyba — **jeden blok**, protože všechny tři patří k tomu
    /// samému kliknutí.
    private var readySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            readyButton
            if let failure = actionState?.readyFailure {
                readyFailureRow(failure)
            } else {
                // **Věta se schová jen tehdy, když je pod tlačítkem chyba**, ne když se odesílá:
                // dvě věty pod sebou v panelu o 300 bodech se čtou jako dva odstavce a ta chybová
                // je ta, kvůli které se tam kouká. Jinak tam je pořád — je součástí rozhodnutí
                // nepotvrzovat sheetem, ne nápovědou k prvnímu kliknutí.
                readyNote
            }
        }
    }

    /// `Připravit k review` — **přes celou šířku panelu a bez tří teček**, protože nic neotevírá:
    /// odešle to rovnou.
    ///
    /// **Bez potvrzovacího sheetu, a je to úvaha o obsahu, ne o počtu kliknutí.** Sheet je v tomhle
    /// okně u odeslání review (#68) a u mergnutí (#465), a obojí má společné to, že **payload je
    /// dlouhý a aplikace je jediné místo, kde se dá celý přečíst**. Tady je payload **jeden bit**;
    /// sheet, jehož výpis *Co se stane* má jediný řádek, se neptá na obsah, ptá se „opravdu?“ —
    /// a přesně tenhle druh potvrzení repo u labelů, odpovědi do vlákna a komentáře pod PR (#73,
    /// #216, #392) zamítlo ve prospěch **jednoho pojmenovaného tlačítka**.
    ///
    /// **Nevratná část na tom ale je** — přepnutí vyžádá review od vlastníků kódu, tedy odešle
    /// upozornění, které se odebráním nevezme zpět. Odpovídá se na ni tak jako u `+ reviewer`
    /// v #392: slovesem tam, kde se kliká, plus větou pod tlačítkem (`readyNote`).
    ///
    /// **Výchozí akci nemá, a to je podmínka, ne detail**: `keyboardShortcut` tady schválně není
    /// (ani `.defaultAction`), takže se akce nedá spustit `Enterem` při průchodu klávesnicí —
    /// tatáž mez jako u potvrzení merge (#465) a u založení labelu (#413). Hlídá to test nad
    /// zdrojákem, ne jen tenhle komentář.
    ///
    /// Šířka je **předaná, ne vyjednaná** (pravidlo #220): vnější rámec je `contentWidth`, tedy
    /// konkrétní číslo. Pružný rámec je až **uvnitř** něj a jen na popisku — viz komentář u něj.
    private var readyButton: some View {
        Button(action: actions.markReady) {
            // **`maxWidth: .infinity` uvnitř pevného rámce, ne místo něj.** Návrh má `.send` jako
            // plnou plochu přes celou šířku, a `borderedProminent` sám plochu k popisku
            // nedotáhne — bez tohohle by z něj bylo tlačítko na 129 bodů vystředěné v prázdném
            // řádku (změřeno renderem). Zákaz z #220 mluví o **vyjednávání**, a to tady žádné
            // není: `frame(width:)` o řádek níž je konkrétní číslo, takže se nabídka nešíří ani
            // o úroveň dál.
            Text(verbatim: Self.readyTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        // Velikost z návrhu (`.send { font-size: 12.5px }`) — tatáž jako u `Odeslat komentář`,
        // což je v návrhu tentýž tvar.
        .font(.system(size: Self.readyFontSize))
        .frame(width: contentWidth)
        .disabled(!section.ready.isAllowed)
        .help(readyHelp)
    }

    /// Věta pod tlačítkem. **Není to dekorace** — text drží `Policy`, protože je součástí
    /// rozhodnutí nepotvrzovat sheetem.
    private var readyNote: some View {
        Text(verbatim: Policy.readyForReviewNote)
            .font(.system(size: Self.readyNoteFontSize))
            .foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Proč přepnutí nedopadlo — **větou v panelu, ne zmizelým kliknutím**, a pod tím tlačítkem,
    /// na které se klikalo.
    ///
    /// Drží se, dokud ji člověk nezavře: chyba, která zmizí sama, je chyba, kterou nikdo nepřečte.
    /// Tvar je tentýž jako u chyby labelů (`PanelMetadataView.noticeRow`) — ikona, věta, `Zavřít`
    /// s `fixedSize`, protože ustupovat má text, ne akce.
    ///
    /// **Věta je jen ta z chyby, a je to odchylka od zákresu** (sekce 37 kreslí *„Přepnout na Ready
    /// for review se nepovedlo: `HTTP 403`. Pull request je pořád rozpracovaný.“*). Obě půlky té
    /// věty jsou totiž závadné a každá jinak:
    ///
    /// - *„Pull request je pořád rozpracovaný“* je **tvrzení, které data neunesou** u `timedOut`
    ///   a `interrupted` — tam se právě neví, jestli přepnutí prošlo, a obě chyby to říkají samy
    ///   (*„Zkontroluj na GitHubu, jestli přesto neprošlo.“*).
    /// - *„se nepovedlo“* říká `PublishError.unknown` **taky** (*„Odeslání se nepovedlo: …“*),
    ///   takže by v panelu stálo dvakrát za sebou.
    ///
    /// Co se akce jmenuje, nese **tlačítko o dva body výš** — je to tatáž úmluva jako u chyby
    /// labelů, která taky kreslí `userDescription` samotný.
    private func readyFailureRow(_ failure: PublishError) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.crit)
                // Ikona je jen vizuální — bez tohohle ji čtečka přečte jako jméno symbolu před
                // větou, která to samé říká slovy (nález Copilota na #465).
                .accessibilityHidden(true)
            Text(verbatim: failure.userDescription)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Zavřít", action: actions.clearReadyFailure)
                .buttonStyle(.mini)
                .fixedSize()
        }
        .font(.system(size: Self.readyNoteFontSize))
    }

    /// Nápověda pod kurzorem. U zakázaného tlačítka **tytéž věty jako v panelu**; u povoleného to,
    /// co se stane — a schválně jinými slovy než věta pod tlačítkem, aby nápověda nebyla její kopie.
    private var readyHelp: String {
        guard section.ready.isAllowed else {
            return section.ready.obstacles.map(\.sentence).joined(separator: " ")
        }
        return "Odešle se hned, bez potvrzení. Pull request přestane být rozpracovaný."
    }

    private static let readyTitle = "Připravit k review"
    /// `.send { font-size: 12.5px }` z návrhu.
    private static let readyFontSize = 12.5
    /// Věta pod tlačítkem a chyba — `font-size: 11.5px` z návrhu.
    private static let readyNoteFontSize = 11.5

    /// Řada akcí. **Obě tlačítka jsou vidět vždycky** (návrh, sekce 36) — mění se jen to, které
    /// z nich je hlavní: srovnat větev dává smysl i tehdy, když už mergnout jde, a schovávat akci
    /// podle stavu by znamenalo, že se tlačítko pod rukou stěhuje.
    private var actionRow: some View {
        HStack(spacing: Self.actionSpacing) {
            mergeButton
            syncButton
            Spacer(minLength: 0)
        }
    }

    /// `Mergnout…` — **tři tečky proto, že otevírá potvrzení**, ne proto, že to trvá.
    ///
    /// Zakázané tlačítko se kreslí dál, jen se do něj nedá kliknout: „tady se to dělá, jen teď ne“
    /// je u červeného checku i u vypnuté brány pravda, a chybějící tlačítko by vypadalo jako
    /// rozbitá aplikace. Důvod stojí v panelu nad ním; nápověda pod kurzorem ho **opakuje**, aby
    /// se dal přečíst i tam, kde je zrovna kurzor.
    private var mergeButton: some View {
        Button(Self.mergeTitle, action: actions.merge)
            .buttonStyle(isPrimary(.merge) ? .miniPrimary : .mini)
            .disabled(!section.merge.isAllowed)
            // `.disabled` u vlastního `ButtonStyle`u sám nic neztlumí — návrh má `opacity: 0.45`.
            .opacity(section.merge.isAllowed ? 1 : 0.45)
            .help(section.merge.isAllowed ? Self.mergeHelp : obstacleHelp)
    }

    /// `Rebase` — **bez tří teček**, protože nic neotevírá: přehraje commity v kopii repa a do
    /// remote nesáhne. Co přesně se stane, stojí v nápovědě pod kurzorem
    /// (`Policy.branchSyncHelp`).
    ///
    /// **Gitové jméno, ne české sloveso**, a je to výslovné rozhodnutí uživatele: `rebase`
    /// a `force push` se v téhle branži nepřekládají a `Přetlačit` je slovo, které nikdo
    /// nepoužívá. Přebíjí to pravidlo o českých uživatelských textech z `CLAUDE.md` — próza
    /// kolem zůstává česky, mění se **jména akcí**.
    ///
    /// **Jméno základu z popisku zmizelo, a je to změřené.** Nese ho řádek stavu nad tlačítky
    /// (`head → base`) i nápověda pod kurzorem, takže se neztratilo; a `Srovnat s main` mělo
    /// 87 bodů, se kterými tři tlačítka v řadě potřebovala **279 z 278** dostupných (a 267 z 218
    /// na podlaze panelu). `Rebase na master` by bylo **delší** — zhoršilo by tedy změřený
    /// problém, kdežto `Rebase` ho odklízí.
    private var syncButton: some View {
        Button(syncTitle, action: actions.sync)
            .buttonStyle(isPrimary(.sync) ? .miniPrimary : .mini)
            .disabled(!section.sync.isAllowed)
            .opacity(section.sync.isAllowed ? 1 : 0.45)
            .help(syncHelp)
    }

    /// Hlavní je ta akce, která z návrhu plyne — a **jen když se do ní dá kliknout**: zvýrazněné
    /// tlačítko, které je zašedlé, by na sebe táhlo oči kvůli něčemu, co teď stejně nejde.
    private func isPrimary(_ action: Policy.BranchAction) -> Bool {
        guard section.primary == action else { return false }
        return action == .merge ? section.merge.isAllowed : section.sync.isAllowed
    }

    private var syncTitle: String { "Rebase" }

    private var syncHelp: String {
        guard section.sync.isAllowed, let plan = section.syncPlan else {
            return section.sync.obstacles.map(\.sentence).joined(separator: " ")
        }
        return Policy.branchSyncHelp(for: plan, resolvesConflicts: section.resolvesConflicts)
    }

    /// Jak dopadlo srovnání větve — **věta v panelu, ne jen v logu**. Drží se, dokud ji člověk
    /// nezavře: hláška, která zmizí sama, je hláška, kterou nikdo nepřečte.
    ///
    /// **Práce, která leží v cache, má vlastní tlačítka.** Jsou to stavy, ne chyby: u rozdělaného
    /// rebase se dá jedině zahodit, u **přerovnané větve, která neodešla**, se dá přetlačit nebo
    /// zahodit — a `Zavřít` u nich schválně **není**, protože zavřít hlášku o práci v cache by ji
    /// schovalo, aniž by zmizela. To je zrovna ten tichý stav, kterému se tahle akce vyhýbá.
    /// **Dvě tlačítka jdou na vlastní řádek, jedno zůstává u věty** — a je to změřené, ne odhadnuté.
    /// `Force push…` a `Zahodit rebase` si vedle sebe vezmou ~213 z 278 bodů, které panel na obsah
    /// má, takže na text zbyde ~50: věta o devíti slovech se v renderu složila do **devíti řádků**
    /// po jednom slově. Je to tatáž past, jakou u sekce `Větev` změřilo #392 v hlavičce PR a #37
    /// u třetího tlačítka — a tentýž závěr: **vlastní řádek je jediné místo, kde se dvě akce vejdou
    /// při každé šířce panelu** (tahá se od 240 bodů).
    @ViewBuilder private func syncNotice(_ state: BranchSyncState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: Self.noticeIcon(state))
                    .foregroundStyle(Self.noticeTint(state))
                    .accessibilityHidden(true)
                Text(verbatim: state.sentence)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Jediné tlačítko se do řádku vejde — `Zahodit rebase` je nejdelší z nich a nechá
                // textu ~160 bodů. Změřeno renderem: krátká věta (`Srovnáno — přetlačeno…`) se sází
                // na dva řádky, nejdelší (konflikt se jménem souboru) na šest. Šest řádků po třech
                // slovech je pořád věta, kdežto u dvojice tlačítek zbylo ~50 bodů a **slovo na
                // řádek** — to je ten rozdíl, kvůli kterému jde na vlastní řádek jenom dvojice.
                // Vlastní řádek u jediného tlačítka je zamítnutý: u `Zavřít` nad dvouřádkovou větou
                // je to řádek navíc v panelu, který má 300 bodů.
                if Self.noticeActions(state) == .one { singleNoticeButton(state) }
            }
            // **Co session dělá právě teď — druhý řádek, a jedině dokud slévá.** Bez něj je
            // desetiminutová session k nerozeznání od zaseknutého okna; a po doběhnutí by řádek
            // o naposled hlášeném kroku zůstal viset nad hotovým výsledkem.
            // **Obě zapisující session**, ne jen slévání konfliktů (#510): patnáctiminutové ticho
            // nad větou „Agent opravuje“ je k nerozeznání od zaseknutého okna, což je celý důvod,
            // proč ten řádek existuje.
            if state.isResolving || state.isFixing, let syncActivity { activityRow(syncActivity) }
            if Self.noticeActions(state) == .two { pairedNoticeButtons(state) }
        }
        // **Velikost vypsaná, ne `.caption`.** Celá sekce sází explicitními body (12 popis, 11
        // odpověď) a `.caption` je proti tomu systémová hodnota, která se s nimi rozejde při první
        // změně nastavení textu. Dvanáct je tatáž hodnota jako ve výstraze — je to tatáž třída
        // věty o stavu.
        .font(.system(size: Self.noticeFontSize))
    }

    /// Kolik akcí u hlášky stojí. **Rozhoduje o rozvržení**, takže je to vlastní odpověď, ne
    /// `if`y rozeseté po dvou místech.
    private enum NoticeActions {
        case none
        case one
        case two
    }

    private static func noticeActions(_ state: BranchSyncState) -> NoticeActions {
        if state.rebasedBranch != nil { return .two }
        // **Rozdělaný rebase má od #467 dvě akce, ne jednu** (návrh sekce 36): `Otevřít
        // v terminálu` k tomu, co tam už bylo. Vlastní řádek na ně je změřený u #466 — dvě
        // tlačítka vedle věty jí nechají ~50 bodů, tedy slovo na řádek.
        // A od #510 stejně tak nepřijatá práce agenta: v kopii repa může ležet a rozhoduje o ní
        // člověk — tedy tytéž dvě akce.
        if state.hasUnfinishedRebase || state.hasRejectedFix { return .two }
        // **Běžící session má `Zrušit`**, na rozdíl od rebase a zahazování: běží minuty a stojí
        // peníze, takže „rozmyslel jsem si to“ nesmí znamenat čekat na konec. Platí to pro slévání
        // konfliktů i pro agenta (#510) — a u agenta o důvod víc, protože ho nikdo nespouštěl
        // kliknutím.
        if state.isResolving || state.isFixing { return .one }
        return state.isBusy ? .none : .one
    }

    /// Jedno tlačítko u věty: `Zrušit` u běžícího slévání, jinak `Zavřít` u hlášky.
    @ViewBuilder private func singleNoticeButton(_ state: BranchSyncState) -> some View {
        if state.isResolving || state.isFixing {
            Button(Self.cancelTitle, action: actions.cancelSync)
                .buttonStyle(.mini)
                .fixedSize()
                .help(Self.cancelHelp)
        } else {
            Button("Zavřít", action: actions.clearSync)
                .buttonStyle(.mini)
                .fixedSize()
        }
    }

    /// Co session zrovna dělá. **Odsazené pod věty**, aby se nečetlo jako druhá věta o stavu.
    private func activityRow(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: Self.noticeFontSize - 0.5))
            .foregroundStyle(Palette.ink3)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(text)
            .padding(.leading, 20)
    }

    /// Dvojice na vlastním řádku — **u přerovnané větve i u rozdělaného rebase** (#467).
    ///
    /// `Force push…` má tři tečky, protože **otevírá potvrzení**; je to tatáž konvence jako
    /// u `Mergnout…` a ze stejného důvodu: co je za tím kliknutím nevratné, se potvrzuje.
    ///
    /// U rozdělaného rebase je hlavní akce `Otevřít v terminálu` (návrh sekce 36): je to ten další
    /// krok, kterým se s tím dá něco udělat — zahodit znamená vzdát to.
    @ViewBuilder private func pairedNoticeButtons(_ state: BranchSyncState) -> some View {
        HStack(spacing: Self.actionSpacing) {
            if state.offersTerminal {
                Button(Self.terminalTitle, action: actions.openTerminal)
                    .buttonStyle(.miniPrimary)
                    .fixedSize()
                    .help(Self.terminalHelp)
            } else {
                Button(Self.pushTitle, action: actions.push)
                    .buttonStyle(.miniPrimary)
                    .fixedSize()
            }
            Button(Self.discardTitle(state), action: actions.discardSync)
                .buttonStyle(.mini)
                .fixedSize()
            Spacer(minLength: 0)
        }
    }

    private static let pushTitle = "Force push…"

    /// Co se tím tlačítkem zahazuje. **Slovo podle stavu, ne jedno na všechno** (#510): po
    /// agentovi v cache žádný rozdělaný rebase neleží, takže `Zahodit rebase` by pojmenovávalo
    /// něco, co tam není — a je to tatáž třída chyby jako věta o rebase nad jeho commitem.
    ///
    /// **Platí to i pro úspěch**, ne jen pro nepřijatý výsledek: `rebased` s původem `.agent` je
    /// commit agenta, ne přehrané commity. Vyšlo to z renderu sondy (scéna `17-agent-hotovo`), kde
    /// pod větou „Agent upravil 2 soubory“ stálo `Zahodit rebase`.
    private static func discardTitle(_ state: BranchSyncState) -> String {
        state.isAgentWork ? "Zahodit změny" : "Zahodit rebase"
    }
    private static let terminalTitle = "Otevřít v terminálu"
    private static let terminalHelp =
        "Otevře zásuvku se shellem v té kopii repa, kde rebase uvázl. Tam máš plná práva."
    private static let cancelTitle = "Zrušit"
    private static let cancelHelp =
        "Zabije session. Co už slila, zůstane v kopii repa — zahodit se to dá tlačítkem."

    private static let noticeFontSize = 12.0

    /// **Ikona ze stavu, ne z barvy** — a `checkmark` jedině u toho, co doopravdy doběhlo.
    private static func noticeIcon(_ state: BranchSyncState) -> String {
        switch state {
        case .rebasing, .resolving, .fixing, .pushing, .discarding: "arrow.triangle.2.circlepath"
        // **Ne `checkmark`.** První krok doběhl, ale akce hotová není — do remote se nesáhlo,
        // a zaškrtnutí by tvrdilo, že je uklizeno.
        case .rebased: "arrow.up.circle"
        // **Agent, který nic nezměnil, není porucha** (#510): doběhl a v cache po něm nic neleží.
        // Vykřičník nad legitimním výsledkem by svítil zbytečně.
        case .pushed, .alreadyInSync, .fixedNothing: "checkmark.circle"
        case .conflicted, .unfinished, .unresolved, .fixRejected, .failed: "exclamationmark.triangle"
        }
    }

    /// **Barva ze škály se bere z palety, nikdy ze systému** (#432).
    private static func noticeTint(_ state: BranchSyncState) -> Color {
        switch state {
        case .rebasing, .resolving, .fixing, .pushing, .discarding: Palette.ink3
        // Agent, který nic nezměnil (#510), je **doběhlá práce, ne mezistav**: nic v cache neleží
        // a nic se nečeká — tedy tentýž tón jako `alreadyInSync`, o kterém platí totéž.
        case .pushed, .alreadyInSync, .fixedNothing: Palette.ok
        // Mezistav není ani hotovo, ani porucha — **čeká na rozhodnutí**, a to je tentýž tón jako
        // u rozdělaného rebase. Nepřijatá práce agenta je tatáž třída: leží v cache a rozhoduje
        // o ní člověk.
        case .rebased, .unfinished, .unresolved, .fixRejected: Palette.stale
        case .conflicted, .failed: Palette.crit
        }
    }

    private static let mergeTitle = "Mergnout…"
    private static let mergeHelp = "Otevře potvrzení. Odešle se až z něj."

    private var obstacles: [Policy.MergeObstacle] { section.merge.obstacles }

    /// Věty do výstrahy — **z obou akcí**. Co z překážek srovnání si vlastní větu žádá, rozhoduje
    /// `Policy.syncWarnings`; ostatní jsou v panelu napsané jinde.
    private var warnings: [String] {
        obstacles.map(\.sentence)
            + Policy.syncWarnings(section.sync).map(\.sentence)
            // **Dnes prázdné, a je to zapsaná odpověď** (#482): oba důvody, proč `Připravit
            // k review` nejde, jsou v panelu buď napsané už jednou (vypnutá brána nese tutéž větu
            // jako `MergeObstacle.notAllowed`), nebo se odklidí samy (běžící odeslání). Sečítá se
            // to přesto — jinak by nová překážka, která si větu **žádá**, skončila jen v nápovědě
            // pod kurzorem a nikdo by si toho nevšiml.
            + Policy.readyWarnings(section.ready).map(\.sentence)
    }

    /// Nápověda pod kurzorem u zakázaného tlačítka — **tytéž věty jako v panelu**, na jednom
    /// řádku. Druhý text by znamenal dvě různá vysvětlení jednoho zašednutí.
    private var obstacleHelp: String {
        obstacles.map(\.sentence).joined(separator: " ")
    }
}
