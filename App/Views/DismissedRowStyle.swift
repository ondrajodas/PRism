import SwiftUI

/// Buňka tabulky nálezů: ztlumená, když je nález odmítnutý (#113), a s kontextovým menu, kterým
/// se to přepíná.
///
/// **Na buňkách, ne na tabulce.** `contextMenu(forSelectionType:)` jde přes výběr řádku, a na
/// ten je v panelu navázaný skok do diffu — pravý klik by tedy odscrolloval a přepnul tab, což
/// od vyvolání menu nikdo nečeká. Takhle se výběr nedotkne a menu vyjde nad celým řádkem,
/// protože se modifikátor přidá každé buňce.
struct DismissedRowStyle: ViewModifier {
    let row: FindingRow
    /// `nil` = jen ke čtení; menu se pak nekreslí.
    let actions: FindingActions?

    func body(content: Content) -> some View {
        content
            // Ztlumit, ne schovat. Odmítnutý nález zabírá jeden řádek naspod tabulky a je
            // pořád k přečtení — schovaný by se nedal odlišit od neexistujícího a nešlo by
            // zkontrolovat, co jsem odmítl.
            .opacity(row.dismissal == nil ? 1 : 0.5)
            .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        if let actions {
            if row.dismissal == nil {
                ForEach(FindingDismissal.Reason.allCases, id: \.self) { reason in
                    Button("Označit jako \(reason.label)") {
                        actions.dismiss(row.finding, reason)
                    }
                }
            } else {
                Button("Vrátit mezi platné") { actions.restore(row.finding) }
            }
        }
    }
}
