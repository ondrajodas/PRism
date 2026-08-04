import Foundation

/// Kam se komentář v draftu váže — číslo řádku a strana diffu, přesně jak to chce API.
///
/// Dvě hodnoty spolu, ne každá zvlášť: k odebranému řádku patří číslo ze **staré** verze
/// souboru, takže volající, který si stranu a číslo vybírá sám, si je umí spárovat špatně —
/// a komentář pak odejde na jiný řádek, aniž by to bylo na čem poznat.
struct DraftAnchor: Hashable, Sendable {
    let line: Int
    let side: DiffSide
}

/// Kam převzatý nález (nebo vlastní poznámka) v draftu patří.
///
/// Rozhoduje o tom GitHub, ne vzhled okna: řádkový komentář bere jedině řádek uvnitř hunku
/// a cokoli jiného vrátí `422` — a s ním **celé** review (změřeno u #62). Nález mimo diff
/// proto jde do těla jako permalink, který GitHub vyrenderuje jako úryvek kódu.
enum DraftTarget: Hashable, Sendable {
    /// Řádkový komentář.
    case line(path: String, anchor: DraftAnchor)
    /// Položka v těle review. `path == nil` = nález se neváže k místu v kódu (a odkaz se
    /// nemá kam udělat), `line == nil` = odkaz na celý soubor.
    case body(path: String?, line: Int?)
}

/// Na které strany diffu se dá na jednom řádku komentovat.
///
/// Kontextový (nezměněný) řádek unese **obě**: je v obou verzích souboru, takže komentář jde
/// napsat vlevo i vpravo. **Změřeno u #98 na živém API** — `side: LEFT` na nezměněném řádku
/// GitHub přijme a zapíše jako `side: LEFT` s `line == original_line`; dokumentace u nezměněných
/// řádků `RIGHT` jen doporučuje, `LEFT` nezakazuje. Bez toho by ve split pohledu kliknutí do levé
/// poloviny založilo komentář vpravo, tedy „okno se otevře jinde, než kam jsem klikl“.
struct LineAnchors: Hashable, Sendable {
    var left: DraftAnchor?
    var right: DraftAnchor?

    var isEmpty: Bool { left == nil && right == nil }

    /// Kotva pro konkrétní stranu; `nil` = na tuhle stranu se komentovat nedá.
    func anchor(on side: DiffSide) -> DraftAnchor? {
        switch side {
        case .left: left
        case .right: right
        }
    }

    /// Kotva pro pohled pod sebou, kde se strana nevybírá — a pro převzatý nález, který stranu
    /// nemá. `right` je výchozí strana GitHubu a u nezměněného řádku ukazuje na novou verzi
    /// souboru, tedy na to, co člověk čte.
    var preferred: DraftAnchor? { right ?? left }
}

/// Rozhodování nad rozdělaným review. Čisté funkce, žádné I/O.
extension Policy {
    /// Ke které straně diffu by šel komentář na tomhle řádku — `nil` znamená „nedá se
    /// komentovat“.
    ///
    /// Pravidla jsou GitHubova, ověřená u #62 na živém API:
    /// - **řádek uvnitř hunku** komentovat jde, a to i **kontextový** (nezměněný);
    /// - **řádek mimo hunky** GitHub odmítne (`422 Line could not be resolved`) — a odmítne
    ///   s ním **celé** review, takže se to nesmí zkoušet naslepo;
    /// - `meta` řádek (`\ No newline at end of file`) není obsah souboru, takže nikdy.
    ///
    /// Strana se řídí druhem řádku: přidaný a kontextový patří k nové verzi (`right`, což je
    /// i výchozí strana GitHubu), odebraný ke staré (`left`). Odebraný řádek totiž v novém
    /// souboru neexistuje a jeho číslo je ze starého — bez správné strany by komentář odešel
    /// na jiný řádek.
    ///
    /// Vrací **kanonickou** stranu, tedy tu, která platí, když se nikdo neptá na konkrétní
    /// polovinu. Kontextový řádek unese i `left` (změřeno u #98) — na to je `LineAnchors`.
    ///
    /// **Rozbalený kontext (#47) komentovat nejde.** Jsou to řádky, které v diffu nejsou:
    /// dotáhly se ze souboru, aby se nález mimo diff dal přečíst. Pozná se to tím, že řádek
    /// v žádném hunku není — `DiffRow` je skládá jako obyčejný kontext s oběma čísly, takže
    /// ze samotného `DiffLine` to poznat nelze a příslušnost k hunku se musí ověřit.
    static func commentableSide(of line: DiffLine, in file: FileDiff) -> DiffSide? {
        guard let side = sides(of: line.kind).first else { return nil }
        guard file.hunks.contains(where: { $0.lines.contains(line) }) else { return nil }
        return side
    }

    /// Dá se na tenhle řádek komentovat?
    static func isCommentable(_ line: DiffLine, in file: FileDiff) -> Bool {
        commentableSide(of: line, in: file) != nil
    }

    /// Kotva komentáře na tomhle řádku — `nil` znamená „nedá se komentovat“.
    ///
    /// Kanonická strana, tedy ta, která platí bez dotazu na konkrétní polovinu diffu. Tudy
    /// chodí i převzatý nález, který stranu nemá.
    static func commentAnchor(of line: DiffLine, in file: FileDiff) -> DraftAnchor? {
        commentAnchors(of: line, in: file).preferred
    }

    /// Kotvy na obě strany diffu — `isEmpty` znamená „nedá se komentovat“.
    static func commentAnchors(of line: DiffLine, in file: FileDiff) -> LineAnchors {
        guard file.hunks.contains(where: { $0.lines.contains(line) }) else { return LineAnchors() }
        return anchors(of: line)
    }

    /// Kotvy všech komentovatelných řádků souboru, jedním průchodem.
    ///
    /// Existuje kvůli ceně: `commentableSide(of:in:)` ověřuje příslušnost k hunku **hledáním**,
    /// takže volat ho pro každý vykreslený řádek je kvadratické — u souboru o tisíci řádcích
    /// milion porovnání při každém překreslení diffu. Mapa se postaví jednou za soubor.
    ///
    /// Klíčem je celý řádek, a je to bezpečné: rozbalený kontext (#47) se řádku hunku nikdy
    /// nerovná, protože jeho čísla jsou z úseku **mimo** hunky. Kdyby se rovnal, dostal by
    /// z mapy odpověď „komentovat jde“, kterou GitHub odmítne.
    static func commentAnchors(in file: FileDiff) -> [DiffLine: LineAnchors] {
        var result: [DiffLine: LineAnchors] = [:]
        for hunk in file.hunks {
            for line in hunk.lines {
                let anchors = anchors(of: line)
                guard !anchors.isEmpty else { continue }
                result[line] = anchors
            }
        }
        return result
    }

    /// Patří rozdělaný komentář k tomuhle řádku diffu?
    ///
    /// Řídí se `side` ze stejného důvodu jako u vláken konverzace (`Policy.matches` nad
    /// `ReviewThread`): komentář k odebranému řádku má číslo ze staré verze souboru, takže
    /// porovnání s novým číslem by bublinu posadilo na jiný kód.
    static func matches(_ comment: ReviewDraftComment, _ line: DiffLine) -> Bool {
        switch comment.side {
        case .right: line.newNumber == comment.line
        case .left: line.oldNumber == comment.line
        }
    }

    /// Komentáře, které patří tomuhle souboru.
    ///
    /// Pořadí zůstává takové, v jakém jsou v draftu — tedy v jakém je člověk psal. Řadit je
    /// podle řádku by znamenalo, že se právě přidaný komentář objeví jinde, než kam se kliklo.
    /// Stará cesta se porovnává taky: komentář vznikl proti diffu, ve kterém soubor mohl
    /// vystupovat pod jiným jménem než dnes.
    static func comments(of file: FileDiff, from comments: [ReviewDraftComment]) -> [ReviewDraftComment] {
        comments.filter { $0.path == file.newPath || $0.path == file.oldPath }
    }

    /// Které strany diffu řádek unese, v pořadí od kanonické.
    ///
    /// Kontextový řádek unese **obě** — je v obou verzích souboru. Změřeno u #98, viz
    /// `LineAnchors`; do té doby tady stálo jen `.right` a kliknutí do levé poloviny split
    /// pohledu zakládalo komentář vpravo.
    private static func sides(of kind: DiffLine.Kind) -> [DiffSide] {
        switch kind {
        case .added: [.right]
        case .removed: [.left]
        case .context: [.right, .left]
        case .meta: []
        }
    }

    /// Kotvy řádku bez ověření hunku — vnitřní krok, protože příslušnost k hunku se ověřuje
    /// jednou za soubor (viz `commentAnchors(in:)`), ne pro každý řádek.
    private static func anchors(of line: DiffLine) -> LineAnchors {
        var result = LineAnchors()
        for side in sides(of: line.kind) {
            switch side {
            case .left: result.left = anchor(of: line, on: .left)
            case .right: result.right = anchor(of: line, on: .right)
            }
        }
        return result
    }

    /// Číslo se bere podle strany: vpravo nové, vlevo staré. Chybějící číslo znamená, že
    /// kotva není — na co GitHub nemá číslo, tam komentář nepustí.
    private static func anchor(of line: DiffLine, on side: DiffSide) -> DraftAnchor? {
        let number = switch side {
        case .right: line.newNumber
        case .left: line.oldNumber
        }
        return number.map { DraftAnchor(line: $0, side: side) }
    }

    // MARK: - Převzetí nálezu

    /// Kam převzatý nález patří.
    ///
    /// Řádkový komentář dostane jedině nález, jehož řádek je **uvnitř hunku** — jinak GitHub
    /// odmítne celé review. Zbytek (nález mimo diff, nález bez řádku, nález bez souboru) jde
    /// do těla review; permalink se z něj udělá tam, kde je co odkazovat.
    ///
    /// Cesta se překládá na tu, pod kterou soubor vystupuje **dnes** (`displayPath`): nález
    /// umí přijít pod starou cestou přejmenovaného souboru, kdežto permalink míří na hlavu PR
    /// a řádkový komentář taky.
    static func draftTarget(for finding: Finding, in diff: Diff?) -> DraftTarget {
        guard let path = finding.file else { return .body(path: nil, line: nil) }
        let file = diff?.file(at: path)
        let resolved = file?.displayPath ?? path

        guard let line = finding.line else { return .body(path: resolved, line: nil) }
        // Nález stranu nemá — hlásí se proti nové verzi souboru, takže platí kanonická
        // (`preferred`). Že kontextový řádek unese i `left`, je věc kliknutí ve split
        // pohledu, ne převzetí nálezu.
        guard let file,
              let hunkLine = file.hunks.lazy.flatMap(\.lines).first(where: { $0.newNumber == line }),
              let anchor = anchors(of: hunkLine).preferred
        else { return .body(path: resolved, line: line) }
        return .line(path: resolved, anchor: anchor)
    }

    /// Text, kterým se převzatý nález předvyplní — to, co napsal reviewer.
    ///
    /// Scénář selhání jde jako druhý odstavec, protože v review komentáři je to ta
    /// nejcennější věta („kdy to praskne“) a smazat odstavec je jedno gesto. Kategorie ani
    /// jméno revieweera se nepřidávají: komentář na GitHubu píšu **já** svým jménem.
    static func adoptedText(of finding: Finding) -> String {
        guard let scenario = finding.failureScenario, !scenario.isEmpty else { return finding.summary }
        return "\(finding.summary)\n\n\(scenario)"
    }

    /// Je nález už v rozdělaném review?
    ///
    /// U řádkového komentáře se porovnává kotva **a reviewer** — bez revieweera by se odznak
    /// objevil i u druhého nálezu na tomtéž řádku a vypadal by jako převzatý, aniž by byl.
    ///
    /// U položky v těle rozhoduje **přítomnost odkazu**. Text si člověk přepíše, odkaz ne —
    /// a když ho smaže, odznak zmizí, což je pravda. Nález bez souboru odkaz nemá, takže
    /// u něj odpověď zůstává `false` a dá se převzít i dvakrát; to je lepší než tvrdit, že
    /// v draftu je něco, co se nedá najít.
    static func isAdopted(
        _ finding: Finding,
        target: DraftTarget,
        in draft: ReviewDraft?,
        repo: RepoID
    ) -> Bool {
        guard let draft else { return false }
        switch target {
        case .line(let path, let anchor):
            return draft.comments.contains {
                $0.path == path
                    && $0.line == anchor.line
                    && $0.side == anchor.side
                    && $0.origin.reviewer == finding.reviewer
            }
        case .body(let path, let line):
            guard let path,
                  let link = permalink(to: path, line: line, in: repo, at: draft.headSha)
            else { return false }
            return draft.body.contains(link.absoluteString)
        }
    }

    /// Na kolika kotvách draftu leží **víc než jeden** komentář.
    ///
    /// Existuje kvůli tomu, co se dá čekat a nestane se: dva komentáře na jednom řádku
    /// **nevytvoří vlákno s odpovědí**, ale dvě samostatná vlákna vedle sebe. Změřeno u #73
    /// v sandboxu — payload review s dvěma komentáři na tomtéž řádku GitHub přijme a vláken
    /// přibudou dvě. `in_reply_to` v `comments[]` neexistuje a neodeslané vlákno navíc ještě
    /// nemá `id`, na které by šlo odkázat.
    ///
    /// Počítají se **místa, ne komentáře**, a je to celý smysl té změny: první verze sčítala
    /// komentáře napříč všemi sdílenými kotvami a okno z toho skládalo větu „N komentářů míří na
    /// stejný řádek“, což u dvou různých řádků po dvou komentářích tvrdilo nepravdu — čtyři
    /// komentáře na jeden řádek nemířily. Našel to Copilot na #119, a **podruhé** ještě
    /// v tomhle popisu, který po přejmenování pořád mluvil o počtu komentářů.
    ///
    /// Nula znamená, že každý komentář stojí na vlastní kotvě.
    static func linesWithSeveralComments(in draft: ReviewDraft?) -> Int {
        guard let draft else { return 0 }
        let counts = Dictionary(grouping: draft.comments, by: { AnchorKey($0) }).mapValues(\.count)
        return counts.values.filter { $0 > 1 }.count
    }

    /// Kotva komentáře jako klíč. Tři pole, protože komentář k odebranému řádku má stejné
    /// číslo jako ten k přidanému — a jsou to různá místa (viz `matches(_:_:)`).
    private struct AnchorKey: Hashable {
        let path: String
        let line: Int
        let side: DiffSide

        init(_ comment: ReviewDraftComment) {
            path = comment.path
            line = comment.line
            side = comment.side
        }
    }

    // MARK: - Tělo review

    /// Permalink na řádek v konkrétním commitu.
    ///
    /// GitHub ho v těle review vyrenderuje jako **obarvený úryvek kódu** (změřeno u #62),
    /// takže je to jediná cesta, kterou se do odeslaného review dostane nález mimo diff.
    /// Skládá se přes `URLComponents`, aby se mezera v cestě zakódovala — neescapovaná by
    /// odkaz rozlomila a úryvek by se nevyrenderoval.
    static func permalink(to path: String, line: Int?, in repo: RepoID, at headSha: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repo)/blob/\(headSha)/\(path)"
        components.fragment = line.map { "L\($0)" }
        return components.url
    }

    /// Položka do těla review: odkaz na kód a text pod ním.
    ///
    /// Odkaz musí stát **sám na řádku** — s textem na téže řádce z něj GitHub úryvek kódu
    /// neudělá a zůstane holá URL.
    static func bodyItem(text: String, link: URL?) -> String {
        guard let link else { return text }
        guard !text.isEmpty else { return link.absoluteString }
        return "\(link.absoluteString)\n\n\(text)"
    }

    /// Přidá položku do těla, aniž by zahodila, co v něm už je.
    ///
    /// Prázdný řádek mezi položkami není kosmetika: bez něj Markdown slije odkaz
    /// s předchozím odstavcem a úryvek kódu se nevyrenderuje.
    static func appendingBodyItem(_ item: String, to body: String) -> String {
        guard !body.isEmpty else { return item }
        return body.hasSuffix("\n") ? "\(body)\n\(item)" : "\(body)\n\n\(item)"
    }

    /// Je draft psaný proti staršímu commitu, než je hlava PR?
    ///
    /// Nový commit draft **nemaže**, jen zablokuje odeslání — vlastní próza nezastarává tak
    /// rychle jako strojové nálezy, takže ji zahodit je dražší než ji nechat s poctivým
    /// příznakem. Přenesení na nový commit řeší #67.
    ///
    /// Odvozuje se, neukládá: na rozdíl od `ReviewRecord.isStale` je hlava PR v tu chvíli
    /// po ruce (aplikace ji má z detailu), takže není důvod držet příznak, který se může
    /// rozejít s pravdou.
    static func isStale(_ draft: ReviewDraft, head headSha: String) -> Bool {
        draft.headSha != headSha
    }

    /// Proč se rozdělané review **nedá** odeslat. `nil` = dá se.
    ///
    /// Odpovídá na to **jedna funkce s důvodem**, ne boolean vedle ní. Do #68 tady stálo
    /// `isSendable`, které vracelo jen ano/ne — a vedle něj by teď existovala cesta, jak se
    /// zeptat a důvod nedostat. Zakázané tlačítko bez vysvětlení je přesně to, co se v tomhle
    /// okně nemá stát.
    ///
    /// Pořadí kopíruje `GhReviewPublisher.submit`: brána na odesílání, pak **všechno, co je
    /// vidět na samotném draftu**, a teprve pak to, co potřebuje hlavu PR. V publisheru je to
    /// totéž rozdělení — `PublishRequest.payload(for:)` běží před `preflight(_:)`.
    ///
    /// Není to jen kosmetika: hlásí se ten důvod, se kterým **se dá něco udělat**. Draft bez
    /// verdiktu má říct „vyber verdikt“, ne „zjišťuji, na kterém commitu PR stojí“ — čekání
    /// tu vadu nespraví, a když se detail navíc nepovede načíst, ukazovalo by okno donekonečna
    /// na síť místo na chybějící verdikt. Chytil to Copilot na #112.
    ///
    /// **Shoda s publisherem nemůže být úplná** a je to tak zamýšlené. `pullRequestNotOpen`
    /// tady protějšek nemá, protože stav PR známe jen z uloženého detailu — a ten je v tu
    /// chvíli z definice starší než pravda, takže zavřený PR pozná až pre-flight. Opačně
    /// `blankComment` protějšek v publisheru nemá: je to náš předstih před 422, a patří
    /// k obsahu draftu, protože se opravuje dopsáním textu.
    /// **Brána se předává parametrem**, protože `Policy` je bez I/O a ke konfiguraci se
    /// nedostane. Skládá ji volající při kliknutí, takže přepnutí v nastavení platí hned.
    static func sendBlock(
        for draft: ReviewDraft?,
        head headSha: String?,
        scope: PublishScope
    ) -> DraftSendBlock? {
        // Bez draftu není co posílat a hlavně není odkud vzít repo pro bránu níž.
        guard let draft else { return .nothingToSend }
        // Brána je první, stejně jako v publisheru — a je to jediný důvod, který se dopsáním
        // review nespraví.
        guard scope.allows(draft.pullRequest.repo) else {
            return .publishingNotAllowed(draft.pullRequest.repo)
        }
        guard !draft.isEmpty else { return .nothingToSend }
        guard draft.verdict != nil else { return .noVerdict }
        guard !draft.comments.contains(where: {
            $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return .blankComment }
        // Odtud dál se bez hlavy PR nedá říct nic. „Nevím, jaká je hlava“ přitom **není**
        // „zastaralé“ — proto vlastní případ. Proč ji neznáme, tahle funkce neví; doplní to
        // volající, který vidí stav načítání.
        guard let headSha else { return .headUnknown(detail: nil) }
        guard !isStale(draft, head: headSha) else {
            return .stale(draft: draft.headSha, head: headSha)
        }
        return nil
    }
}

/// Proč se rozdělané review nedá odeslat.
///
/// Typované, ne boolean, a se **větou pro okno**: mlčky zakázané tlačítko vypadá jako
/// rozbitá aplikace, a každý z těch důvodů vede jinam — prázdný komentář se dopíše, verdikt
/// vybere, zastaralý draft počká na přenesení (#69) a nepovolené repo na přepínač v nastavení.
enum DraftSendBlock: Hashable, Sendable {
    /// Draft neexistuje nebo v něm není nic, co by šlo poslat.
    case nothingToSend
    /// Odesílání není pro tohle repo povolené (`PublishScope`).
    case publishingNotAllowed(RepoID)
    /// Ještě nevíme, na kterém commitu PR stojí.
    ///
    /// `detail` = **proč** se to nepovedlo zjistit; `nil` znamená, že se detail pořád načítá.
    /// Rozdíl je v tom, co se s tím dá dělat: načítání se dořeší samo, selhání ne — a slíbit
    /// „hned to bude“ nad chybou, která sama nezmizí, je horší než mlčet. Tentýž rozdíl už
    /// v okně dělá `PullRequestDetailView.draftUnavailable`; doplňuje ho `AppStore`, protože
    /// stav načítání zná jen on.
    case headUnknown(detail: String?)
    /// Verdikt není vybraný. `event` je v API povinný a nepředvyplňuje se.
    case noVerdict
    /// Draft je psaný proti staršímu commitu, než je hlava PR.
    case stale(draft: String, head: String)
    /// Aspoň jeden řádkový komentář je prázdný.
    case blankComment

    /// Věta pro okno. Ke každému důvodu patří i to, co s ním jde udělat.
    var userDescription: String {
        switch self {
        case .nothingToSend:
            "Není co poslat — v review není tělo, verdikt ani komentář."
        case .publishingNotAllowed(let repo):
            // Delegovaná, ne opsaná: dvě formulace téhož omezení by se rozešly a jedna
            // z nich by pak tvrdila něco jiného než druhá.
            PublishError.publishingNotAllowed(repo).userDescription
        case .headUnknown(let detail?):
            "Nevím, na kterém commitu PR stojí, takže odeslat nejde. \(detail)"
        case .headUnknown:
            "Zjišťuji, na kterém commitu PR stojí. Odeslat půjde, jakmile to bude jasné."
        case .noVerdict:
            "Vyber verdikt — bez něj GitHub review nepřijme."
        case .stale(let draft, let head):
            "Review je psané proti commitu \(draft.prefix(7)), ale hlava PR je \(head.prefix(7)). Takhle se odeslat nedá."
        case .blankComment:
            "Některý řádkový komentář je prázdný. Dopiš ho, nebo ho vyjmi — GitHub by kvůli němu odmítl celé review."
        }
    }
}
