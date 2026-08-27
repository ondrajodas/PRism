import Foundation

/// Proč se review neodeslalo.
///
/// Typované schválně, stejně jako `GitHubError`: každý případ vede jinam. `lineOutsideDiff`
/// se spraví přesunutím komentáře, `pendingReviewExists` zavřením rozdělaného review
/// v prohlížeči, `ownPullRequest` změnou verdiktu na komentář, `staleDraft` novým čtením
/// diffu. Jedna hláška „nepovedlo se“ by z toho udělala hádanku.
///
/// Klasifikace z výstupu `gh` je **čistá funkce** (`init(failure:)`) a testuje se tabulkou
/// skutečných hlášek z fixtures ze spike #62 — je to křehké rozpoznávání z textu, takže
/// právě proto patří na jedno místo bez I/O.
enum PublishError: Error, Equatable {
    /// Odesílání není pro tohle repo povolené (`PublishScope`). Nic se nevolalo.
    case publishingNotAllowed(RepoID)
    /// Draft je psaný proti jinému commitu, než je teď hlava PR. Nic se nevolalo.
    case staleDraft(draft: String, head: String)
    /// PR není otevřený.
    case pullRequestNotOpen(PullRequestState)
    /// Draft je prázdný nebo bez verdiktu. Nic se nevolalo.
    case nothingToSend
    /// Odpověď do vlákna je prázdná. Nic se nevolalo.
    ///
    /// Vlastní případ, ne `nothingToSend`: ten mluví o draftu a jeho věta radí vybrat verdikt,
    /// což u odpovědi nedává smysl. A není to opatrnost — změřeno v sandboxu, že GitHub prázdné
    /// tělo **tiše spolkne** (`comment: null`, exit 0), takže bez téhle brány by okno hlásilo
    /// odeslanou odpověď, která nikdy nevznikla.
    case blankReply
    /// Komentář pod PR je prázdný. Nic se nevolalo (#216).
    ///
    /// Vlastní případ, ne `blankReply`: věta u odpovědi mluví o vlákně, kdežto tohle je
    /// diskuze pod PR — a hláška, která pojmenuje něco jiného, než na co se člověk dívá,
    /// vypadá jako chyba v jiné části okna. Důvod je jinak tentýž a změřený stejně.
    case blankComment
    /// Vyžádání review bez jediného člověka **i týmu**. Nic se nevolalo (#392).
    ///
    /// Vlastní případ, ne `blankComment`: ta věta radí napsat text, což u vyžádání nedává smysl.
    /// A není to opatrnost — GitHub prázdné pole `reviewers` přijme a neudělá nic, takže by okno
    /// hlásilo vyžádané review, které nevzniklo. Tatáž past jako u prázdného komentáře.
    case noReviewer
    /// Nový label bez jména. Nic se nevolalo (#413).
    ///
    /// Vlastní případ, ne `blankComment`: ta věta radí napsat text do komentáře. Nabídka prázdné
    /// jméno k založení nenabízí, takže se sem dá dostat jedině obejitím obrazovky — a právě proto
    /// tady ta kontrola je.
    case blankLabelName
    /// Label toho jména už v repozitáři je (#413).
    ///
    /// Vlastní případ, ne `unknown`: je to jediná chyba zakládání, po které **není co spravovat** —
    /// label existuje, takže se stačí podívat do nabídky. `Policy.newLabelOffer` na to nedosáhne,
    /// protože nabídka je snímek z chvíle otevření; mezitím ho může založit někdo jiný.
    case labelExists(String)
    /// Merge bez hlavy, na kterou se má mergovat. Nic se nevolalo (#465).
    ///
    /// Vlastní případ, ne `nothingToSend`: ta věta radí vybrat verdikt, což u merge nedává smysl.
    /// A není to opatrnost — `sha` je v payloadu **podmínka**, takže bez ní by GitHub mergnul, co
    /// je zrovna nahoře; tedy přesně to, čemu ta podmínka brání.
    case mergeWithoutHead
    /// GitHub odmítl merge jako neproveditelný — `405` (#465).
    ///
    /// Vlastní případ, ne `unknown`: vede jinam než cokoli ostatního. Znamená, že se stav větve
    /// mezi načtením panelu a kliknutím změnil (konflikt, spadlý povinný check), takže dalším
    /// krokem je podívat se na aktuální stav, ne zkoušet znovu.
    case notMergeable(String)
    /// Větev se pohnula mezi potvrzením a voláním — `409` (#465).
    ///
    /// Vlastní případ, a je to ten nejcennější v celém tomhle výčtu: znamená, že **hlava
    /// v payloadu zabrala** a GitHub nemergnul commit, který nikdo neviděl. Pokrývá obě strany
    /// (`Head branch was modified` i `Base branch was modified`), protože další krok je u obou
    /// tentýž — načíst PR znovu a podívat se, co přibylo.
    case branchMoved(String)
    /// Vlákno, do kterého se odpovídá, na GitHubu není.
    ///
    /// Vlastní případ, ne `network`: hláška `Could not resolve to a node with the global id`
    /// vypadá jako ta, kterou `GitHubError` používá pro neexistující repozitář, ale znamená něco
    /// jiného a vede jinam — konverzaci je potřeba načíst znovu, ne zkoušet síť.
    case threadNotFound(String)
    /// Komentář míří na řádek, který v diffu není. **Neodeslalo se nic** — volání je
    /// atomické (změřeno u #62).
    case lineOutsideDiff(String)
    /// Komentář míří na **soubor**, který v diffu není vůbec.
    ///
    /// Vlastní případ, ne varianta `lineOutsideDiff`: rada „přesuň komentář na řádek uvnitř
    /// diffu“ je tady nepravdivá, protože v diffu není celý soubor. Narazilo se na to při
    /// ověřování #67 proti živému API — GitHub vrací `Path could not be resolved`.
    case pathOutsideDiff(String)
    /// Na PR leží rozdělané (pending) review z prohlížeče.
    case pendingReviewExists
    /// Verdikt na vlastní PR. `APPROVE` i `REQUEST_CHANGES` GitHub zakazuje, `COMMENT` pustí.
    case ownPullRequest(String)
    case notAuthenticated
    case rateLimited(String)
    case network(String)
    case timedOut
    case toolUnavailable(String)
    /// Odpověď se nepodařilo přečíst — review možná odešlo, ale nevíme, jak vypadá.
    case malformedResponse(String)
    /// Odesílání se přerušilo uprostřed. Review mohlo dojít i nedojít.
    ///
    /// Vlastní případ, ne `unknown`: zrušit jde jedině **během** volání, takže je to jediná
    /// chyba, u které se nedá říct ani „nic se nestalo“, ani „nepovedlo se to“. Dnes ji nikdo
    /// nevyvolá (task odeslání se neruší), ale mít pro ni tvar znamená, že se `CancellationError`
    /// nedá spolknout jako „nic se nestalo“ — což byl přesně ten první, nebezpečný pokus.
    case interrupted
    /// Cokoli, co se nepodařilo zařadit. Text `gh` se nese dál, protože je to jediné, co
    /// o tom víme.
    case unknown(String)
}

extension PublishError {
    /// Mohlo review přesto dojít na GitHub?
    ///
    /// **Nejdůležitější vlastnost celé téhle enumerace.** Rozhoduje o tom, jestli okno smí
    /// napsat „nic se nestalo, zkus to znovu“ a jestli zůstane aktivní tlačítko odeslat —
    /// a nabídnout znovuodeslání nad review, které už na PR leží, znamená **druhé review**.
    /// Odeslání je atomické (#62), takže mezistav neexistuje: buď tam je celé, nebo vůbec.
    ///
    /// Rozhoduje se **konzervativně**: co se nedá s jistotou zařadit mezi odmítnutí, počítá se
    /// jako „možná odešlo“. Cena za omyl je nesymetrická — falešné „radši zkontroluj GitHub“
    /// stojí jedno kliknutí, falešné „nic se nestalo“ stojí approve navíc.
    var mightHaveReachedGitHub: Bool {
        switch self {
        // Nic se nevolalo (brány a pre-flight), nebo `gh` vůbec nenaběhl.
        case .publishingNotAllowed, .staleDraft, .nothingToSend, .blankReply, .blankComment,
             .noReviewer, .blankLabelName, .mergeWithoutHead, .pullRequestNotOpen, .toolUnavailable:
            false
        // GitHub požadavek **odmítl** — 422 u rozřazení komentářů, 401 u přihlášení, 403 u
        // limitu, spadlé spojení u sítě. Ve všech případech review nevzniklo.
        //
        // `labelExists` je taky odmítnutí (422 `already_exists`), a navíc jediné, u kterého
        // „možná to prošlo“ nic neznamená: label toho jména v repu **je**, ať ho tam dal kdokoli.
        //
        // `notMergeable` (405) a `branchMoved` (409) jsou odmítnutí taky — a u merge je to ta
        // podstatná vlastnost: GitHub neudělal nic, takže se panel smí zeptat na stav znovu
        // a nabídnout to podruhé.
        case .lineOutsideDiff, .pathOutsideDiff, .pendingReviewExists, .ownPullRequest,
             .notAuthenticated, .rateLimited, .network, .threadNotFound, .labelExists,
             .notMergeable, .branchMoved:
            false
        // `timedOut`: `gh` jsme po třiceti vteřinách zabili sami, POST mohl doběhnout.
        // `malformedResponse`: exit kód byl **nula**, takže POST prošel a jen odpovědi
        // nerozumíme — tady review skoro jistě existuje.
        // `interrupted`: zrušeno uprostřed volání.
        // `unknown`: nezařazená hláška, o které z definice nevíme nic.
        case .timedOut, .malformedResponse, .interrupted, .unknown:
            true
        }
    }
}

extension PublishError {
    /// Klasifikace selhání `gh api`. Tabulka sedí na skutečné hlášky z `Tests/Fixtures/gh/
    /// review-error-*.json`, které vznikly voláním živého API u #62.
    init(failure result: ProcessResult) {
        let text = result.failureText

        // `gh` má vlastní exit kód 4 pro chybějící přihlášení — jediné, co se pozná jinak
        // než z textu.
        if result.exitCode == 4 {
            self = .notAuthenticated
            return
        }

        switch true {
        // **Před** obecným `Could not resolve to` níž, jinak by chybějící vlákno vyšlo jako
        // výpadek sítě. Hlášky se liší jen koncem (`…to a node with the global id` proti
        // `…to a Repository`), takže na pořadí těch dvou případů záleží — změřeno na živém
        // API u #73.
        case text.contains("Could not resolve to a node"):
            self = .threadNotFound(text)
        case text.contains("Line could not be resolved"):
            self = .lineOutsideDiff(text)
        case text.contains("Path could not be resolved"):
            self = .pathOutsideDiff(text)
        case text.contains("one pending review"):
            self = .pendingReviewExists
        // 422 při zakládání labelu: `{"resource":"Label","code":"already_exists","field":"name"}`.
        //
        // **Obojí naráz, ne `already exists` samo.** Tahle funkce třídí `failureText` **všech sedmi**
        // cest ven, a „already exists“ je v běžné angličtině GitHubu obvyklá fráze — v repu je
        // dvakrát ve zprávách commitů (`Tests/Fixtures/gh/pr-commits.json`). Kdyby na ni stačila
        // shoda, ohlásilo by se jako duplikát labelu kterékoli jiné selhání, jehož výstup ji nese.
        // Zúžení na strojový kód **a** jméno zdroje může nechat skutečný duplikát propadnout do
        // `unknown` (věta „Odeslání se nepovedlo: …“ s celým textem), a to je ta správná strana
        // omylu: neurčitá pravda je lepší než určitá nepravda.
        case text.contains("already_exists") && text.contains("Label"):
            self = .labelExists(text)
        // 409 u merge: `Head branch was modified. Review and try the merge again.` — tedy že
        // **zabrala hlava v payloadu**. `Base branch was modified` je totéž z druhé strany a vede
        // ke stejnému kroku, takže se poznává společný kus věty.
        case text.contains("branch was modified"):
            self = .branchMoved(text)
        // 405 u merge: `Pull Request is not mergeable`. **Před** obecným 403/422 níž není potřeba
        // nic řadit — je to jediná hláška, která tenhle text nese.
        case text.contains("not mergeable"):
            self = .notMergeable(text)
        case text.contains("Can not approve your own"),
             text.contains("Can not request changes on your own"):
            self = .ownPullRequest(text)
        case text.contains("HTTP 401"), text.contains("gh auth login"):
            self = .notAuthenticated
        case text.lowercased().contains("rate limit"):
            self = .rateLimited(text)
        case text.contains("error connecting to"), text.contains("Could not resolve to"):
            self = .network(text)
        default:
            self = .unknown(text)
        }
    }

    /// Věta pro okno. Ke každé chybě patří i to, co s ní jde udělat — chyba, ze které
    /// nevyplývá další krok, je jen zpráva o smůle.
    var userDescription: String {
        switch self {
        case .publishingNotAllowed(let repo):
            // **Bez slova „review“**: tatáž brána od #73 povoluje i odpovědi do vláken, takže
            // věta o review by u zakázaného `Odpovědět` mluvila o něčem jiném, než co uživatel
            // právě dělá. Zůstává jedna věta na jednom místě (delegují ji `DraftSendBlock`
            // i `ThreadActions`) a odkazuje na přepínač, který se jmenuje stejně.
            "Odesílání na GitHub není pro \(repo) povolené. Zapni ho v nastavení (⌘,)."
        case .staleDraft(let draft, let head):
            "Draft je psaný proti commitu \(draft.prefix(7)), ale hlava PR je \(head.prefix(7)). Načti diff znovu."
        case .pullRequestNotOpen(let state):
            // Neutrálně: tuhle chybu dostane i odpověď do vlákna, takže věta o review by
            // mluvila o něčem jiném, než co uživatel právě dělá.
            "Pull request není otevřený — je \(state.czechLabel). Odeslat se dá jen na otevřený PR."
        case .nothingToSend:
            "Není co poslat — draft je prázdný nebo v něm chybí verdikt."
        case .blankReply:
            // Ne „neuloží se“ ani „nepovedlo se“: GitHub prázdné tělo přijme a zahodí, takže
            // bez téhle věty by se odpověď jevila jako odeslaná. Změřeno v sandboxu.
            "Odpověď je prázdná. Napiš text — prázdný komentář GitHub tiše zahodí."
        case .blankComment:
            "Komentář je prázdný. Napiš text — prázdný komentář GitHub tiše zahodí."
        case .noReviewer:
            // **Ne „vyber člověka“**: od #392 se dá vyžádat i tým, a hláška, která nabídku
            // zužuje na lidi, mluví o něčem jiném, než co je na obrazovce (nález Copilota).
            "Nebyl vybraný nikdo, od koho review vyžádat. Vyber ze seznamu člověka nebo tým."
        case .blankLabelName:
            "Nový label nemá jméno. Napiš ho do hledacího pole v nabídce."
        case .labelExists:
            // **Ne „zkus to znovu“**: label existuje, takže druhý pokus dopadne stejně. Jediný
            // další krok je otevřít nabídku znovu — v ní už ten řádek bude.
            "Label toho jména už v repozitáři je. Zavři nabídku a otevři ji znovu, bude v seznamu."
        case .mergeWithoutHead:
            "Nevím, na který commit mergovat. Načti pull request znovu."
        case .notMergeable:
            // **Ne „zkus to znovu“**: dokud se stav nezmění, dopadne druhý pokus stejně.
            "GitHub merge odmítl — pull request se v tuhle chvíli mergnout nedá. Zkontroluj stav větve a checků."
        case .branchMoved:
            // Nejde o poruchu, ale o to, že ochrana zabrala — a proto se to říká jako fakt, ne
            // jako chyba: mergnout se nemá to, co člověk neviděl.
            "Větev se mezitím pohnula, takže se nic nemergovalo. Načti pull request znovu a podívej se, co přibylo."
        case .threadNotFound:
            "Vlákno na GitHubu není — někdo ho mezitím smazal, nebo je konverzace v okně stará. Načti ji znovu."
        case .lineOutsideDiff:
            "Některý komentář míří na řádek, který v diffu není. Neodeslalo se nic; přesuň ho na řádek uvnitř diffu."
        case .pathOutsideDiff:
            "Některý komentář míří na soubor, který v diffu není vůbec. Neodeslalo se nic; smaž ho nebo načti diff znovu."
        case .pendingReviewExists:
            "Na PR leží rozdělané review z prohlížeče. Dokonči ho nebo zahoď a zkus to znovu."
        case .ownPullRequest:
            "Na vlastní PR nejde poslat verdikt. Přepni na „jen komentář“."
        case .notAuthenticated:
            "`gh` není přihlášený. Spusť `gh auth login`."
        case .rateLimited:
            "GitHub omezuje počet dotazů. Zkus to za chvíli."
        case .network(let detail):
            "GitHub není dostupný: \(detail)"
        // Tři věty o nejistém výsledku, a všechny **neutrální**: nastanou u review i u odpovědi
        // do vlákna, takže „jestli review nedošlo“ by u zakázané odpovědi poslalo člověka hledat
        // něco, co neposílal. Co zůstává, je pokyn zkontrolovat to na GitHubu — ten platí pro
        // obojí a je to celý smysl těch hlášek.
        case .timedOut:
            "Odeslání trvalo moc dlouho. Zkontroluj na GitHubu, jestli přesto neprošlo."
        case .toolUnavailable(let detail):
            "`gh` se nepodařilo spustit: \(detail)"
        case .malformedResponse(let detail):
            "Odpověď GitHubu nejde přečíst, takže nevím, jak to dopadlo — zkontroluj to na GitHubu. \(detail)"
        case .interrupted:
            "Odesílání se přerušilo uprostřed. Zkontroluj na GitHubu, jestli přesto neprošlo."
        case .unknown(let detail):
            "Odeslání se nepovedlo: \(detail)"
        }
    }
}
