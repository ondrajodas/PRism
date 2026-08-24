import Foundation

/// Text, který se otevírá v `CodeTextSheet`u — celý hunk (#157), nebo celý log jobu (#214).
///
/// **Jeden typ pro obě cesty a druh jako pole** (#417, sekce 28 návrhu). Co sheet *dělá*, je
/// u hunku i u logu totéž: jeden vybíratelný text, zalamování, `Zkopírovat vše`, `Zavřít` — druhé
/// view by to jen zdvojilo. Jak *velký* se otevře, je ale vlastnost obsahu, a rozhoduje o tom
/// `Policy.codeSheetSizing(kind:screen:)` právě podle `kind`.
///
/// Hlavička se sem nese **složená** (`title`, `slug`, `note`), ne jako data k sesazení. Věty o tom,
/// k čemu se text vztahuje, skládá `CodeSheetText` z toho, co ví volající — u logu je to stav jobu
/// a okamžik snímku, u hunku počet řádků —, a sheet o nich nerozhoduje: kdyby si je skládal sám,
/// musel by znát `PullRequestCheck` i `DiffHunk`.
struct CodeText: Identifiable, Hashable {
    /// Který profil velikosti to je. **Ne druhé view** — viz dokumentace typu.
    enum Kind: Hashable, Sendable {
        case hunk
        case log
    }

    let kind: Kind
    /// Odkud text je. Identita sheetu je z ní, takže dvě různá místa otevřou různý obsah.
    let id: String
    /// Nadpis hlavičky — `Hunk — src/Vault/SecretClient.php`, `Celý log — phpstan (level 8)`.
    let title: String
    /// Mono řádka pod nadpisem: hlavička hunku a commit, u logu `job.log · N řádků · velikost · PR`.
    let slug: String
    /// Třetí řádka hlavičky — k čemu se text vztahuje. U logu má **dvě podoby** (běžící job je
    /// snímek s časem, doběhlý „log je celý“), u hunku říká, že je to nová verze bez znaků změny.
    let note: String
    /// Cesta k souboru, ze které se pozná jazyk na obarvení.
    ///
    /// **`nil` u logu, a je to podmínka, ne shoda** (#417): obarvit v logu `[ERROR]` znamená skládat
    /// text po řádcích, tedy 155 ms proti 7,9 ms na 8,78MB logu (změřeno u #214). Do #417 to drželo
    /// jen tím, že `path` bylo jméno checku a `Language(path:)` v něm žádný jazyk nepoznal — tedy
    /// náhodou, kterou by rozbil check jmenující se `build.rs`.
    let path: String?
    /// Kód **bez** znaků změny a bez čísel řádků, nebo log **bez ANSI, ale s timestampy**.
    let code: String
    /// Kudy se jde pro novější text — `Otevřít celý log na GitHubu ↗`. `nil` = nikam.
    ///
    /// Log jobu je na síti (`gh` stahoval 8,78 MB 5,75 až 27,44 s, změřeno u #292), takže se
    /// přírůstek nepočítá a v patičce je odkaz. U hunku odkaz není: kód v sheetu je z checkoutu,
    /// ne z GitHubu.
    let link: URL?
}
