import Foundation

/// Co aplikace navrhuje udělat s PR.
///
/// **Návrh, ne akce.** Odeslat review umí od #67 jedině `ReviewPublishing`, jedině na výslovný
/// pokyn člověka a jedině tam, kde se to povolilo — tohle je vstup do jeho rozhodnutí. Od #114
/// se jím verdikt draftu **předvyplňuje**, ale pořád se neukládá: viz `EffectiveVerdict`.
///
/// Neukládá se — odvozuje se z uložených nálezů, takže `Codable` by popisoval tvar, který
/// na disku nikdy není. Proto tu jako jediný z modelů chybí.
enum ReviewVerdict: Hashable, Sendable {
    case approve
    case requestChanges

    /// Volba draftu, která z návrhu vyjde — tedy to, co by šlo do `event`.
    ///
    /// `comment` mezi návrhy není a nebude: je to vědomé „nerozhoduju“, tedy pravý opak návrhu
    /// odvozeného z nálezů. Právě proto je `ReviewDraft.Verdict` vlastní typ se třemi případy.
    var choice: ReviewDraft.Verdict {
        switch self {
        case .approve: .approve
        case .requestChanges: .requestChanges
        }
    }
}

/// Verdikt, který na rozdělaném review **platí** — a odkud se vzal (#114).
///
/// Dvě hodnoty spolu schválně: `APPROVE` z návrhu aplikace a `APPROVE`, který jsem vybral,
/// odejdou na GitHub stejně, ale v okně se **musí** dát odlišit. Tatáž úvaha jako
/// u `ReviewDraftComment.Origin`, kde jde o rozdíl mezi převzatým nálezem a vlastní poznámkou.
/// Do #114 stačila hodnota, protože jiný původ neexistoval.
///
/// **Neukládá se.** Návrh v draftu na disku není (draft zůstává `verdict == nil`) a počítá se
/// z nálezů při každém vykreslení. Kdyby se zapsal, vznikl by draft ze samotného otevření PR —
/// a „draft existuje“ musí znamenat „je co poslat“, protože na tom stojí indikátor v řádku
/// seznamu i pravidlo, že se prázdný draft maže.
struct EffectiveVerdict: Hashable, Sendable {
    let verdict: ReviewDraft.Verdict
    let origin: Origin

    /// Odkud se verdikt vzal.
    enum Origin: Hashable, Sendable {
        /// Návrh z nálezů. Nikdo ho nevybral, jen se jím předvyplnilo.
        case suggested
        /// Moje volba. Návrh přebíjí vždycky.
        case chosen
    }

    var isSuggested: Bool { origin == .suggested }
}
