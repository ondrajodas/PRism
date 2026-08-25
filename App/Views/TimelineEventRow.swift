import SwiftUI

/// Událost časové osy převedená na řádek přehledu (#171) — symbol, věta a údaj vpravo.
///
/// Mimo view, jako `FindingRow` a `ReleaseRow`: texty se pak testují bez UI. **Datum si
/// formátuje view**, takže na locale nezávisí nic z toho, co je tady.
struct TimelineEventRow {
    let event: TimelineEvent

    /// Jméno toho, kdo za událostí stojí.
    ///
    /// `někdo` u smazaného účtu je pravda — kdežto věta bez podmětu by u části druhů vyšla
    /// jako „zavřel PR“ bez toho kdo. Nastává to zřídka a je to levnější než dvě znění
    /// každé věty.
    private var actor: String { event.actor?.login ?? "někdo" }

    var isBot: Bool { event.actor?.isBot ?? false }

    /// Ikona vlevo. Vede se tady, ne ve view: k druhu události patří stejně jako věta, takže
    /// by se dvě místa mohla rozejít.
    var symbol: String {
        switch event.kind {
        case .commit: "smallcircle.filled.circle"
        case .reviewRequested: "eye"
        case .reviewRequestRemoved: "eye.slash"
        case .forcePushed: "arrow.triangle.2.circlepath"
        case .readyForReview: "arrow.up.circle"
        case .convertedToDraft: "pencil.circle"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .reopened: "arrow.counterclockwise.circle"
        case .baseChanged: "arrow.triangle.branch"
        }
    }

    /// Barva uzlu na ose. `nil` = **bez vlastní barvy**, tedy neutrální puntík z palety.
    ///
    /// Vlastní barvu mají jen tři druhy — a kde svítí všechno, nesvítí nic. Merge a zavření
    /// proto, že po nich se s PR nedá dál pracovat; force push proto, že jím zastarají nálezy
    /// i rozdělané review, a to je jediná událost na ose, po které je něco potřeba udělat.
    ///
    /// **Volitelná, ne ztlumená konstanta** (#216): návrh kreslí neutrální uzel obrysem
    /// `--line` a symbolem `--ink-2`, tedy dvěma různými barvami. Jedna hodnota to neunese
    /// a `color == .secondary` jako test „je neutrální?“ je porovnávání barev, které se při
    /// první změně palety tiše rozejde.
    var tint: Color? {
        switch event.kind {
        case .merged: .purple
        case .closed: Palette.crit
        case .forcePushed: Palette.stale
        default: nil
        }
    }

    /// Hlavní text řádku **se zvýrazněnými účastníky** (#216).
    ///
    /// U commitu je to jeho **titulek**, ne věta o pushnutí: kdo pushnul, říká avatar
    /// a ikona, kdežto titulek je to jediné, co o commitu něco vypovídá. Ostatní druhy jsou
    /// věta, protože u nich žádný vlastní text neexistuje.
    ///
    /// Tučně jdou **jen jména** — kdo to udělal a komu. To je to, podle čeho se osa přejíždí
    /// očima; sloveso zvýrazněné být nemá, jinak je tučné skoro všechno. Zvýraznění se nese
    /// jako `inlinePresentationIntent`, tedy bez barvy a bez fontu: jak přesně se tučné kreslí,
    /// rozhoduje view (`ConversationEntryView`), tady je jen řečeno, **co** je jméno.
    var attributedTitle: AttributedString {
        switch event.kind {
        case .commit(_, let headline):
            AttributedString(headline.isEmpty ? "commit bez popisu" : headline)
        case .reviewRequested(let reviewer):
            if event.isSelfDirected { who() + " si vyžádal review" }
            else if let reviewer { who() + " vyžádal review od " + name(reviewer) }
            else { who() + " vyžádal review" }
        case .reviewRequestRemoved(let reviewer):
            if event.isSelfDirected { who() + " odebral svoje vyžádané review" }
            else if let reviewer { who() + " odebral vyžádané review od " + name(reviewer) }
            else { who() + " odebral vyžádané review" }
        case .forcePushed:
            who() + " přepsal historii větve"
        case .readyForReview:
            who() + " označil PR za hotový k review"
        case .convertedToDraft:
            who() + " převedl PR na draft"
        case .merged(let branch):
            branch.map { who() + " mergnul PR do " + name($0) } ?? who() + " mergnul PR"
        case .closed:
            who() + " zavřel PR"
        case .reopened:
            who() + " otevřel PR znovu"
        case .baseChanged(let from, let to):
            switch (from, to) {
            case (let from?, let to?): who() + " změnil base z " + name(from) + " na " + name(to)
            case (nil, let to?): who() + " změnil base na " + name(to)
            case (let from?, nil): who() + " změnil base z " + name(from)
            case (nil, nil): who() + " změnil base"
            }
        }
    }

    /// Věta bez sazby. **Odvozená z `attributedTitle`**, ne psaná podruhé: dvě znění téže věty
    /// by se rozešla a testy by hlídaly to, které není vidět.
    var title: String { String(attributedTitle.characters) }

    private func who() -> AttributedString { name(actor) }

    private func name(_ value: String) -> AttributedString {
        var text = AttributedString(value)
        text.inlinePresentationIntent = .stronglyEmphasized
        return text
    }

    /// Sází se titulek monospace?
    ///
    /// U commitu ano — je to jeho zpráva, tedy kód, a GitHub to kreslí stejně. Věty ostatních
    /// událostí kód nejsou. Rozhoduje o tom řádek, ne view: jinak by ve view stál `switch`
    /// nad druhem události.
    var isTitleCode: Bool {
        if case .commit = event.kind { true } else { false }
    }

    /// Sha, které k události patří, **v pořadí a po jednom** — návrh je kreslí jako samostatné
    /// odznaky se šipkou mezi nimi, takže je view potřebuje rozdělené. Prázdné = není co ukázat.
    var shas: [String] {
        switch event.kind {
        case .commit(let oid, _): [Self.short(oid)]
        case .forcePushed(let before, let after):
            [before, after].compactMap { $0.map(Self.short) }
        default: []
        }
    }

    /// Týž údaj jako věta. **Odvozený ze `shas`**, ať se sazba a text nemůžou rozejít.
    /// `nil` = není co ukázat.
    var detail: String? {
        shas.isEmpty ? nil : shas.joined(separator: " → ")
    }

    /// Sha se zkracuje na sedm znaků, jako `git` a GitHub. Krátí se **až tady**, protože model
    /// nese to, co přišlo z API — celý sha se hodí na odkaz.
    private static func short(_ oid: String) -> String { String(oid.prefix(7)) }
}
