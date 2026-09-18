import Foundation

/// Co osmá session udělala s **tělem** návrhu review (#521).
///
/// **Bydlí v razítku návrhu** (`StoredAutoDraft.body`), tedy u dvojice `(PR, headSha)` — a je to
/// tatáž volba jako u razítka samotného (#520) a u kontroly nálezů (#150). Tvrdá podmínka č. 5 se
/// tím **drží, ne obchází**: nová hlava znamená nový záznam, ve kterém razítko není, takže z okna
/// zmizí pruh i s větou o hlasu. Žádná další kontrola na to není potřeba a žádná se na to nedá
/// zapomenout.
///
/// **Neukládá se text.** Ten leží v `ReviewDraft.body`, tedy tam, kde ho jdu přepsat — druhá kopie
/// téhož odstavce by byla stav, který se umí rozejít s tím, co je v composeru doopravdy. Tady
/// zůstává jedině to, co o něm okno říká: **z kolika mých review se bral hlas** a **proč se
/// nepoužil**.
///
/// Zapsané razítko je zároveň to, co drží **cenu**: dokud v něm nic není, pokládá se tělo za
/// nenapsané a session se po dalším načtení diffu pustí znovu. Proto se zapisuje **i selhání** —
/// razítko bez záznamu o nepovedeném běhu znamená session, která se zkouší při každém otevření PR.
struct AutoDraftBody: Codable, Hashable, Sendable {
    /// Kolik mých uložených těl review šlo session do zadání jako vzorek hlasu.
    ///
    /// **Nula je legitimní hodnota, ne chybějící údaj** (nový uživatel): pruh o ní mluví jinak než
    /// o pěti vzorcích, protože tělo napsané neutrálně **není** tělo v mém hlasu — a tvrdit to
    /// o něm by bylo právě to „text v UI, který tvrdí víc, než data unesou“.
    let samples: Int
    /// Proč odstavec v composeru není. `nil` = je tam.
    let failure: Failure?
    /// Co běh stál. `nil` = cenu nenahlásil (zabitá session bez `result` eventu).
    ///
    /// Drží se tady, aby dráha v `Průběhu` přežila restart — stejně jako u anotací
    /// (`StoredAnnotations.usage`). Do `SpendLedger` jde nezávisle na tom, a to **vždycky**:
    /// utracené zůstávají utracené, i když z běhu nic nevypadlo.
    let usage: RunUsage?
    /// Kdy běh skončil. `nil` = neví se (starší záznam).
    let finishedAt: Date?

    init(samples: Int, failure: Failure? = nil, usage: RunUsage? = nil, finishedAt: Date? = nil) {
        self.samples = samples
        self.failure = failure
        self.usage = usage
        self.finishedAt = finishedAt
    }

    /// Leží odstavec od session v composeru? `false` = leží tam něco jiného, nebo nic.
    var isUsed: Bool { failure == nil }

    /// Proč odstavec v composeru není (#521). **Výčet, ne věta**: rozhodnutí se testuje výčtem
    /// a věty k nim skládá `Policy.reviewBodyNote` — dvě skládání by znamenala, že pruh a dráha
    /// v `Průběhu` říkají o témž běhu něco jiného.
    enum Failure: Codable, Hashable, Sendable {
        /// Session to nedopsala — spadla, vypršel jí čas, nebo nevrátila text.
        ///
        /// **Composer po tomhle zůstává prázdný, a to je záměr.** Půlka odstavce je u textu
        /// odesílaného na GitHub horší než věta o tom, že se to nepovedlo.
        case session(detail: String)
        /// Než odstavec dorazil, začal jsem do composeru psát sám.
        ///
        /// **Vlastní případ, ne selhání session.** Ta doběhla v pořádku a peníze stála; co se
        /// nestalo, je zápis — a ten se nestal schválně: *co jsem začal psát já, aplikace nepřepíše
        /// ani o komentář* je tatáž věta, na které stojí brána `draftExists` u #520.
        case handWritten
    }
}
