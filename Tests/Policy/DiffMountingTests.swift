import CoreGraphics
import Testing

@testable import PRism

/// Kdy je blok kódu nasazený a která hlavička souboru se drží u horní hrany (#469).
///
/// Obojí je čistá funkce a obojí drží něco, co se rozbije potichu: první to, že se v seznamu
/// nehromadí `NSTextView` (cena projíždění roste s **jejich** počtem, ne s délkou diffu), druhá
/// to, že hlavička souboru zůstane nahoře — což je v návrhu `position: sticky`, ne detail
/// implementace.
@Suite("Diff — nasazení bloků a ukotvená hlavička (#469)")
struct DiffMountingTests {
    /// Výřez 800 bodů vysoký, odscrollovaný na 2000. Krok pásu je pak 800: horní hrana spadne
    /// do úseku 2 (pás začíná o krok níž, na 800), dolní do úseku 4 (pás končí o krok výš, na 4000).
    private let visible = CGRect(x: 0, y: 2000, width: 900, height: 800)

    @Test("Pás je o výřez širší na každou stranu")
    func bandReachesBeyondViewport() {
        let band = Policy.mountBand(visible: visible)
        #expect(band == 800...4000)
        // Nad výřezem i pod ním je nejmíň jeden výřez rezervy — blok se tedy nasadí dřív, než
        // na něj kdokoli může vidět.
        #expect(visible.minY - band.lowerBound >= visible.height)
        #expect(band.upperBound - visible.maxY >= visible.height)
    }

    /// **Kvantování je půlka toho rozhodnutí**: pás čte každý blok v diffu, takže kdyby se měnil
    /// při každém otočení kolečka, překládalo by se při každém snímku celé tělo seznamu.
    @Test("Pás se posunem uvnitř kroku nemění")
    func bandIsQuantised() {
        let band = Policy.mountBand(visible: visible)
        for offset in [0.0, 1, 199, 399] {
            #expect(Policy.mountBand(visible: visible.offsetBy(dx: 0, dy: offset)) == band)
        }
        // Až přechod do dalšího kroku pásem pohne.
        #expect(Policy.mountBand(visible: visible.offsetBy(dx: 0, dy: 400)) == 1600...4000)
        #expect(Policy.mountBand(visible: visible.offsetBy(dx: 0, dy: 400)) != band)
    }

    /// Nízké okno má krok z podlahy, ne z výšky výřezu — jinak by se v pruhu o výšce dvou řádků
    /// bloky nasazovaly a odpojovaly při každém otočení kolečka.
    @Test("Nízké okno má nejmenší krok")
    func usesFloorForShortViewport() {
        #expect(Policy.minimumMountingMargin == 400)
        let low = CGRect(x: 0, y: 900, width: 900, height: 60)
        #expect(Policy.mountBand(visible: low) == 400...1600)
    }

    /// Nahoře se pás nedrží u nuly — sahá nad obsah. Je to schválně: řezat ho na nule by
    /// znamenalo druhé místo, které o obsahu něco tvrdí, a nasazení se rozhoduje **překryvem**,
    /// takže záporná hranice nikomu nevadí.
    @Test("Na začátku obsahu sahá pás nad nulu")
    func bandAtTheTop() {
        #expect(Policy.mountBand(visible: CGRect(x: 0, y: 0, width: 900, height: 800)) == -800...1600)
    }

    /// **Neznámý blok se nasazuje.** Je to ta jediná odpověď, po které nemůže zůstat prázdné
    /// místo: dokud se blok nikdy nekreslil, neví se, jak je vysoký, takže se nedá ani zastoupit.
    @Test("Nezměřený blok se nasazuje")
    func mountsUnmeasuredBlock() {
        #expect(Policy.isBlockMounted(nil, band: 800...4000))
    }

    @Test("Nasazuje se, co do pásu zasahuje")
    func mountsOverlappingBlocks() {
        let band = 800.0...4000
        #expect(Policy.isBlockMounted(1000...1100, band: band))
        // Přesah zdola i shora se počítá — blok delší než pás je pořád vidět.
        #expect(Policy.isBlockMounted(0...100_000, band: band))
        #expect(Policy.isBlockMounted(700...801, band: band))
        #expect(Policy.isBlockMounted(3999...4400, band: band))
        #expect(!Policy.isBlockMounted(0...799, band: band))
        #expect(!Policy.isBlockMounted(4001...4400, band: band))
    }

    // MARK: - Ukotvená hlavička

    private let files = [0.0...1000, 1000.0...1600, 1600.0...5000]

    /// Nad prvním souborem se nedrží nic — a stejně tak, dokud se rozsahy nezměřily.
    @Test("Bez souborů se hlavička nekreslí")
    func noHeaderWithoutFiles() {
        #expect(Policy.pinnedFileHeader(files: [], top: 0, headerHeight: 30) == nil)
        #expect(Policy.pinnedFileHeader(files: files, top: -20, headerHeight: 30) == nil)
    }

    @Test("Drží se hlavička souboru, ve kterém jsme")
    func picksTheFileAtTheTop() {
        #expect(Policy.pinnedFileHeader(files: files, top: 0, headerHeight: 30)?.index == 0)
        #expect(Policy.pinnedFileHeader(files: files, top: 999, headerHeight: 30)?.index == 0)
        #expect(Policy.pinnedFileHeader(files: files, top: 1000, headerHeight: 30)?.index == 1)
        #expect(Policy.pinnedFileHeader(files: files, top: 4000, headerHeight: 30)?.index == 2)
    }

    /// Uprostřed souboru je posun nulový — hlavička prostě sedí u hrany.
    @Test("Uvnitř souboru se hlavička neposouvá")
    func headerRestsAtTheTop() {
        #expect(Policy.pinnedFileHeader(files: files, top: 400, headerHeight: 30)?.offset == 0)
    }

    /// **Na konci souboru se hlavička vysune s ním**, aby ji hlavička dalšího souboru vytlačila
    /// místo aby ji překryla — to je celý rozdíl mezi `position: sticky` a plovoucím pruhem.
    @Test("Na konci souboru hlavička odjede")
    func headerLeavesWithItsFile() {
        // Konec prvního souboru je na 1000, hlavička vysoká 30 — od 970 výš se vysouvá.
        #expect(Policy.pinnedFileHeader(files: files, top: 970, headerHeight: 30)?.offset == 0)
        #expect(Policy.pinnedFileHeader(files: files, top: 985, headerHeight: 30)?.offset == -15)
        #expect(Policy.pinnedFileHeader(files: files, top: 999, headerHeight: 30)?.offset == -29)
    }

    /// Dokud se hlavička nezměřila, neposouvá se: záporný posun spočítaný z nuly by ji vytáhl
    /// nad obsah a při prvním snímku by problikla mimo své místo.
    @Test("Nezměřená hlavička se neposouvá")
    func unmeasuredHeaderDoesNotOffset() {
        #expect(Policy.pinnedFileHeader(files: files, top: 999, headerHeight: 0)?.offset == 0)
    }
}
