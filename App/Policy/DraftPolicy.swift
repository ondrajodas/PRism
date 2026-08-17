import Foundation

/// Kam se komentář v draftu váže — číslo řádku a strana diffu, přesně jak to chce API.
///
/// Dvě hodnoty spolu, ne každá zvlášť: k odebranému řádku patří číslo ze **staré** verze
/// souboru, takže volající, který si stranu a číslo vybírá sám, si je umí spárovat špatně —
/// a komentář pak odejde na jiný řádek, aniž by to bylo na čem poznat.
///
/// `line` a `side` jsou **konec** rozsahu: u víceřádkového komentáře je to poslední řádek,
/// u kterého visí bublina (jako na GitHubu), a přesně ten pár, který jde do payloadu jako
/// `line`/`side`. Začátek je v `start` a `nil` znamená jednořádkový komentář.
struct DraftAnchor: Hashable, Sendable {
    let line: Int
    let side: DiffSide
    /// Začátek rozsahu, když je komentář víceřádkový. Jde do payloadu jako
    /// `start_line`/`start_side`.
    ///
    /// **`nil` u jednořádkového komentáře, ne `start == line`.** Změřeno u #110, že GitHub
    /// `start_line == line` přijme, takže by šlo mít jen rozsah — jenže pak by se u každého
    /// jednořádkového komentáře posílalo o dvě pole víc, než co prošlo u #62 a #67. Dvě
    /// podoby téhož by navíc byla past pro toho, kdo draft na disku čte, proto `Policy` rozsah
    /// s oběma konci na jednom řádku **srazí** na `nil`.
    let start: Endpoint?

    init(line: Int, side: DiffSide, start: Endpoint? = nil) {
        self.line = line
        self.side = side
        self.start = start
    }

    /// Jeden konec rozsahu. Tentýž pár jako `line`/`side` výš — vlastní typ proto, aby se
    /// konce nedaly zaměnit a aby šly seřadit.
    struct Endpoint: Hashable, Sendable {
        let line: Int
        let side: DiffSide
    }

    /// Konec rozsahu jako `Endpoint`, ať se dvojice konců dá řešit jednotně.
    var end: Endpoint { Endpoint(line: line, side: side) }

    var isRange: Bool { start != nil }
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

/// Jak dopadla kotva komentáře proti novému commitu (#69).
///
/// Čtyři stavy, ne dva, protože každý vede jinam — tatáž úvaha jako u `ReviewState`: „nevím“ není
/// „ztraceno“ a „posunulo se“ není „sedí“.
enum DraftAnchorState: Hashable, Sendable {
    /// Komentovaný řádek je pořád na svém místě.
    case fits
    /// Komentovaný řádek se v souboru našel jinde. Nese **novou** kotvu.
    case moved(DraftAnchor)
    /// Adresa pořád jde komentovat, ale **nevíme, co na ní bylo** — draft z doby před #69 nebo
    /// komentář založený bez načteného diffu. Rozhodnout musí člověk.
    case uncertain
    /// Komentovaný řádek v novém diffu není.
    case lost
}

/// Co se má s komentářem při přenesení stát.
enum DraftTransferChoice: Hashable, Sendable {
    /// Nechat kotvu, jak je. U `moved` to znamená **novou** kotvu ze stavu.
    case keep
    /// Přepsat na tělo review (s odkazem na kód) — text zůstane, kotva zmizí.
    case body
    case delete
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

    // MARK: - Rozsah řádků (#110)

    /// Spojí dva konce do rozsahu a **seřadí je podle pořadí, ve kterém se řádky kreslí**.
    ///
    /// Bere konce, ne celé kotvy: kdo rozsah roztahuje, musí sám rozhodnout, který konec zůstává
    /// na místě — u ⇧ kliku je to **začátek** už existujícího rozsahu, ne jeho konec.
    /// `nil` = některý konec v diffu není, takže rozsah nemá z čeho vzniknout.
    ///
    /// Pořadí se bere z diffu, ne z čísel, a je to podstatné: na jedné straně z toho vyjde
    /// vzestupné číslo, což GitHub kontroluje (`start_line > line` se stejným `side` skončí
    /// `422 Start position could not be resolved`), ale **napříč stranami nekontroluje nic** —
    /// `LEFT` a `RIGHT` jsou dvě různé osy číslování, takže rozsah `6 LEFT → 5 RIGHT` je
    /// v pořádku, i když čísla klesají. Obojí změřeno u #110.
    ///
    /// **Oba konce musí ležet v hunku, ale nemusí být ve stejném.** Rozsah smí přeskočit mezeru,
    /// která v diffu vůbec není (změřeno u #110) — jen konec mimo hunk je `422`.
    ///
    /// Když oba konce sedí na tentýž řádek, vyjde **jednořádkový** komentář: rozsah délky 1 by
    /// GitHub sice přijal, ale byla by to druhá podoba téhož (viz `DraftAnchor.start`).
    static func commentRange(
        from one: DraftAnchor.Endpoint,
        to other: DraftAnchor.Endpoint,
        in file: FileDiff
    ) -> DraftAnchor? {
        guard let first = position(of: one, in: file), let second = position(of: other, in: file) else {
            return nil
        }
        guard first != second else { return DraftAnchor(line: other.line, side: other.side) }

        let (start, end) = first < second ? (one, other) : (other, one)
        return DraftAnchor(line: end.line, side: end.side, start: start)
    }

    /// Řádky, které rozsah pokrývá — pro zvýraznění v diffu. Prázdné u jednořádkového
    /// komentáře i u toho, jehož konce v diffu nejsou.
    ///
    /// Pokrytí je **po řádcích diffu, ne po stranách**: rozsah je úsek toho, co se kreslí, takže
    /// kontextový řádek uprostřed do něj patří celý. Ve split pohledu se proto zvýrazní obě
    /// buňky takového řádku, a je to tak správně — ten řádek v rozsahu je.
    static func rangeLines(of comment: ReviewDraftComment, in file: FileDiff) -> Set<DiffLine> {
        rangeLines(of: comment.anchor, in: file)
    }

    /// Totéž pro rozsah, který ještě není komentářem — tažení ho ukazuje průběžně (#110).
    static func rangeLines(of anchor: DraftAnchor, in file: FileDiff) -> Set<DiffLine> {
        Set(rangeLinesInOrder(of: anchor, in: file))
    }

    /// Řádky rozsahu **v pořadí, jak stojí v souboru**.
    ///
    /// Zvýraznění pořadí nepotřebuje (ptá se jen `contains`), kopírování do schránky (#157) ano —
    /// a hledat konce rozsahu podruhé by znamenalo druhé místo, které to musí vědět stejně.
    static func rangeLinesInOrder(of anchor: DraftAnchor, in file: FileDiff) -> [DiffLine] {
        guard let start = anchor.start,
              let from = position(of: start, in: file),
              let to = position(of: anchor.end, in: file)
        else { return [] }

        let lines = file.hunks.flatMap(\.lines)
        return Array(lines[min(from, to)...max(from, to)])
    }

    /// Buňky pokryté rozsahy **všech** komentářů, které patří k tomuhle souboru — jedním
    /// průchodem, protože hledání konců jde přes všechny hunky a po řádcích by to bylo
    /// kvadratické (tentýž důvod jako u `commentAnchors(in:)`).
    static func commentRangeCells(of comments: [ReviewDraftComment], in file: FileDiff) -> Set<DraftAnchor.Endpoint> {
        self.comments(of: file, from: comments).reduce(into: Set<DraftAnchor.Endpoint>()) { result, comment in
            result.formUnion(rangeCells(of: comment.anchor, in: file))
        }
    }

    /// Buňky, které rozsah pokrývá — **řádek a strana**, ne jen řádek.
    ///
    /// Ve split pohledu je to rozdíl, na kterém záleží: rozsah tažený v pravém sloupci nemá
    /// zvýrazňovat levý, i když kontextový řádek stojí na obou stranách jako tatáž hodnota.
    /// Nahlášené při zkoušení #110 („označuje se levý i pravý řádek“) — do té doby bylo pokrytí
    /// po řádcích a bralo obě buňky.
    ///
    /// Strany bere z **konců** rozsahu: obvykle jedna, u rozsahu přes obě strany obě — ten spadá
    /// do obou sloupců doopravdy.
    static func rangeCells(of anchor: DraftAnchor, in file: FileDiff) -> Set<DraftAnchor.Endpoint> {
        let sides: Set<DiffSide> = anchor.start.map { [$0.side, anchor.side] } ?? [anchor.side]
        var result: Set<DraftAnchor.Endpoint> = []
        for line in rangeLines(of: anchor, in: file) {
            for side in sides {
                guard let number = number(of: line, on: side) else { continue }
                result.insert(DraftAnchor.Endpoint(line: number, side: side))
            }
        }
        return result
    }

    /// Číslo řádku na dané straně — vpravo nové, vlevo staré. `nil` = na téhle straně řádek není.
    static func number(of line: DiffLine, on side: DiffSide) -> Int? {
        switch side {
        case .right: line.newNumber
        case .left: line.oldNumber
        }
    }

    /// Kolikátý je řádek s tímhle koncem v pořadí kreslených řádků souboru. `nil` = není v diffu.
    ///
    /// Hledá se podle strany: vpravo se porovnává nové číslo, vlevo staré — tatáž otázka jako
    /// `matches(_:_:)` nad komentářem, jen nad koncem rozsahu.
    private static func position(of endpoint: DraftAnchor.Endpoint, in file: FileDiff) -> Int? {
        file.hunks.flatMap(\.lines).firstIndex { line in
            switch endpoint.side {
            case .right: line.newNumber == endpoint.line
            case .left: line.oldNumber == endpoint.line
            }
        }
    }

    // MARK: - Přenesení na nový commit (#69)

    /// Snímek kódu pod kotvou — text řádků, ke kterým se komentář píše.
    ///
    /// Bere se z diffu, ne od view: jedno místo, které ví, že vlevo je staré číslo a vpravo nové.
    /// Prázdný snímek znamená, že se to nedalo zjistit (soubor v diffu není) — a revalidace to pak
    /// musí říct, ne se tvářit, že kotva sedí.
    static func snapshot(of anchor: DraftAnchor, in file: FileDiff) -> DraftSnapshot {
        DraftSnapshot(
            anchored: text(at: anchor.end, in: file),
            start: anchor.start.flatMap { text(at: $0, in: file) }
        )
    }

    /// Text řádku na daném konci. `nil` = takový řádek v diffu není.
    static func text(at endpoint: DraftAnchor.Endpoint, in file: FileDiff) -> String? {
        file.hunks.lazy.flatMap(\.lines).first { line in
            number(of: line, on: endpoint.side) == endpoint.line
        }?.text
    }

    /// Jak dopadne kotva komentáře proti **novému** diffu.
    ///
    /// Rozhoduje **text**, ne číslo řádku: nový commit čísla posouvá, takže „stejné číslo“ neříká
    /// nic o tom, jestli tam pořád stojí komentovaný kód. Porovnává se **otrimovaný** text — změna
    /// odsazení je pořád tentýž řádek a přeanchorovat ho jinam by bylo horší než ho nechat.
    static func anchorState(of comment: ReviewDraftComment, in diff: Diff) -> DraftAnchorState {
        guard let file = diff.file(at: comment.path) else { return .lost }

        let anchor = comment.anchor
        // Bez snímku (draft z doby před #69) se dá zjistit jen tohle: leží ta adresa pořád
        // v hunku? Tvrdit „sedí“ by byl přesně ten tichý přenos, kterému se #69 vyhýbá.
        guard !comment.snapshot.isEmpty else {
            return line(at: anchor.end, in: file) == nil ? .lost : .uncertain
        }

        guard let end = endpoint(matching: comment.anchoredText, near: anchor.end, in: file) else {
            return .lost
        }
        guard let start = anchor.start else {
            return end == anchor.end ? .fits : .moved(DraftAnchor(line: end.line, side: end.side))
        }
        // U rozsahu musí sednout **oba** konce. Když jeden zmizel, přeanchorovat druhý by z rozsahu
        // udělalo něco jiného, než co člověk označil.
        guard let newStart = endpoint(matching: comment.startText, near: start, in: file),
              let range = commentRange(from: newStart, to: end, in: file)
        else { return .lost }

        return range == anchor ? .fits : .moved(range)
    }

    /// Výchozí volba pro každý stav kotvy.
    ///
    /// `lost` míří do **těla**, ne do koše: text je ručně psaná práce a odkaz na kód se z něj udělat
    /// dá, takže smazání musí být rozhodnutí člověka, ne výchozí stav. `uncertain` zůstává na svém
    /// místě, protože nejčastěji tam pořád je to, co komentoval — ale je to vidět v seznamu
    /// s výstrahou, takže tiché to není.
    static func defaultChoice(for state: DraftAnchorState) -> DraftTransferChoice {
        switch state {
        case .fits, .moved, .uncertain: .keep
        case .lost: .body
        }
    }

    /// Přenese draft na nový commit podle rozhodnutí, která člověk potvrdil.
    ///
    /// Chybějící rozhodnutí u komentáře znamená **výchozí** pro jeho stav; kdo sheet potvrdí bez
    /// klikání, dostane to, co v něm bylo vidět. `headSha` se přepíše **až tady**: dokud se draft
    /// nepřenesl, musí zůstat zastaralý, aby ho nešlo odeslat.
    static func transferring(
        _ draft: ReviewDraft,
        to diff: Diff,
        head: String,
        in repo: RepoID,
        choices: [UUID: DraftTransferChoice] = [:]
    ) -> ReviewDraft {
        var result = draft
        result.headSha = head
        result.comments = []

        for comment in draft.comments {
            let state = anchorState(of: comment, in: diff)
            switch choices[comment.id] ?? defaultChoice(for: state) {
            case .delete:
                continue
            case .body:
                // Odkaz míří na **nový** commit: tělo se odešle proti němu, takže permalink na
                // starou hlavu by ukazoval na kód, který v PR není.
                let item = bodyItem(
                    text: comment.body,
                    link: permalink(to: comment.path, line: comment.line, in: repo, at: head)
                )
                result.body = appendingBodyItem(item, to: result.body)
            case .keep:
                result.comments.append(moved(comment, by: state))
            }
        }
        return result
    }

    /// Komentář s kotvou podle stavu — u `moved` s novou, jinak s tou, kterou měl.
    ///
    /// Snímek **zůstává**: kotva se posunula právě proto, že se ten text našel jinde, takže je to
    /// pořád ten kód, ke kterému člověk komentoval. Přepsat ho textem z nového diffu by nic
    /// nezměnilo a při dalším commitu by se hledalo totéž.
    private static func moved(_ comment: ReviewDraftComment, by state: DraftAnchorState) -> ReviewDraftComment {
        guard case .moved(let anchor) = state else { return comment }
        return ReviewDraftComment(
            id: comment.id,
            path: comment.path,
            anchor: anchor,
            snapshot: comment.snapshot,
            body: comment.body,
            origin: comment.origin
        )
    }

    /// Konec s tímhle textem, **nejblíž** původnímu číslu. `nil` = text v diffu není.
    ///
    /// Nejblíž schválně: stejný řádek se v souboru vyskytuje víckrát (`}`, prázdný řádek), takže
    /// první nález by kotvu odnesl na druhý konec souboru. Strana se drží: komentář k odebranému
    /// řádku patří ke staré verzi, takže se hledá mezi odebranými.
    private static func endpoint(
        matching text: String?,
        near endpoint: DraftAnchor.Endpoint,
        in file: FileDiff
    ) -> DraftAnchor.Endpoint? {
        guard let text else { return nil }
        let wanted = text.trimmingCharacters(in: .whitespaces)

        return file.hunks
            .lazy
            .flatMap(\.lines)
            .compactMap { line -> DraftAnchor.Endpoint? in
                guard line.text.trimmingCharacters(in: .whitespaces) == wanted,
                      let number = number(of: line, on: endpoint.side)
                else { return nil }
                return DraftAnchor.Endpoint(line: number, side: endpoint.side)
            }
            .min { abs($0.line - endpoint.line) < abs($1.line - endpoint.line) }
    }

    /// Řádek na daném konci — `nil`, když v diffu není.
    private static func line(at endpoint: DraftAnchor.Endpoint, in file: FileDiff) -> DiffLine? {
        file.hunks.lazy.flatMap(\.lines).first { number(of: $0, on: endpoint.side) == endpoint.line }
    }

    /// Kde komentář je, jako text do panelu i do potvrzení odeslání — `Cart.php:26–31`.
    ///
    /// Jedno místo pro obě obrazovky: do #110 to byly dva shodné výrazy ve dvou views a text
    /// s rozsahem by se v jednom z nich zapomněl. Testuje se bez UI.
    ///
    /// Strana se píše jen tam, kde je jiná než výchozí (`starý`/`staré`) — u komentáře k nové
    /// verzi souboru by to byl šum u každého řádku.
    static func location(of comment: ReviewDraftComment) -> String {
        "\(comment.path):\(lines(of: comment))"
    }

    /// Jen ta čísla — `26–31`, `26 (starý)`. Bez cesty, protože bublina u kódu už ví, ve kterém
    /// souboru je; skládat to ve view přes hledání dvojtečky v `location` by se rozbilo na cestě,
    /// která dvojtečku obsahuje.
    static func lines(of comment: ReviewDraftComment) -> String {
        let anchor = comment.anchor
        guard let start = anchor.start else {
            return "\(anchor.line)\(anchor.side == .left ? " (starý)" : "")"
        }
        guard start.side == anchor.side else {
            // Rozsah přes obě strany (změřeno u #110, že ho GitHub bere): bez stran u obou
            // čísel by z `6–5` vypadal jako chyba.
            return "\(label(of: start))–\(label(of: anchor.end))"
        }
        return "\(start.line)–\(anchor.line)\(anchor.side == .left ? " (staré)" : "")"
    }

    private static func label(of endpoint: DraftAnchor.Endpoint) -> String {
        "\(endpoint.line)\(endpoint.side == .left ? " (starý)" : " (nový)")"
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
        /// Celá kotva, tedy i začátek rozsahu (#110): dva komentáře na **stejném** rozsahu jsou
        /// dvě vlákna k témuž místu, ale komentář na 26 a komentář na 20–26 míří jinam, i když
        /// mají stejný konec.
        let anchor: DraftAnchor

        init(_ comment: ReviewDraftComment) {
            path = comment.path
            anchor = comment.anchor
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

    // MARK: - Verdikt (#114)

    /// Verdikt, který na draftu **platí** — moje volba, jinak návrh z nálezů.
    ///
    /// Moje volba přebíjí návrh vždycky a druhý klik na ni ji ruší, takže se pak vrátí návrh.
    /// `nil` znamená „nevybráno **a** není z čeho navrhnout“ — a přesně kvůli tomu vrací
    /// `suggestedVerdict` `nil` místo opatrného `approve`: schválit PR proto, že reviewer spadl,
    /// je nejdražší chyba, kterou tahle aplikace umí udělat.
    ///
    /// **Návrhem se nic neukládá.** Draft zůstává `verdict == nil`, dokud na verdikt někdo
    /// neklikne; tohle je počítaná odpověď na „co by odešlo“, ne zápis. Do #114 se
    /// nepředvyplňovalo vůbec — proč se to rozhodnutí změnilo, je ve specifikaci.
    static func effectiveVerdict(
        of draft: ReviewDraft?,
        suggestion: ReviewVerdict?
    ) -> EffectiveVerdict? {
        if let chosen = draft?.verdict {
            return EffectiveVerdict(verdict: chosen, origin: .chosen)
        }
        return suggestion.map { EffectiveVerdict(verdict: $0.choice, origin: .suggested) }
    }

    /// Návrh, kterým se **smí** předvyplnit. `nil` = nepředvyplňovat.
    ///
    /// Na vlastním PR ne: `APPROVE` i `REQUEST_CHANGES` tam GitHub odmítne (změřeno u #62,
    /// `PublishError.ownPullRequest`) a návrh umí právě ty dva. Předvyplněním by se k odeslání,
    /// které skončí `422`, došlo snáz než dnes — projde tam jedině `COMMENT`, a ten se
    /// nepředvyplňuje nikdy, protože je to vědomé „nerozhoduju“.
    static func prefillableSuggestion(
        _ suggestion: ReviewVerdict?,
        author: String?,
        viewer: String?
    ) -> ReviewVerdict? {
        isOwn(author: author, viewer: viewer) ? nil : suggestion
    }

    /// Je to můj vlastní PR?
    ///
    /// **`false`, dokud nevíme, kdo se dívá** — `viewer` je z načtené konverzace, takže by
    /// opatrnost návrh schovala u každého PR, dokud nedorazí. Cena omylu je jedna chyba od
    /// GitHubu, a ta si o `Jen komentář` řekne sama; schovaný návrh naproti tomu nevysvětlí nic.
    ///
    /// Bere **dva optionaly, ne `Conversation`**, i když `Conversation.isMine` porovnává totéž.
    /// Právě ten stav „konverzaci nemám“ je to, o čem se tady rozhoduje, a `isMine` ho vyjádřit
    /// neumí — má `viewer` neoptional. Řetězit to přes model by znamenalo, že se rozhodnutí dělá
    /// v `??` u volajícího, tedy mimo `Policy` a mimo testy.
    ///
    /// **Samo porovnání dělá `Policy.ownership(ofAuthor:mine:)`** (#330), protože „je to moje?“ se
    /// od té doby ptá i seznam PR — a dvě odpovědi na tutéž otázku se rozejdou. Zbylo tedy jen to,
    /// co je na tomhle volajícím vlastní: viewer z **konverzace** (ne z `gh api user`, ta patří
    /// seznamu) a `Bool` místo `PullRequestOwnership`, protože předvyplnění je zákaz, ne rozřazení.
    /// Vedlejší efekt sdílené cesty: porovnává se **bez ohledu na velikost písmen** a s odstřiženými
    /// mezerami, takže `OndraJodas` z `gh` sedne na `ondrajodas` z konfigurace.
    static func isOwn(author: String?, viewer: String?) -> Bool {
        ownership(ofAuthor: author, mine: ownLogins(viewer: viewer)) == .mine
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
    ///
    /// **Návrh z nálezů verdikt zastoupí** (#114): `noVerdict` odpadá, když je z čeho navrhnout,
    /// protože odejde právě ten návrh. Ptá se na to přes `effectiveVerdict(of:suggestion:)`, tedy
    /// tou samou funkcí, ze které kreslí panel — dvě odpovědi na „platí nějaký verdikt?“ by se
    /// rozešly a okno by zakázalo tlačítko nad verdiktem, který je v něm vidět.
    ///
    /// Výchozí `nil` u návrhu znamená „žádný“, tedy chování před #114. Default tady být smí,
    /// protože jeho zapomenutí odeslání **zablokuje**, ne otevře — u `scope` je to obráceně
    /// a proto tam žádný není.
    static func sendBlock(
        for draft: ReviewDraft?,
        head headSha: String?,
        scope: PublishScope,
        suggestion: ReviewVerdict? = nil
    ) -> DraftSendBlock? {
        // Bez draftu není co posílat a hlavně není odkud vzít repo pro bránu níž.
        guard let draft else { return .nothingToSend }
        // Brána je první, stejně jako v publisheru — a je to jediný důvod, který se dopsáním
        // review nespraví.
        guard scope.allows(draft.pullRequest.repo) else {
            return .publishingNotAllowed(draft.pullRequest.repo)
        }
        guard !draft.isEmpty else { return .nothingToSend }
        guard effectiveVerdict(of: draft, suggestion: suggestion) != nil else { return .noVerdict }
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

    /// Dá se otevřít **potvrzení odeslání**? (Ne odeslat — to je až druhé tlačítko v něm.)
    ///
    /// **Není to `sendBlock == nil`.** Zastaralý draft se smí otevřít, když je proti čemu
    /// zkontrolovat kotvy (#69): okno tím začne a odeslání se odemkne až po přenesení. Ostatní
    /// důvody se opravují v panelu, takže nad nimi otevřít okno nemá smysl.
    ///
    /// Ptají se na to **dvě** místa — tlačítko v panelu a zkratka `⌘⏎` v detailu PR (#151).
    /// Do #151 to byla podmínka uvnitř `DraftPanel`; jako druhá kopie ve view by znamenala, že
    /// zkratka otevře okno tam, kde je tlačítko zakázané.
    static func canOpenSubmission(block: DraftSendBlock?, canTransfer: Bool) -> Bool {
        block == nil || needsTransfer(block: block, canTransfer: canTransfer)
    }

    /// Začne okno odeslání kontrolou kotev (#69)? Rozhoduje o tom i **jméno** tlačítka
    /// (`Zkontrolovat a odeslat…` místo `Odeslat review…`).
    static func needsTransfer(block: DraftSendBlock?, canTransfer: Bool) -> Bool {
        canTransfer && block?.isStale == true
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
    /// Verdikt není vybraný **a není z čeho ho navrhnout**.
    ///
    /// `event` je v API povinný, takže bez něj review neodejde. Od #114 se předvyplňuje návrhem
    /// z nálezů, takže tenhle důvod zbývá na PR, kde review neproběhlo, spadlo, ztratilo nález
    /// nebo je jeho záznam zastaralý — tam se vybírá ručně.
    case noVerdict
    /// Draft je psaný proti staršímu commitu, než je hlava PR.
    case stale(draft: String, head: String)
    /// Aspoň jeden řádkový komentář je prázdný.
    case blankComment

    /// Je to zastarání? Odsud se pozná, že se s tím dá něco udělat **v okně odeslání** (#69) —
    /// ostatní důvody se opravují v panelu, takže tam otevírat okno nemá smysl.
    var isStale: Bool {
        if case .stale = self { true } else { false }
    }

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
