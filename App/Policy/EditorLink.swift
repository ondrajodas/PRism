import Foundation

extension Policy {
    // MARK: - Otevření souboru v editoru (#530)

    /// Znaky, které se v cestě k souboru **nechávají tak, jak jsou**; všechno ostatní se
    /// procentuje.
    ///
    /// Vychází z `urlPathAllowed`, ze kterého odcházejí čtyři znaky, a každý z nich má vlastní
    /// důvod:
    ///
    /// - **`:`** — u VS Code a Cursoru je dvojtečka oddělovač čísla řádku (`…/A.swift:81`), takže
    ///   soubor, který ji má ve jméně, by editor rozdělil na jiném místě, než kde se to myslelo.
    /// - **`&` a `=`** — u Xcodu leží cesta v **query** (`?url=file://…&line=81`), kde obojí dělí
    ///   parametry; `urlPathAllowed` je propouští, protože v cestě nic nedělí.
    /// - **`+`** — v query se čte jako mezera, což je zrovna ten znak, kvůli kterému se cesty
    ///   escapují nejčastěji.
    ///
    /// **Jedna sada pro všechny tři editory**, i když každý z nich potřebuje jen část z toho:
    /// dvě sady by znamenaly dvě odpovědi na otázku „co je v cestě bezpečné“ a rozdíl mezi nimi by
    /// se projevil jedině u souboru, který nikdo nemá. Lomítko zůstává nedotčené schválně — cesta
    /// v adrese má být čitelná.
    static let editorPathAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":&=+")
        return allowed
    }()

    /// Adresa, kterou dostane `NSWorkspace`, aby editor otevřel ten soubor na tom řádku.
    ///
    /// `nil` = **adresa se nesložila** a nesmí se otevřít nic. Nastane to jedině tehdy, když se
    /// cesta nedá procentovat nebo z výsledku nevznikne `URL` — je to pojistka, ne provozní stav.
    ///
    /// **Tvary schémat jsou tři a nejsou zaměnitelné.** VS Code i Cursor berou cestu jako
    /// **cestu adresy** a číslo řádku za dvojtečkou (`vscode://file/Users/…/A.swift:81`); Xcode
    /// bere `file://` URL jako **parametr** (`xcode://open?url=file:///Users/…/A.swift&line=81`).
    /// Skládá se to proto ručně a ne přes `URLComponents`: ten by v query nechal `&` i `=`
    /// nedotčené (jsou v `urlQueryAllowed`), takže by cesta s ampersandem rozbila parametr.
    ///
    /// **Řádek se přidává jen kladný.** Nula ani záporné číslo neexistují a `:0` by editor
    /// v lepším případě ignoroval, v horším skočil na začátek souboru a tvrdil, že tam nález je.
    /// Nález bez řádku (nález o souboru jako celku) je proto adresa bez řádku, ne `:1`.
    static func editorURL(_ editor: ExternalEditor, file: URL, line: Int?) -> URL? {
        let path = file.path(percentEncoded: false)
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: editorPathAllowed) else {
            return nil
        }
        let line = (line ?? 0) > 0 ? line : nil
        let text = switch editor {
        case .xcode:
            "xcode://open?url=file://\(encoded)" + (line.map { "&line=\($0)" } ?? "")
        case .vscode:
            "vscode://file\(encoded)" + (line.map { ":\($0)" } ?? "")
        case .cursor:
            "cursor://file\(encoded)" + (line.map { ":\($0)" } ?? "")
        }
        return URL(string: text)
    }

    /// Popisek tlačítka. **Jméno editoru je v něm napsané**, ne obecné `Otevřít v editoru`: co se
    /// otevře, se nastavuje jednou a pak se na to zapomene — a tlačítko, které spustí cizí
    /// aplikaci, má říct kterou.
    static func openInEditorTitle(_ editor: ExternalEditor) -> String {
        "Otevřít \(editor.locative)"
    }

    /// Věta u tlačítka: **co se otevře a proč to není tvůj klon.**
    ///
    /// Musí být, a je to podmínka téhle funkce, ne kosmetika: `Otevřít v Cursoru` nad diffem
    /// vypadá jako „otevři mi ten soubor“ a člověk, který v něm začne psát, čeká, že píše do
    /// svého repozitáře. Píše přitom do kopie v cache aplikace (tvrdá podmínka č. 3), a u
    /// **vlastního** PR do toho stromu, ze kterého změna odejde jedině přes `Force push` se
    /// sheetem (#466).
    ///
    /// Dvě různé věty proto, že to jsou dvě různá sdělení: u cizího PR je kopie **jen na
    /// přečtení** (co se v ní změní, nemá kam odejít), u vlastního je to pracovní strom, který
    /// jednu cestu ven má.
    static func editorNote(_ editor: ExternalEditor, ownership: PullRequestOwnership) -> String {
        let opening = "Otevře kopii z cache aplikace, ne tvůj klon."
        return switch ownership {
        case .mine:
            "\(opening) U vlastního PR je to strom pro srovnání větve (`-sync`) — co v něm "
                + "\(editor.title) změní, odejde jedině přes Force push s potvrzením."
        case .theirs:
            "\(opening) Je to pracovní kopie review, tedy kód k přečtení — změna v ní nemá kam odejít."
        }
    }

    /// Ze kterého stromu v cache se soubor otevře. `nil` = **v cache není ani jeden**.
    ///
    /// **Strom pro srovnání větve má přednost před tím od review**, a je to celé rozhodnutí téhle
    /// funkce. Strom review stojí na `headSha` v odpojené hlavě, takže je to kód k přečtení a nic
    /// víc; strom `-sync` je větev, ze které vede cesta ven (#466). Kdo si otevře soubor
    /// u vlastního PR, ho nejčastěji chce **opravit** — a oprava v odpojené hlavě je práce, která
    /// se zahodí s dalším `git worktree remove`.
    ///
    /// U cizího PR se tím nic nemění: `-sync` vzniká jedině při srovnávání **vlastní** větve,
    /// takže tam žádný není a rozhodne strom review.
    static func editorTree(sync: URL?, review: URL?) -> URL? { sync ?? review }

    /// Proč se nic neotevřelo — pull request nemá v cache pracovní kopii.
    ///
    /// **Vlastní věta, ne ta od zásuvky s terminálem**: tam se nabízí i bare klon, takže „nemá
    /// pracovní kopii“ znamená v každém z těch dvou míst něco trochu jiného, a hláška má říct,
    /// co s tím.
    static let editorNoWorktreeNote =
        "Tenhle pull request nemá v cache rozbalenou pracovní kopii — pusť na něj review, nebo "
        + "u vlastního srovnej větev."

    /// Soubor v pracovní kopii **není**. Běžný případ je smazaný soubor: v diffu je vidět, na
    /// disku po něm nezůstalo nic.
    static func editorMissingFileNote(_ path: String) -> String {
        "Soubor `\(path)` v pracovní kopii v cache není — smazané soubory otevřít nejde."
    }

    /// Cesta vede mimo cache, nebo je na ní symbolický odkaz.
    ///
    /// **Neříká „nepodařilo se otevřít“**, ale co se stalo: je to jediný stav v téhle akci, který
    /// znamená, že aplikace mířila někam, kam nesmí — a to se nemá schovat za obecnou chybu.
    static func editorRefusalNote(_ refusal: CacheFile.Refusal, path: String) -> String {
        switch refusal {
        case .outsideCache:
            "Cesta `\(path)` vede mimo cache aplikace, takže se v editoru neotevřela."
        case .symbolicLink:
            "Na cestě `\(path)` leží symbolický odkaz — ten by mohl vést mimo cache, takže se "
                + "v editoru neotevřela."
        }
    }

    /// Adresa se z cesty **nesložila** (`editorURL` vrátilo `nil`).
    ///
    /// **Vlastní věta, ne ta o cestě mimo cache**, a je to oprava z vlastní revize: sáhnout tady
    /// po `editorRefusalNote(.outsideCache…)` je pohodlné, ale tvrdilo by to víc, než co se stalo
    /// — cesta v cache **byla**, jen z ní nevznikla adresa. *Mířili jsme mimo cache* je jediná
    /// věta v téhle akci, u které se má někdo zarazit, a přestane platit v tu chvíli, kdy ji
    /// řekne i něco jiného.
    ///
    /// Je to **pojistka, ne provozní stav**: procentování cesty ani `URL(string:)` nad ní selhat
    /// prakticky nemá čím. O to důležitější je, aby ta jedna věta za rok nelhala.
    static func editorAddressNote(_ editor: ExternalEditor, path: String) -> String {
        "Adresu pro \(editor.title) se z cesty `\(path)` nepodařilo složit, takže se soubor "
            + "neotevřel."
    }

    /// Systém adresu odmítl. Nejčastěji proto, že editor **není nainstalovaný** — schéma pak
    /// nemá kdo obsloužit a `NSWorkspace` vrátí `false`.
    static func editorRefusedBySystemNote(_ editor: ExternalEditor) -> String {
        "Systém adresu nepřevzal — je \(editor.title) nainstalovaný?"
    }
}
