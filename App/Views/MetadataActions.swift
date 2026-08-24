import Foundation

/// Co se dá s labely a reviewery udělat (#392) — jedno místo, ne osm parametrů view.
///
/// Tentýž vzor jako `DraftActions` a `ThreadActions`: panel dostane akce jako hodnotu, takže se dá
/// složit i **bez** nich (offscreen render, náhled) a nemusí u toho znát `AppStore`.
///
/// Výchozí implementace nic nedělají schválně: panel bez akcí je panel jen ke čtení, a to je přesně
/// ta podoba, kterou má na cizím PR.
struct MetadataActions: Sendable {
    /// Přepnout jeden label. Sadu skládá `Policy`, ne tenhle uzávěr.
    var toggle: @MainActor (PullRequestLabel) -> Void = { _ in }
    /// Založit nový label v repozitáři **a přidat ho na PR** (#413) — dvě volání, jedna akce.
    ///
    /// **Bere celý label, ne jméno**: barvu vybírá `Policy` a je to tatáž hodnota, kterou nakreslil
    /// náhled v potvrzení. Kdyby se sem posílalo jméno, musela by se barva složit podruhé ve store —
    /// a dvě skládání téhož se rozejdou.
    var create: @MainActor (PullRequestLabel) -> Void = { _ in }
    /// Vyžádat review od jednoho člověka **nebo týmu**.
    var request: @MainActor (ReviewerCandidate) -> Void = { _ in }
    /// Dotáhnout nabídku labelů. Volá se **při otevření**, ne při kreslení panelu — nabídka se
    /// otevírá zřídka a volání navíc při každém výběru řádku by se platilo vždycky.
    var loadLabels: @MainActor () async -> Void = {}
    /// Dotáhnout nabídku lidí. Tatáž úvaha.
    var loadCandidates: @MainActor () async -> Void = {}
    /// Zahodit přečtenou chybu odesílání.
    var clearFailure: @MainActor () -> Void = {}
}
