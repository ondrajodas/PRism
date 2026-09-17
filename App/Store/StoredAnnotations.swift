import Foundation

/// Co po sobě nechala jedna anotační session (#524) — přesně to, co leží v jednom souboru.
///
/// **Klíčem je hlava, ne otisk obsahu** (tvrdá podmínka č. 5), a je to rozhodnutí proti značce
/// `Prošlo` (#500), která to má obráceně. Tři důvody, každý sám o sobě stačí:
///
/// - **Anotace se nepočítá z obsahu hunku.** Věta *proč* vzniká z commitů, z popisu PR a z kódu
///   kolem; otisk hunku by ji tedy udržel při životě i tehdy, když se odpověď změnila (přepsaná
///   historie, nový commit, který tu změnu vysvětluje jinak). `Prošlo` je naopak tvrzení o tom,
///   **co jsem přečetl**, a to na ničem jiném než na bajtech nezávisí — proto tam otisk je.
/// - **Anotace se páruje pořadím hunku** (`HunkAnnotation.hunk`). Index je poziční, takže první
///   push, který přidá hunk nad ní, posune všechny ostatní; otisk by tu chybu nechytil, protože
///   obsah hunku se nezměnil, jen jeho číslo.
/// - **Zastarat má stejně jako nálezy.** Přesně to zadání #524 říká, a je to i to, co drží
///   dohromady příští kolo: s přírůstkovým review (#517) se anotace přepočítají nad novou hlavou.
///
/// **Jeden soubor na PR, ne na `(PR, hlava)`.** Užitečná je vždycky jen ta pro dnešní hlavu —
/// starší se nesmí ukázat ani jako zastaralá (viz výš), takže by soubory po starých hlavách byly
/// v cache mrtvé místo, které nikdo nečte a nic nemaže. Nový běh tedy ten předchozí **přepíše**;
/// je to tatáž úvaha jako u `ReadMark` a u draftu, jen s opačným závěrem o tom, co se z něj
/// smí ukázat. Rozhoduje `Policy.annotations(of:head:)`.
struct StoredAnnotations: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Hlava, nad kterou se anotovalo. Jediná věc, která rozhoduje o tom, jestli záznam platí.
    let headSha: String
    let hunks: [HunkAnnotation]
    let files: [FileAnnotation]
    /// Jak běh skončil. **Ukládá se i zabitá a spadlá session**, přestože z ní anotace nevypadnou
    /// (odpověď je poslední sdělení, viz `AnnotationSchema`): bez záznamu by se „zkusilo se to
    /// a nedoběhlo“ nedalo odlišit od „nikdy neběželo“, a příští otevření PR by session zaplatilo
    /// znovu. `outcome` v okně říká, za co ten záznam nemluví.
    let outcome: ReviewRunOutcome
    /// Cesta k `claude --resume <id>`.
    let sessionID: String?
    /// Přišla odpověď ve tvaru, který se dal přečíst? **Odděleno od prázdných seznamů** ze stejného
    /// důvodu jako `calledReportFindings` u běhu: „diff se nedal popsat“ a „nic jsem nepopsala“ se
    /// nesmí slít. U odpovědi posledním sdělením je to **důležitější** než u nástroje — je to
    /// zrovna ta cesta, kterou sběr umí tiše nefungovat (`docs/claude-cli.md`).
    let answered: Bool
    /// Kolik položek se nepodařilo přečíst. **Musí být vidět** — bez toho je anotace bez povinného
    /// pole k nerozeznání od hunku, který session schválně nepopsala.
    let dropped: Int
    let finishedAt: Date
    /// Co běh stál (#148). `nil` = nevíme, ne nula — stejná úmluva jako u běhu review.
    let usage: RunUsage?

    /// Je v záznamu vůbec co ukázat?
    var isEmpty: Bool { hunks.isEmpty && files.isEmpty }
}
