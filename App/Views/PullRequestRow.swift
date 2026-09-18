import SwiftUI

/// Jeden řádek seznamu PR (#172).
///
/// **Titulek je nahoře, souřadnice pod ním.** Do #172 to bylo obráceně — repo první, titulek
/// druhý — a seznam se tím čte místo skenuje: „odkud to je“ je otázka, na kterou dojde řada
/// až po „co to je“.
///
/// Stav review nese **hrana řádku**, ne jen odznak. Barva na kraji se přečte periferně, takže
/// se fronta dá přejet očima; odznak vedle ní říká totéž slovy, protože samotná barva nestačí.
struct PullRequestRow: View {
    let pullRequest: PullRequestSummary
    let reviewState: ReviewState
    /// Leží na tomhle PR rozdělané review? Ukazuje se ikonou, ne slovem: „draft“ je vedle
    /// v řádku obsazený **rozpracovaným pull requestem**, což je něco jiného.
    var hasDraft = false
    /// Odvozená čísla k výsledku — kolik nálezů blokuje. Prázdné u PR, na kterém nic neběželo.
    var row: QueueRow = .empty
    /// Mapa PR do mini pásu (#502) — **místo spektra reviewerů**. `nil` = pás se **nekreslí**:
    /// buď na PR nic neběželo, nebo aplikace jeho diff ještě neviděla. Rozhoduje o tom
    /// `AppStore.queueMap(for:)`, a tam je i vysvětlení, proč se nekreslí nic místo prázdna.
    var map: PullRequestMap?
    /// Čí PR to je (#331). U vlastního má řádek vpravo `Prompt →`, protože sestavit z nálezů
    /// a konverzace zadání pro agenta je jediné, co s ním okno umí udělat — verdikt na vlastní PR
    /// GitHub odmítá.
    var ownership: PullRequestOwnership = .theirs
    /// Co udělá `Prompt →` (#333). `nil` = **tlačítko se nekreslí** — řádek bez storu (náhled,
    /// test) akci nemá odkud vzít a nakreslit ji naprázdno je zrovna ta lež, kvůli které se
    /// v #331 kreslila zakázaná.
    var openPrompt: (() -> Void)?
    /// Kolik položek na vlastním PR zbývá předat agentovi (#334) — `Policy.handoff`, tedy tatáž
    /// funkce, ze které čte odznak v railu i panel. Nula znamená „nic nezbývá“ a pilulka se
    /// nekreslí; na cizím PR se nekreslí nikdy.
    var pending = 0
    /// Co na vlastním PR od minule udělal někdo jiný (#335) — `2 nové komentáře od minule`
    /// v meta řádku. Prázdná znamená „nic nepřibylo“ (nebo se ještě nikdo nedíval) a řádek pak
    /// vypadá jako dřív; bere se z **téhož** `HandoffReport` jako `pending`.
    var activity: ForeignActivity = .none
    /// Co na vlastním PR dělá agent (#511) — `agent běží · 4 min`, nebo `push čeká na tebe`.
    /// `nil` = neběží nic a nic nečeká; na cizím PR **nikdy** (rozhoduje `Policy.agentRowPill`).
    ///
    /// **Skládá to store, ne řádek**, a je to kvůli hodinám: uplynulý čas se počítá z `time.now`,
    /// tedy z toho zdroje času, který se v testech dá nastavit. `Date()` uvnitř `body` by z toho
    /// udělal měření, které se nedá zopakovat.
    var agent: AgentRowPill?
    /// Co řádek říká o návrhu review (#520) — `návrh review · 3 + 2 sporné`, u čistého
    /// `návrh: schválit`. `nil` = **nekreslí se nic**: vypnutá brána, žádný návrh, nebo o něm
    /// řádek neví (náhled, test).
    ///
    /// **Skládá to store, ne řádek**, jako u pilulky agenta: rozhoduje o ní razítko na záznamu
    /// a brána z konfigurace, a obojí je za `Policy.autoDraftPill`. Dvě skládání by znamenala,
    /// že fronta říká o témž návrhu něco jiného než panel.
    var autoDraft: AutoDraftPill?
    /// Odložit (#512) — **jedna hodnota, ne dvojice nabídka + akce**. `nil` znamená „řádek
    /// o odložení neví“ (náhledy, testy), prázdná nabídka uvnitř znamená „nesmí se“ (vlastní PR,
    /// `Policy.canSnooze`). V obou případech se nekreslí **nic**, ne zašedlá položka — ta by
    /// sváděla na ni kliknout a hledat, co je rozbité (tatáž úvaha jako u `Prompt →`, #333).
    ///
    /// **Kdo řádek kreslí, tohle předává**, a je to podmínka, ne nabídka: do opravy #512 to
    /// předával jen seznam, takže na desce a v sekci `Rozdělaná` odložit nešlo — a na desce se
    /// přitom o odložených mluví ve větě pod pozdravem. Hlídá to `PullRequestRowSnoozeWiringTests`.
    var snoozeAction: SnoozeAction?
    /// Dráha vlastního PR zmenšená do řádku (#509) — pět teček a slovo k aktivní stanici.
    ///
    /// `nil` = **nekreslí se nic**, ne prázdný pruh teček: řádek bez storu (náhled, test) dráhu
    /// nemá odkud vzít a pět šedých koleček by tvrdilo, že se na tom PR nic nestalo. Tatáž úvaha
    /// jako u mapy PR (#502) a u `Prompt →` (#333).
    ///
    /// **Skládá ji `Policy.ownLoopRow` nad `Policy.ownLoop`** (#508), ne řádek: dvě skládání
    /// jedné smyčky by uměla říct každé něco jiného než hlavička téhož PR.
    ///
    /// **Kdo řádek kreslí, předává i tohle** — hlídá to `OwnLoopRowRenderTests`, a ze stejného
    /// důvodu jako u `snoozeAction`: řádek se kreslí na třech místech (#512).
    var loop: OwnLoopRow?
    /// Kde v sérii tenhle PR stojí (#513). `nil` = v žádné není, nebo o ní řádek neví (náhled, test).
    /// Kreslí se z toho pilulka `1. v sérii` a přerušovaná čára na kraji řádku.
    ///
    /// **Pilulka jde všude, kam se řádek kreslí.** Stát na cizí větvi je vlastnost pull requestu,
    /// takže na desce i v sekci `Rozdělaná` platí stejně jako ve frontě — na rozdíl od popisku níž.
    var series: SeriesPlacement?
    /// Popisek nad skupinou — `série · AJDA-563 · 2 PR · review v pořadí ↓` (#513). `nil` = tenhle
    /// řádek popisek nedostane.
    ///
    /// **Jen ve frontě, a je to rozhodnutí, ne opomenutí.** Popisek je tvrzení o **pořadí
    /// v seznamu** (tyhle řádky patří k sobě a čtou se shora dolů), a to drží jedině fronta: deska
    /// řádky rozřazuje do pruhů podle mého tahu a ořezává je na pět, takže by čára obtáhla skupinu,
    /// která tam celá není. Rozhoduje `Policy.seriesCaptions(in:series:)` nad tím, co se doopravdy
    /// kreslí — nad osamoceným členem popisek nevznikne.
    var seriesCaption: String?

    var body: some View {
        // `spacing: 0` a popisek **uvnitř řádku**, ne jako další prvek seznamu (#361): řádky fronty
        // se identifikují pull requestem, a popisek s vlastní identitou by do seznamu přidal prvek,
        // jehož identita by musela být pořadí. Takhle se identita nemění vůbec.
        VStack(alignment: .leading, spacing: 0) {
            if let seriesCaption { caption(seriesCaption) }
            rowBody
        }
    }

    /// `SÉRIE · AJDA-563 · 2 PR · REVIEW V POŘADÍ ↓` — popisek nad skupinou (návrh, `.rv-stackcap`).
    ///
    /// Mono 10 s prostrkáním a verzálkami jako ostatní nadpisy v okně, ale **v akcentu**: je to
    /// jediná věc v seznamu, která mluví o vztahu mezi řádky, a musí se od jejich vlastního obsahu
    /// odlišit.
    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, design: .monospaced))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Palette.accent)
            .lineLimit(1)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .padding(.leading, 13)
            .accessibilityLabel(text)
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            headline
            meta
        }
        .padding(.vertical, 4)
        .padding(.leading, 9)
        // Proužek přes celou výšku řádku. `overlay`, ne sloupec v `HStacku`: jinak by se
        // musela výška dopočítávat ručně a u dvouřádkového titulku by proužek nedosáhl.
        .overlay(alignment: .leading) {
            Capsule()
                .fill(stripe)
                .frame(width: 3)
        }
        // Přerušovaná čára série (#513, návrh `.rv-stackgroup`) — **vlevo od proužku stavu**, ne
        // místo něj: proužek mluví o výsledku review na tomhle PR, čára o tom, že řádek patří do
        // skupiny. Odsazení se přidává jedině členovi série, takže se ostatní řádky nehnou.
        .padding(.leading, series == nil ? 0 : Self.spineInset)
        .overlay(alignment: .leading) {
            if series != nil {
                SeriesSpine()
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
        }
        // **Zápis `Bool`u na `Bool`, ne poloha z každého snímku** — `onContinuousHover` je ta
        // třída, která si žádá `Policy.hoverChange` (#358); tohle se ozve jedině na přechodu.
        //
        // **A jen na řádku, který nabídku má.** Bez toho guardu by se stav přepisoval i na desce
        // a v sekci `Rozdělaná`, tedy překreslení řádku za odpověď, kterou nikdo nepřečte.
        .onHover { hovering in
            guard showsSnoozeAction else { return }
            isHovered = hovering
        }
        // Pravé tlačítko — **druhá cesta k téže nabídce**, ne druhá nabídka. Bez nabídky se
        // `.contextMenu` nekreslí vůbec: prázdná nabídka po pravém kliknutí vypadá jako porucha.
        .contextMenu {
            if showsSnoozeAction, let snoozeAction {
                SnoozeMenuItems(offers: snoozeAction.offers, snooze: snoozeAction.snooze)
            }
        }
    }

    /// Je řádek pod kurzorem? Rozhoduje o `Odložit` (#512) — o ničem jiném, takže se v ostatních
    /// místech, která řádek kreslí (deska, `Rozdělaná`), nezmění nic.
    @State private var isHovered = false

    /// Má řádek nabídku `Odložit` (#512)? **Pojmenované, ne `if` uvnitř `body`** — je to
    /// rozhodnutí o tom, co řádek nabízí, a v `body` se testovat nedá; tatáž úvaha jako
    /// u `showsPromptAction`.
    ///
    /// **Ptá se na akci i na obsah nabídky.** Tlačítko s prázdnou nabídkou je tlačítko, po kterém
    /// se nic nestane — a to je zrovna ta lež, kvůli které se v #333 přestala kreslit zakázaná
    /// `Prompt →`. Vlastní řádek dostane prázdné `offers` (`Policy.canSnooze`), takže na něm
    /// nevznikne ani tlačítko, ani položka v kontextové nabídce.
    ///
    /// **Ptají se na ni obě kreslicí místa, ne jen jedno.** Kdyby si tlačítko a kontextová nabídka
    /// psaly `if let snoozeAction, snoozeAction.isAvailable` každé po svém, byla by tahle property
    /// vedlejší produkt — a test nad ní by pak tvrdil něco, co s kresbou nesouvisí.
    var showsSnoozeAction: Bool { snoozeAction?.isAvailable == true }

    private var headline: some View {
        HStack(spacing: 6) {
            Image(systemName: PullRequestStateAppearance.symbol)
                .font(.caption)
                .foregroundStyle(PullRequestStateAppearance.color(of: pullRequest.state))
                .help(pullRequest.state.czechLabel)
                .accessibilityLabel(pullRequest.state.czechLabel)
            Text(pullRequest.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            // **Mapa PR místo spektra reviewerů** (#502, mění #172): barva je závažnost, tedy
            // totéž kódování jako u pásu pod hlavičkou a v okraji diffu. Bez mapy se nekreslí
            // **nic** — prázdný obdélník by se tvářil jako údaj, tatáž úvaha, kvůli které
            // se do #502 nekreslilo spektrum u řádku bez běhu.
            if let map, !map.isEmpty {
                QueueMapStrip(map: map)
            }
            // Série (#513) — **vedle ostatních, ne místo nich**: `1. v sérii` odpovídá na „v jakém
            // pořadí to číst“, kdežto dráha, pilulka agenta i odznak na „jak to dopadlo“ a „kde
            // v kole to stojí“. Jsou to různé otázky, takže se o slot neperou — a je to jediná věc
            // v řádku, která mluví o **jiném** pull requestu.
            if let series {
                seriesPill(series)
            }
            // **Na vlastním PR dráha smyčky místo odznaku stavu** (#509, návrh sekce 52). Tečky
            // říkají, kde v kole to stojí, pilulka vedle nich to řekne slovem — a je to celá
            // odpověď na „co s tímhle PR ještě je“, ne jen na „jak dopadlo moje review“.
            //
            // **Pohlcuje to pilulku `N k předání`** (#334), a je to postup, ne zrušení: `Zadání`
            // je jedna z těch pěti stanic, takže se nepředané zadání dozvím pořád — jenom teď
            // vedle toho vidím i to, že mezitím spadlo CI. Dvě pilulky vedle sebe by nešly, obě
            // mluví o témže PR a jedna z nich by musela vyhrát bez důvodu.
            //
            // **Tečky kreslí dráha vždycky, pilulku si bere agent, dokud běží** (#511 nad #509,
            // slito v PR #581). Slot je jediný a pořadí v něm je *agent → dráha → `N k předání` →
            // odznak*; že dráha ustoupí, rozhoduje `showsLoopWord`, ne tenhle `if`. Dvě odpovědi
            // z jiných dat to není: `agent běží · 4 min` i stanice `Push` čtou **tentýž**
            // `BranchSyncState`, pilulka agenta je jen jeho podrobnější čtení — nese uplynulý čas,
            // který dráha nemá kde vzít (`OwnLoop.Stop.detail` je jedno slovo, tady `probíhá`).
            // Tečky u ní zůstávají schválně: odpovídají na „kde v kole to stojí“, a ta otázka se
            // během agentova běhu neztrácí.
            //
            // **Bez dráhy zůstává všechno, jak bylo.** Řádek bez storu (náhled, test) ani cizí
            // řádek ji nedostanou, a odznak review je tam pořád ta správná odpověď.
            if let loop = showsLoop {
                OwnLoopDots(row: loop)
            }
            if showsLoopWord, let loop = showsLoop {
                loopPill(loop)
            } else if let agent {
                agentPill(agent)
            } else if let pending = pendingHandoff {
                handoffPill(pending)
            } else {
                ReviewStateBadge(state: reviewState, blocking: row.blocking)
            }
            if showsPromptAction {
                promptButton
            }
            // Odložit pod kurzorem (#512). **Za odznakem, ne před ním**: řádek se čte zleva
            // doprava (co to je → jak to dopadlo) a akce patří na konec.
            if isHovered, showsSnoozeAction, let snoozeAction {
                SnoozeRowButton(action: snoozeAction)
            }
        }
    }

    /// Má řádek vpravo `Prompt →`? **Pojmenované, ne `if` uvnitř `body`** — je to jediné, čím se
    /// vlastní řádek od cizího liší, a uvnitř `body` se to tvrdit nedá; tatáž úvaha jako
    /// u `FindingBadgeAppearance`. Ven z aplikace se tím nic neotevírá, je to jeden modul.
    ///
    /// **Ptá se i na akci** (#333): vlastní řádek bez `openPrompt` tlačítko nedostane. Do #333 se
    /// kreslilo zakázané, protože akci měl dodat až tenhle kus — a zakázané tlačítko, po kterém se
    /// nic nestane, svádí na něj kliknout a hledat, co je rozbité.
    var showsPromptAction: Bool { ownership == .mine && openPrompt != nil }

    /// Dráha, jestli se má kreslit (#509). `nil` = cizí PR, nebo se nedodala.
    ///
    /// **Pojmenované, ne `if` uvnitř `body`**, ze stejného důvodu jako `showsPromptAction`: je to
    /// rozhodnutí o tom, co řádek tvrdí, a v `body` se testovat nedá.
    ///
    /// **Ptá se na vlastnictví, i když ho `Policy.ownLoop` hlídá taky.** Není to druhá kontrola,
    /// je to **předfiltr u kresby**: řádek dostává dráhu odjinud (deska, seznam, sekce
    /// `Rozdělaná`) a nikde není zapsáno, že mu ji někdo nepodstrčí i k cizímu PR. Tečky na cizím
    /// řádku by přitom byly tvrzení o práci, kterou nikdo z nás dělat nebude — smyčka je „co
    /// udělám se **svojí** větví“, tak jako sekce `Větev` (#465).
    ///
    /// **Ptá se i na to, jestli je co nakreslit.** Dráha bez stanic by dala prázdný pruh
    /// v šířce pěti teček — tedy díru, která vypadá jako vada kresby, ne jako odpověď. Je to
    /// tatáž kontrola, jakou má vedle mapa PR (`if let map, !map.isEmpty`, #502).
    var showsLoop: OwnLoopRow? {
        guard ownership == .mine, let loop, !loop.dots.isEmpty else { return nil }
        return loop
    }

    /// Říká řádek slovo dráhy (#509), nebo ho v jediném slotu přebil agent (#511)?
    ///
    /// **Pojmenované, ne `if` uvnitř `body`**, ze stejného důvodu jako `showsLoop`: pořadí
    /// v tom slotu je rozhodnutí, ne kresba, a v `body` se testovat nedá.
    ///
    /// **Tečky se tím neřídí.** `OwnLoopDots` odpovídá na *kde v kole to stojí* a ta otázka
    /// během agentova běhu nemizí — tečky stojí **před** slotem, takže se o něj neperou.
    var showsLoopWord: Bool { showsLoop != nil && agent == nil }

    /// Barva proužku na hraně řádku.
    ///
    /// **Na vlastním PR ji od #509 bere aktivní stanice**, ne stav mého review. Je to tatáž
    /// změna jako u pilulky vedle: na vlastním PR není otázka „jak dopadlo moje review“ (to je
    /// první z pěti stanic), ale „co s tím ještě je“ — a hrana se čte periferně, takže má nést
    /// zrovna tu odpověď. PR s čistým review a spadlým CI má proto červenou hranu, ne zelenou.
    ///
    /// **Na cizím řádku se nemění nic.** Tam je stav mého review celá odpověď.
    var stripe: Color {
        guard let loop = showsLoop else {
            return ReviewStateAppearance.color(of: reviewState, blocking: row.blocking)
        }
        return LanePhaseChip.tint(of: loop.tone)
    }

    /// Kolik zbývá předat, jestli se to má kreslit (#334). `nil` = cizí PR, nebo nezbývá nic.
    ///
    /// Pojmenované, ne `if` uvnitř `body`, ze stejného důvodu jako `showsPromptAction`.
    var pendingHandoff: Int? {
        guard ownership == .mine, pending > 0 else { return nil }
        return pending
    }

    /// Je `Prompt →` na tomhle řádku plné akcentové tlačítko (#509)?
    ///
    /// **Pojmenované, ne `if` uvnitř `body`**, ze stejného důvodu jako `showsPromptAction` —
    /// a hlavně proto, že je to tvrzení o **jediném akcentovém místě** v řádku, tedy o věci,
    /// která se v bloku `Moje PR` pozná jedině tím, že se řádky porovnají mezi sebou.
    ///
    /// **Stojí na `pendingHandoff`, ne na dráze.** Zvýrazňuje se akce, ne stav: PR se spadlým CI
    /// je naléhavý, ale prompt z něj složit nejde, dokud není co předat. Tuhle odpověď má
    /// `Policy.handoff` a nemá ji nikdo jiný.
    var promptIsPrimary: Bool { pendingHandoff != nil }

    /// `2 nové komentáře od minule` (#335). `nil` = cizí PR, nebo od minule nic — pak v meta řádku
    /// zůstane autor a čas.
    ///
    /// Pojmenované, ne `if` uvnitř `body`, ze stejného důvodu jako `showsPromptAction`: je to
    /// rozhodnutí o tom, co řádek tvrdí, a v `body` se nedá testovat. **Jen u vlastního PR** —
    /// u cizího je novinkou stav review, který má řádek vpravo, a cizí diskuzi aplikace na pozadí
    /// nehlídá (`Policy.activitySweep`), takže by tam text byl vždycky prázdný.
    ///
    /// Počet a slovo skládá `Policy.activityHeadline`, tedy totéž místo jako titulek notifikace;
    /// `od minule` je tady, protože v banneru by nemělo smysl (ten mluví o tom, o čem se ještě
    /// nehlásilo, ne o mojí poslední návštěvě).
    var activityLine: String? {
        guard ownership == .mine, let headline = Policy.activityHeadline(activity) else { return nil }
        return "\(headline) od minule"
    }

    /// `6 k předání` — plná pilulka z návrhu (`.pill.find`).
    ///
    /// **Barva nálezu**, ne akcent ani mint: většinu toho počtu tvoří nálezy a `find` v tomhle okně
    /// znamená „něco se našlo“. Akcent vedle by se pral s `Prompt →` o roli hlavní akce a mint
    /// znamená stav, se kterým se nic nedělá — tady je to naopak práce, která leží.
    private func handoffPill(_ pending: Int) -> some View {
        Text(verbatim: "\(pending) k předání")
            .designPill(tint: Palette.find, background: Palette.find.opacity(0.15))
            .help("Nálezy, vlákna a komentáře, které jsi ještě nepředal agentovi — sestavit zadání jde v panelu Zadání")
            .accessibilityLabel("\(pending) k předání agentovi")
    }

    /// Slovo k aktivní stanici dráhy (#509) — `Push o 4 vzadu`, `CI 1 neprošel`, `hotovo`.
    ///
    /// **Barvu vydává `LanePhaseChip`, ne tenhle řádek**: je to týž stav a tentýž význam jako
    /// v kapsli dráhy nad otevřeným PR, takže by druhé mapování znamenalo, že `spadlo` v seznamu
    /// časem zčervená jinak než `spadlo` v hlavičce.
    ///
    /// **Nemá `layoutPriority` ani `fixedSize`, a je to změřené** — pilulka se v nejužším okně
    /// vejde vedle teček i `Prompt →` a řádek zůstává na jedné řádce (`OwnLoopRowRenderTests`).
    /// Kdyby se přišpendlila, ustupoval by místo ní titulek, tedy to jediné, podle čeho se PR
    /// v seznamu pozná.
    private func loopPill(_ loop: OwnLoopRow) -> some View {
        Text(verbatim: loop.word)
            .lineLimit(1)
            .designPill(
                tint: LanePhaseChip.tint(of: loop.tone),
                background: LanePhaseChip.background(of: loop.tone)
            )
            .help("Kde tenhle pull request stojí ve smyčce — celou dráhu ukazuje jeho hlavička")
            .accessibilityLabel("Na tahu: \(loop.word)")
    }

    /// `1. v sérii` / `2. · stojí na #726` (#513) — pilulka z návrhu (`.pill.run`).
    ///
    /// **Akcent, jako u běžícího review**: je to jediná věc v řádku, která mluví o **vztahu k jinému
    /// řádku**, a musí se odlišit od stavových barev, které mluví o nálezech. Text i nápovědu
    /// skládá `Policy`, ne kresba.
    private func seriesPill(_ placement: SeriesPlacement) -> some View {
        let text = Policy.seriesPill(placement)
        return Text(verbatim: text)
            .designPill(tint: Palette.accent, background: Palette.accent.opacity(0.15))
            .help(Policy.seriesHint(placement))
            .accessibilityLabel(text)
    }

    /// Odsazení řádku, které si bere přerušovaná čára série (návrh: `margin-left: 3px`
    /// + `border-left: 2px`, mezi čarou a proužkem stavu zbývají 2 body).
    private static let spineInset: Double = 7

    /// `návrh review · 3 + 2 sporné` (#520) — pilulka z návrhu (`.pill.mint`).
    ///
    /// **Mint, jako pero, které nahradila** (#309): je to **totéž sdělení** — něco tu leží
    /// neodeslané —, a jedna věc nesmí mít v okně dvě barvy. Akcent by se v tomhle řádku pral
    /// s `běží` z `ReviewStateBadge`, tedy s „něco se tu právě děje“.
    private func autoDraftPill(_ pill: AutoDraftPill) -> some View {
        Text(verbatim: pill.text)
            .lineLimit(1)
            .designPill(tint: Palette.mint, background: Palette.mint.opacity(0.15))
            .help(pill.help)
            .accessibilityLabel(pill.text)
    }

    /// `agent běží · 4 min` / `push čeká na tebe` (#511).
    ///
    /// **Akcent, ne barva nálezu**: na rozdíl od `N k předání` to není práce, která leží, ale
    /// **něco, co se právě děje nebo právě čeká** — tedy tatáž role, jakou má akcent u odznaku
    /// `běží`. `Prompt →` se s ním o pozornost nepere: to je tlačítko a stojí za ním.
    private func agentPill(_ pill: AgentRowPill) -> some View {
        Text(verbatim: pill.text)
            .designPill(tint: Palette.accent2, background: Palette.accent2.opacity(0.15))
            .help(Self.agentHelp(pill))
            .accessibilityLabel(pill.text)
    }

    /// Nápověda říká **co dál**, ne co je vidět — text pilulky se v ní neopakuje.
    private static func agentHelp(_ pill: AgentRowPill) -> String {
        switch pill {
        case .running:
            "Agent opravuje tenhle PR podle cizího review. Co dělá, je vidět v sekci Větev."
        case .awaitingPush:
            "Agent nechal commit v kopii repa. Prohlédni si ho a přetlač z panelu — samo nic neodejde."
        }
    }

    /// `Prompt →` u vlastního PR (#331, akce od #333).
    ///
    /// **Plné akcentové (`.mini.pri`) jen tam, kde je co předat** (#509). Do té změny bylo plné
    /// vždycky, takže si v bloku `Moje PR` bralo akcent i na řádcích, kde by prompt složil
    /// prázdné zadání — a akcent, který svítí na všem, přestane ukazovat na cokoli. Tichá obrysová
    /// podoba (`.mini`) zůstává, protože panel `Zadání` se otevřít **dá** i bez položek: je v něm
    /// vidět, co se předalo minule.
    ///
    /// **Otevře PR a v něm panel se zadáním, text neskládá.** Sheet by z řádku šel otevřít taky, ale
    /// dal by horší zadání: konverzace se tahá při zobrazení PR, takže z neotevřeného řádku by v textu
    /// nebyla vlákna ani komentáře. Zdůvodnění je u `AppStore.openAgentPrompt(in:)`, a proto tu
    /// **není `disabled`** — navigace udělá vždycky něco.
    ///
    /// **Vedle něj stojí od #509 dráha smyčky**, ne odznak review ani pilulka `6 k předání`.
    /// Do #334 to byl odznak (jediná věta, kterou šlo napsat, dokud předání nemělo razítko), do
    /// #509 pilulka `N k předání` (stav **jediné** z pěti stanic) — a od #509 celá dráha, protože
    /// nepředané zadání je jen jeden z důvodů, proč PR ještě není hotový.
    private var promptButton: some View {
        Button("Prompt →") { openPrompt?() }
            .buttonStyle(promptIsPrimary ? .miniPrimary : .mini)
            // Nápověda říká, co se stane — tedy „otevře“, ne „složí“: text se sází teprve v panelu,
            // a nápověda, která slíbí hotové zadání, je tatáž lež jako němé tlačítko.
            .help("Otevřít PR a v něm panel se zadáním pro agenta")
            .accessibilityLabel("Sestavit prompt pro agenta")
    }

    private var meta: some View {
        HStack(spacing: 4) {
            // `verbatim`, jinak `Text` interpoluje číslo přes locale a z PR #21663 udělá
            // „#21 663“ — číslo PR není množství.
            Text(verbatim: "\(pullRequest.repo) #\(pullRequest.number)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            // Draft je **slovo**, ne jen odstín ikony. Tvar ikony je u otevřeného
            // a rozpracovaného PR tentýž, takže by rozdíl nesla pouze barva — a ta sama
            // nestačí. V prvním řádku pro něj místo není, tady zbývá.
            if pullRequest.state == .draft {
                Text(verbatim: "·")
                Text("draft")
            }
            Text(verbatim: "·")
            // **Novinky nese text, ne tečka** (návrh, poznámka 66b), a **místo autora a času**, jak
            // to kreslí sekce 21. Není to úspora místa, je to pořadí důležitosti: „2 nové komentáře
            // od minule“ je důvod na ten řádek kliknout, kdežto autorem vlastního PR jsem já (nebo
            // můj agent) a „před 3 hodinami“ o čekající práci neříká nic. Obojí zůstává v hlavičce
            // detailu, takže se nic neschovává — a na cizím řádku se nemění vůbec nic.
            if let activityLine {
                Text(verbatim: activityLine)
                    // `accent-2` z návrhu — jediná barva v tomhle řádku, protože je to jediná věc,
                    // která se v něm má přečíst dřív než ostatní.
                    .foregroundStyle(Palette.accent2)
                    .lineLimit(1)
            } else {
                Text(verbatim: pullRequest.author)
                Text(verbatim: "·")
                Text(pullRequest.updatedAt, format: .relative(presentation: .named))
            }
            Spacer(minLength: 8)
            // **Pilulka místo pera** (#520) — ale jedině ta, která za rozdělané review **mluví**
            // (`AutoDraftPill.speaksForTheDraft`): `návrh review · 3 + 2 sporné` říká totéž co pero
            // a víc, takže by dvě značky o jedné věci vedle sebe četly jako dvě různé. `návrh:
            // schválit` je proti tomu tvrzení o **nálezech** a o mojí rozepsané próze neví nic —
            // nechat ho pero přebít by znamenalo, že neodeslaná ruční práce z fronty zmizí.
            if let autoDraft {
                autoDraftPill(autoDraft)
            }
            if hasDraft, autoDraft?.speaksForTheDraft != true {
                // **Mint, ne akcent** (#309), a to ze dvou důvodů naráz. Je to **totéž sdělení**
                // jako `2 review` v souhrnu fronty, a jedna věc nesmí mít v okně dvě barvy.
                // A v tomhle řádku akcent už něco znamená: `ReviewStateBadge` jím kreslí `běží`,
                // takže akcentové pero vedle něj tvrdilo „něco se tu děje“ místo „něco tu leží“.
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Palette.mint)
                    .help("Leží tu rozdělané review, které jsi ještě neodeslal")
                    .accessibilityLabel("Rozdělané review")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

}

#Preview {
    List {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85),
                title: "chore: modernize dependencies (Symfony 8-ready, PHPUnit 11)",
                author: "odinuv",
                url: URL(string: "https://github.com/keboola/vault/pull/85")!,
                updatedAt: Date().addingTimeInterval(-3600),
                state: .open
            ),
            reviewState: .completed(findings: 3),
            row: QueueRow(blocking: 1),
            map: PullRequestMap(
                segments: [4, 64, 12, 240, 8, 2790, 30].enumerated().map { index, lines in
                    PullRequestMapSegment(
                        path: "src/File\(index).php",
                        name: "File\(index).php",
                        changedLines: lines,
                        additions: lines,
                        deletions: 0,
                        marker: index == 3 ? .blocking : (index == 1 ? .findings : nil),
                        isNew: index == 5,
                        readState: index < 2 ? .read(at: Date(timeIntervalSince1970: 1_000_000)) : .unread,
                        findings: index == 3 ? 2 : (index == 1 ? 1 : 0),
                        threads: []
                    )
                },
                summary: "7 souborů · 2 prošlé · 3 nálezy"
            )
        )
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14451),
                title: "Refreshable tokens (2/7): refresher domain, OAuth refresher, storage",
                author: "babakks",
                url: URL(string: "https://github.com/cli/cli/pull/14451")!,
                updatedAt: Date().addingTimeInterval(-10800),
                state: .open
            ),
            reviewState: .notStarted,
            series: SeriesPlacement(position: 1, count: 2, standsOn: nil, standsOnBase: nil),
            seriesCaption: Policy.seriesCaption(count: 2, titles: ["AJDA-563 a", "AJDA-563 b"])
        )
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14452),
                title: "Refreshable tokens (3/7): short-lived login, refresh, git credential path",
                author: "babakks",
                url: URL(string: "https://github.com/cli/cli/pull/14452")!,
                updatedAt: Date().addingTimeInterval(-1200),
                state: .open
            ),
            reviewState: .completed(findings: 1),
            series: SeriesPlacement(
                position: 2,
                count: 2,
                standsOn: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14451),
                standsOnBase: "trunk"
            )
        )
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 171),
                title: "feat: události na časové ose konverzace",
                author: "ondrajodas",
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/171")!,
                updatedAt: Date().addingTimeInterval(-300),
                state: .draft
            ),
            reviewState: .notStarted,
            hasDraft: true
        )
    }
    .frame(width: 420)
}

/// Přerušovaná čára u skupiny série (#513, návrh `.rv-stackgroup`).
///
/// **Tvar, ne `Rectangle` s okrajem**: čára jde po celé výšce řádku, který může mít titulek na dvě
/// řádky, takže se výška nedá napsat číslem — `Shape` ji dostane změřenou od `overlay`, stejně jako
/// proužek stavu vedle ní.
struct SeriesSpine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
