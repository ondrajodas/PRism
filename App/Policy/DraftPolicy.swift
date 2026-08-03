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
    /// **Rozbalený kontext (#47) komentovat nejde.** Jsou to řádky, které v diffu nejsou:
    /// dotáhly se ze souboru, aby se nález mimo diff dal přečíst. Pozná se to tím, že řádek
    /// v žádném hunku není — `DiffRow` je skládá jako obyčejný kontext s oběma čísly, takže
    /// ze samotného `DiffLine` to poznat nelze a příslušnost k hunku se musí ověřit.
    static func commentableSide(of line: DiffLine, in file: FileDiff) -> DiffSide? {
        guard let side = side(of: line.kind) else { return nil }
        guard file.hunks.contains(where: { $0.lines.contains(line) }) else { return nil }
        return side
    }

    /// Dá se na tenhle řádek komentovat?
    static func isCommentable(_ line: DiffLine, in file: FileDiff) -> Bool {
        commentableSide(of: line, in: file) != nil
    }

    /// Kotva komentáře na tomhle řádku — `nil` znamená „nedá se komentovat“.
    static func commentAnchor(of line: DiffLine, in file: FileDiff) -> DraftAnchor? {
        commentableSide(of: line, in: file).flatMap { anchor(of: line, on: $0) }
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
    static func commentAnchors(in file: FileDiff) -> [DiffLine: DraftAnchor] {
        var result: [DiffLine: DraftAnchor] = [:]
        for hunk in file.hunks {
            for line in hunk.lines {
                guard let side = side(of: line.kind), let anchor = anchor(of: line, on: side) else {
                    continue
                }
                result[line] = anchor
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

    private static func side(of kind: DiffLine.Kind) -> DiffSide? {
        switch kind {
        case .added, .context: .right
        case .removed: .left
        case .meta: nil
        }
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
        guard let file,
              let hunkLine = file.hunks.lazy.flatMap(\.lines).first(where: { $0.newNumber == line }),
              let side = side(of: hunkLine.kind),
              let anchor = anchor(of: hunkLine, on: side)
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

    /// Dá se draft odeslat?
    ///
    /// Musí být z čeho poslat (`!isEmpty`), musí být vybraný verdikt a nesmí být zastaralý.
    /// Chybějící verdikt je vlastní důvod: `event` je v API povinný a hádat ho za člověka
    /// znamená odeslat něco jiného, než chtěl.
    ///
    /// **Prázdný komentář blokuje odeslání celého draftu.** Vzniká běžně — kliknutím na
    /// „komentovat“ se založí prázdný a text se dopisuje potom — a GitHub takový payload
    /// odmítne, přičemž odmítnutí je atomické, takže s ním padne i všechno ostatní. Tady
    /// se to pozná dřív, než se sáhne na síť.
    static func isSendable(_ draft: ReviewDraft, head headSha: String) -> Bool {
        guard !draft.isEmpty, draft.verdict != nil, !isStale(draft, head: headSha) else {
            return false
        }
        return !draft.comments.contains { $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
