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

    /// Barva **ikony**: merge fialově, zavření červeně, zbytek ztlumeně.
    ///
    /// Vlastní barvu mají jen ty dvě, protože po nich se s PR nedá dál pracovat — a kde svítí
    /// všechno, nesvítí nic. Zbytek je `.secondary`, tedy **ztlumeně, ne barvou okolí**: ikona
    /// je ukazatel k textu, takže v plné síle by soupeřila s tím, co označuje. Dědit barvu
    /// okolí by u ní znamenalo totéž zvýraznění jako u věty vedle.
    var color: Color {
        switch event.kind {
        case .merged: .purple
        case .closed: .red
        default: .secondary
        }
    }

    /// Hlavní text řádku.
    ///
    /// U commitu je to jeho **titulek**, ne věta o pushnutí: kdo pushnul, říká avatar
    /// a ikona, kdežto titulek je to jediné, co o commitu něco vypovídá. Ostatní druhy jsou
    /// věta, protože u nich žádný vlastní text neexistuje.
    var title: String {
        switch event.kind {
        case .commit(_, let headline):
            headline.isEmpty ? "commit bez popisu" : headline
        case .reviewRequested(let reviewer):
            if event.isSelfDirected { "\(actor) si vyžádal review" }
            else if let reviewer { "\(actor) vyžádal review od \(reviewer)" }
            else { "\(actor) vyžádal review" }
        case .reviewRequestRemoved(let reviewer):
            if event.isSelfDirected { "\(actor) odebral svoje vyžádané review" }
            else if let reviewer { "\(actor) odebral vyžádané review od \(reviewer)" }
            else { "\(actor) odebral vyžádané review" }
        case .forcePushed:
            "\(actor) přepsal historii větve"
        case .readyForReview:
            "\(actor) označil PR za hotový k review"
        case .convertedToDraft:
            "\(actor) převedl PR na draft"
        case .merged(let branch):
            branch.map { "\(actor) mergnul PR do \($0)" } ?? "\(actor) mergnul PR"
        case .closed:
            "\(actor) zavřel PR"
        case .reopened:
            "\(actor) otevřel PR znovu"
        case .baseChanged(let from, let to):
            switch (from, to) {
            case (let from?, let to?): "\(actor) změnil base z \(from) na \(to)"
            case (nil, let to?): "\(actor) změnil base na \(to)"
            case (let from?, nil): "\(actor) změnil base z \(from)"
            case (nil, nil): "\(actor) změnil base"
            }
        }
    }

    /// Sází se titulek monospace?
    ///
    /// U commitu ano — je to jeho zpráva, tedy kód, a GitHub to kreslí stejně. Věty ostatních
    /// událostí kód nejsou. Rozhoduje o tom řádek, ne view: jinak by ve view stál `switch`
    /// nad druhem události.
    var isTitleCode: Bool {
        if case .commit = event.kind { true } else { false }
    }

    /// Údaj vpravo, monospace. `nil` = není co ukázat.
    var detail: String? {
        switch event.kind {
        case .commit(let oid, _): Self.short(oid)
        case .forcePushed(let before, let after):
            switch (before, after) {
            case (let before?, let after?): "\(Self.short(before)) → \(Self.short(after))"
            case (nil, let after?): Self.short(after)
            case (let before?, nil): Self.short(before)
            case (nil, nil): nil
            }
        default: nil
        }
    }

    /// Sha se zkracuje na sedm znaků, jako `git` a GitHub. Krátí se **až tady**, protože model
    /// nese to, co přišlo z API — celý sha se hodí na odkaz.
    private static func short(_ oid: String) -> String { String(oid.prefix(7)) }
}
