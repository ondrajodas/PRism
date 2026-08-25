import Testing

@testable import PRism

/// Podoba tlačítka obnovení podle toho, jestli se aplikace ptá (#442).
///
/// Je to čistá funkce nad jedním `Bool`em, takže výčet je doopravdy vyčerpávající — a právě proto
/// sem patří i tvrzení, která vypadají triviálně. Ta zajímavá jsou dvě: **prstýnek a zákaz kliku
/// jdou spolu** (jedno bez druhého znamená točící se tlačítko, které pustí druhý dotaz, nebo mrtvé
/// tlačítko, na kterém není vidět proč), a **popisek se musí lišit** — pro čtečku obrazovky je to
/// jinak pořád stejné tlačítko `Obnovit` a celá změna se pro ni nestala.
@Suite("Tlačítko obnovení (#442)")
struct RefreshControlTests {
    @Test("V klidu je to šipka, která bere klik")
    func idleDrawsTheArrowAndTakesClicks() {
        let control = Policy.refreshControl(isRefreshing: false)

        #expect(!control.isSpinning)
        #expect(control.isEnabled)
        #expect(control.label == "Obnovit")
        // Zkratka v závorce je z katalogu (#441), jak ji kreslí návrh — ne opsaná vedle klávesy.
        #expect(control.help == "Obnovit seznam (⌘R)")
    }

    @Test("Po dobu dotazu se točí prstýnek a klik neprojde")
    func refreshingSpinsAndRefusesClicks() {
        let control = Policy.refreshControl(isRefreshing: true)

        #expect(control.isSpinning)
        #expect(!control.isEnabled)
    }

    /// **Tvrzení o tom, co se nesmí slít.** Prstýnek bez zákazu kliku by druhý dotaz pustil; zákaz
    /// bez prstýnku by byl tlačítko, které přestalo reagovat a neřeklo proč. Vyčerpávající výčet
    /// obou stavů to hlídá jedním pravidlem, ne dvěma tvrzeními, která se dají opravit každé zvlášť.
    @Test("Točí se právě tehdy, když je klik zakázaný")
    func spinningAndDisabledAlwaysGoTogether() {
        for isRefreshing in [true, false] {
            let control = Policy.refreshControl(isRefreshing: isRefreshing)
            #expect(control.isSpinning == !control.isEnabled)
        }
    }

    /// Popisek pro čtečku obrazovky **i nápověda** se musí lišit. Bez toho by z celé změny nezbylo
    /// pro VoiceOver nic — a nápověda `Obnovit seznam` nad tlačítkem, které klik nebere, by lhala.
    @Test("Popisek i nápověda se v obou stavech liší")
    func bothStatesSpeakDifferently() {
        let idle = Policy.refreshControl(isRefreshing: false)
        let busy = Policy.refreshControl(isRefreshing: true)

        #expect(idle.label != busy.label)
        #expect(idle.help != busy.help)
        #expect(busy.label == "Obnovuje se")
        #expect(!busy.help.isEmpty)
    }
}
