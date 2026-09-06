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
    /// Odložit (#512) — **jedna hodnota, ne dvojice nabídka + akce**. `nil` znamená „řádek
    /// o odložení neví“ (náhledy, testy), prázdná nabídka uvnitř znamená „nesmí se“ (vlastní PR,
    /// `Policy.canSnooze`). V obou případech se nekreslí **nic**, ne zašedlá položka — ta by
    /// sváděla na ni kliknout a hledat, co je rozbité (tatáž úvaha jako u `Prompt →`, #333).
    ///
    /// **Kdo řádek kreslí, tohle předává**, a je to podmínka, ne nabídka: do opravy #512 to
    /// předával jen seznam, takže na desce a v sekci `Rozdělaná` odložit nešlo — a na desce se
    /// přitom o odložených mluví ve větě pod pozdravem. Hlídá to `PullRequestRowSnoozeWiringTests`.
    var snoozeAction: SnoozeAction?

    var body: some View {
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
                .fill(ReviewStateAppearance.color(of: reviewState, blocking: row.blocking))
                .frame(width: 3)
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
            // **Na vlastním PR pilulka `N k předání` místo odznaku stavu** (#334, návrh sekce 21).
            // Do #334 tady stál odznak review i na vlastním řádku — a byla to jediná věta, kterou
            // se dalo napsat, dokud předání nemělo razítko. Teď se dá napsat ta, na kterou se
            // u vlastního PR ptám: kolik věcí zbývá předat agentovi. Vedle sebe by nešly: obě
            // čísla mluví o týchž nálezech, takže by se pod sebou pral „3 nálezy“ s „6 k předání“
            // a nikdo by nevěděl, které je které.
            //
            // **Když nezbývá nic, zůstává odznak.** Prázdné místo po pilulce by z vlastního řádku
            // udělalo řádek, ze kterého nejde poznat, jestli review vůbec běželo.
            if let pending = pendingHandoff {
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

    /// Kolik zbývá předat, jestli se to má kreslit (#334). `nil` = cizí PR, nebo nezbývá nic.
    ///
    /// Pojmenované, ne `if` uvnitř `body`, ze stejného důvodu jako `showsPromptAction`.
    var pendingHandoff: Int? {
        guard ownership == .mine, pending > 0 else { return nil }
        return pending
    }

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

    /// `Prompt →` u vlastního PR (#331, akce od #333) — plné akcentové tlačítko z návrhu
    /// (`.mini.pri`).
    ///
    /// **Otevře PR a v něm panel se zadáním, text neskládá.** Sheet by z řádku šel otevřít taky, ale
    /// dal by horší zadání: konverzace se tahá při zobrazení PR, takže z neotevřeného řádku by v textu
    /// nebyla vlákna ani komentáře. Zdůvodnění je u `AppStore.openAgentPrompt(in:)`, a proto tu
    /// **není `disabled`** — navigace udělá vždycky něco.
    ///
    /// **Odznak stavu review vedle něj zůstává**, ačkoli návrh na tom místě kreslí pilulku
    /// `6 k předání`. Ta věta se dá napsat, teprve až předání nese razítko (#334); do té doby by šlo
    /// o počet, který nikdo nepředal. Odznak zatím říká to, co se ví — že reviewer běžel a s jakým
    /// výsledkem —, a to je zrovna materiál, který prompt ponese.
    private var promptButton: some View {
        Button("Prompt →") { openPrompt?() }
            .buttonStyle(.miniPrimary)
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
            if hasDraft {
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
