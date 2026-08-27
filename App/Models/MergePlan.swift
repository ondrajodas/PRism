import Foundation

/// Co se stane, když se klikne na `Mergnout` (#465) — **snímek, ne odkaz do storu**.
///
/// Tatáž úmluva jako u `ReviewDraft` v `ReviewSubmission`: co je v potvrzení vidět, to odejde.
/// Kdyby si sheet hodnoty dotahoval ze storu při kresbě, mohl by mezi otevřením a kliknutím
/// dorazit polling s jiným počtem commitů — a člověk by potvrdil něco jiného, než co četl.
///
/// **Metoda v plánu není, a je to rozhodnutí.** Squash je jediná, kterou aplikace posílá (tak se
/// v tomhle repu merguje a titulek PR je z něj commit message; kdo chce jinak, jde na GitHub),
/// takže pole s jedinou dosažitelnou hodnotou by byla mrtvá váha — a hlavně druhé místo, kde by se
/// dala rozejít kresba s payloadem. Sheet i payload ji čtou z jedné konstanty
/// (`MergeRequest.method`).
struct MergePlan: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Hlava, na kterou se merguje.
    ///
    /// Posílá se **v payloadu** (`sha`), ne jen kontroluje v pre-flightu: GitHub na tenhle
    /// parametr odpoví `409`, když se větev mezitím pohnula, takže je to jediná ochrana, která
    /// zabírá i na commit pushnutý mezi pre-flightem a voláním. U review taková možnost není
    /// (tam se `commit_id` bere jako údaj, ne jako podmínka — změřeno u #62).
    let headSha: String
    /// Jméno slévané větve, jak stojí v panelu i v potvrzení.
    let head: String
    /// Cílová větev.
    let base: String
    /// Kolik commitů se slévá do jednoho. **Z načteného seznamu commitů**, ne z vlastního dotazu:
    /// tab `Commity` je má stejně, a druhý dotaz na totéž se s prvním umí rozejít.
    let commits: Int
    /// Titulek squash commitu — **posílá se doslova takhle**.
    ///
    /// Skládá ho `Policy.squashTitle(of:number:)`, protože bez `commit_title` si ho GitHub vyrobí
    /// sám podle nastavení repozitáře, do kterého aplikace nevidí — a potvrzení by pak ukazovalo
    /// titulek, který nemusí vzniknout.
    let commitTitle: String
}

/// Co GitHub potvrdil po mergi (#465).
///
/// **Vrací se, co potvrdil GitHub, ne co jsme poslali** — stejně jako u `SubmittedReview`. Ze
/// `sha` je vidět, který commit doopravdy vznikl, takže se dá ukázat v okně bez dalšího čtení.
///
/// **Jen `sha`, i když odpověď má tři pole.** `merged` je podmínka, ne údaj (bez něj se
/// `MergedPullRequest` nesloží), a anglická věta `Pull Request successfully merged` se v českém
/// okně nikde neukazuje — držet ji by byl stav, který nikdo nečte. Do chybové hlášky se čte
/// **z odpovědi**, ne odsud.
struct MergedPullRequest: Hashable, Sendable {
    /// Sha commitu, který mergem vznikl.
    let sha: String
}
