import Foundation

/// Založení nového labelu z nabídky v panelu (#413) — **kdy se akce nabídne a jakou dostane barvu**.
///
/// Do #413 byla nabídka labelů uzavřená doopravdy: co repozitář nezná, se z panelu vybrat nedalo.
/// Cena za to byl odskok do prohlížeče kvůli jedinému štítku, tedy zrovna to, kvůli čemu #392
/// vzniklo. Zakládání to nahrazuje **krokem, ne odemčeným polem**: uzavřený zůstává **seznam**
/// (řádky nesou dál jen labely repozitáře a `↵` na nich pořád jen přepíná) a založení je vlastní
/// akce s vlastní klávesou, která vede na potvrzení.
///
/// Tady žije to, co z toho jde rozhodnout bez obrazovky — a je to schválně **jedna** funkce
/// s vyčerpávajícím výčtem důvodů, proč se akce nekreslí. Kdyby ta rozhodnutí byla rozeseté `if`y ve
/// view, nedal by se ten výčet otestovat a pátý důvod by se přidal potichu.
extension Policy {
    /// Label, který se z dotazu založí — i s barvou, kterou dostane. `nil` = **akce se nekreslí**.
    ///
    /// Pět důvodů, proč `nil`, a každý je jiná věta:
    ///
    /// - **Nabídka se ještě nenačetla** (`isLoaded == false`). Bez seznamu z repozitáře se nedá
    ///   poznat, jestli label toho jména už existuje — a `Bug` vedle `bug` je zrovna ten odpad, kvůli
    ///   kterému byla nabídka uzavřená. Prázdný **načtený** seznam je naopak odpověď: repo labely
    ///   nezná, takže se dá založit cokoli.
    /// - **Prázdné jméno.** Jméno se bere z dotazu, takže bez napsaného textu není co zakládat.
    /// - **Label toho jména už v repozitáři je** — shoda se posuzuje **týmž pravidlem jako hledání**
    ///   (`pickerSameName`), tedy bez ohledu na velikost písmen a diakritiku. Nabídne se naopak
    ///   i tehdy, když seznam něco **našel**: `bug-ui` v repu, který zná `bug-ui-legacy`, se založit
    ///   musí, jinak by taková jména nešla zakládat vůbec.
    /// - **Cizí PR** (`editing == .absent`). Přeštítkovat frontu někoho jiného se odsud nedělá
    ///   nikdy, takže tam není odkud zakládat.
    /// - **Vypnutá brána** (`editing == .blocked`). Tam je `+ label` zašedlé a důvod stojí v panelu
    ///   (#392), takže se do nabídky nedá ani dostat — a kdyby se to změnilo, nemá se odsud dát
    ///   založit nic.
    ///
    /// Vrací **`PullRequestLabel`, ne vlastní typ požadavku**, a je to rozhodnutí: druhý typ o dvou
    /// stejných polích by byl druhé místo, kde se dá barva složit jinak. Takhle je to jedna hodnota,
    /// kterou nakreslí náhled v potvrzení **a** pošle publisher — náhled tedy nemůže lhát, protože
    /// je to tentýž label.
    static func newLabelOffer(
        query: String,
        known: [PullRequestLabel],
        isLoaded: Bool,
        editing: MetadataEditing
    ) -> PullRequestLabel? {
        guard editing.isAllowed, isLoaded else { return nil }
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard !known.contains(where: { pickerSameName($0.name, name) }) else { return nil }
        return PullRequestLabel(name: name, color: labelColor(for: name))
    }

    /// Barva nového labelu — z výchozí palety GitHubu, **podle jména**.
    ///
    /// **Vybírá ji aplikace, ne člověk.** Dvě pole a vzorník by z popoveru o 300 bodech udělaly
    /// dialog kvůli hodnotě, na kterou se člověk podívá jednou; kdo ji chce jinou, mění ji tam, kde
    /// se label i maže — v prohlížeči. V potvrzení je vidět i s hexem, takže se z náhledu pozná,
    /// co vznikne.
    ///
    /// **Stejné jméno dá vždycky stejnou barvu**, a proto to počítá vlastní hash, ne `hashValue`:
    /// Swiftové hashování je zaseté náhodně **při každém spuštění procesu**, takže by tentýž label
    /// vyšel po restartu jinak — a „podle jména“ by bylo „podle náhody“. FNV-1a je pár řádků, je
    /// stabilní a nezávisí na verzi standardní knihovny.
    static func labelColor(for name: String) -> String {
        let index = Int(fnv1a(name) % UInt32(labelColors.count))
        return labelColors[index]
    }

    /// Šestnáct odstínů, které GitHub nabízí ve svém dialogu nového labelu — **hexy bez `#`**, jak
    /// je chce API i jak je drží `PullRequestLabel`.
    ///
    /// Je to paleta z **zakládání** labelu, ne barvy devíti výchozích labelů nového repozitáře:
    /// zakládá se tady, takže se bere ta, kterou na tomtéž místě nabízí GitHub. Bílá (`ffffff`)
    /// z výchozích labelů (`wontfix`) v ní schválně není — puntík by v panelu splynul se světlým
    /// podkladem a obtažení `--line` je proti němu slabé.
    static let labelColors = [
        "b60205", "d93f0b", "fbca04", "0e8a16",
        "006b75", "1d76db", "0052cc", "5319e7",
        "e99695", "f9d0c4", "fef2c0", "c2e0c6",
        "bfdadc", "c5def5", "bfd4f2", "d4c5f9",
    ]

    /// FNV-1a nad UTF-8 bajty. `&*` a `&+` schválně: přetečení je součást algoritmu, ne chyba.
    private static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}
