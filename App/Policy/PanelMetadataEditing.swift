import Foundation

/// Co se s labely a reviewery v panelu **smí** (#392).
///
/// Dvě různé otázky, a proto tři stavy, ne boolean:
///
/// - **Čí je PR.** Na cizím se to nedělá **nikdy** — přeštítkovat frontu někoho jiného není moje
///   věc a odebrat vyžádaného reviewera už vůbec. Akce tam proto **nejsou**, ne zašedlé: zašedlé
///   tlačítko tvrdí „tady se to dělá, jen teď ne“, a to by byla nepravda.
/// - **Jestli je povolené odesílat.** To se **mění** (přepínač v nastavení, per repo), takže
///   „tady se to dělá, jen teď ne“ je přesně pravda — a zakázané tlačítko s důvodem je správná
///   podoba. Tatáž úvaha jako u odpovědí do vláken (`AppStore.canPublishToThreads`).
extension Policy {
    enum MetadataEditing: Hashable, Sendable {
        /// Cizí PR — akce se nekreslí vůbec.
        case absent
        /// Vlastní PR, ale odesílání není povolené. Věta je ta samá, na které skončí publisher.
        case blocked(String)
        case allowed

        /// Kreslí se akce (`+ label`, `+ reviewer`)? Zakázaná akce se kreslí — jen se do ní
        /// nedá kliknout.
        var isVisible: Bool { self != .absent }

        var isAllowed: Bool { self == .allowed }

        var reason: String? {
            if case .blocked(let reason) = self { reason } else { nil }
        }
    }

    /// Smí se na tomhle PR měnit label a vyžádat reviewer?
    ///
    /// **Brána se předává, ne odvozuje** — `Policy` je bez I/O a ke konfiguraci se nedostane.
    /// Skládá ji volající, takže přepnutí v nastavení platí bez restartu; a je to **tatáž** brána
    /// jako u review a komentářů, protože druhý přepínač by byl druhé místo, kde se dá „samo nic
    /// neodejde“ porušit.
    ///
    /// `hasTool` je dostupné `gh`: bez něj nemá čím odejít nic, a to je porucha prostředí, ne
    /// nastavení — proto se hlásí jinou větou.
    static func metadataEditing(
        ownership: PullRequestOwnership,
        repo: RepoID,
        scope: PublishScope,
        hasTool: Bool
    ) -> MetadataEditing {
        guard ownership == .mine else { return .absent }
        guard hasTool else { return .blocked(PublishError.toolUnavailable("nenašel se").userDescription) }
        guard scope.allows(repo) else {
            return .blocked(PublishError.publishingNotAllowed(repo).userDescription)
        }
        return .allowed
    }

    /// Nová sada labelů po kliknutí na `label` v nabídce. `nil` = **nic se neposílá**.
    ///
    /// Tady stojí to, co má u labelů největší cenu: **z výběru nejde vyrobit label, který repo
    /// nezná.** Nabídka je uzavřená množinou z repozitáře a volný text neexistuje jako vstup —
    /// ale i tak se to ověřuje ještě tady, protože jediná kontrola ve view je kontrola, kterou
    /// příští obrazovka obejde. Label, který v repozitáři není, by se přidáním **vyrobil**, a ten
    /// už z repa sám nezmizí.
    ///
    /// Vrací **celou** sadu, ne rozdíl: `PUT /issues/{n}/labels` sadu nahrazuje, takže rozdíl by
    /// se musel skládat podruhé v publisheru — a dvě skládání téhož se rozejdou.
    static func toggledLabels(
        _ label: PullRequestLabel,
        on current: [PullRequestLabel],
        known: [PullRequestLabel]
    ) -> [String]? {
        guard known.contains(where: { $0.name == label.name }) else { return nil }
        let names = current.map(\.name)
        guard names.contains(label.name) else { return names + [label.name] }
        return names.filter { $0 != label.name }
    }

    /// Koho jde ještě vyžádat: lidi, kteří na repo smí, minus ty, kteří už vyžádaní jsou.
    ///
    /// Vyžádat znovu toho, kdo už vyžádaný je, GitHub sice snese, ale bylo by to tlačítko, po
    /// kterém se nic nestane. Kdo už **odpověděl**, v nabídce zůstává — vyžádat review po opravě
    /// je zrovna to, kvůli čemu se na tu nabídku kliká.
    static func reviewerCandidates(
        assignable: [String],
        reviewers: [RequestedReviewer]
    ) -> [String] {
        let waiting = Set(reviewers.filter { $0.answer == .waiting }.map(\.login))
        return assignable.filter { !waiting.contains($0) }.sorted()
    }
}
