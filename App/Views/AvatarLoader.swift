import AppKit
import Observation

/// Obrázky uživatelů z GitHubu (#171).
///
/// **Jde to přes `HTTPGetting`, ne přes `AsyncImage`.** Ten by si otevřel vlastní
/// `URLSession` mimo jedinou cestu, kterou aplikace na síť chodí sama za sebe — takže by se
/// nedal ani nahradit v testech, ani spočítat mezi tím, co aplikace dělá. Cena je tenhle
/// soubor; hodnota je, že testy nechodí na síť a že je z architektury pořád vidět, kudy se
/// venku sahá.
///
/// **Žádná autentizace.** Avatary jsou veřejné (změřeno: HTTP 200 bez tokenu, 991 B na
/// 40×40), a `HTTPGetting` ani nemá čím token poslat — tvrdá podmínka č. 4 se tím nedotýká.
///
/// Bydlí v `App/Views/`, i když sahá na síť: existuje **jen** proto, aby měl `AvatarView` co
/// kreslit. V `App/Support/` by naznačoval, že ho používá i něco mimo okno.
@MainActor
@Observable
final class AvatarLoader {
    private let http: any HTTPGetting
    private var images: [URL: NSImage] = [:]
    /// Adresy, o které se už žádalo — **včetně těch, které se nepovedly**.
    ///
    /// Drží dvě věci naráz: sloučení souběžných požadavků a to, že se selhání v témže běhu
    /// nezkouší znovu. Řádky přehledu jsou v líném seznamu a překreslují se, takže bez toho
    /// by odscrollování znamenalo další dotaz na obrázek, který posledně nedorazil.
    private var attempted: Set<URL> = []

    init(http: any HTTPGetting = URLSessionHTTP()) {
        self.http = http
    }

    /// Obrázek, když ho máme. `nil` = ještě nedorazil, nebo nedorazí (pak kreslí `AvatarView`
    /// zástupný symbol).
    func image(for url: URL) -> NSImage? { images[url] }

    /// Stáhne obrázek, pokud se o něj ještě nežádalo.
    ///
    /// **Značka se zapisuje před prvním `await`**, takže dva řádky se stejným autorem
    /// vykreslené naráz dají jeden dotaz. Tatáž lekce jako u dvojkliku na odeslání odpovědi
    /// (#73): mezi kontrolou a zápisem nesmí být mezera, do které se vejde druhé volání.
    func load(_ url: URL) async {
        guard !attempted.contains(url) else { return }
        attempted.insert(url)

        do {
            let response = try await http.get(url, ifNoneMatch: nil)
            // Nenulový, ale nepovedený stav je běžná odpověď, ne chyba dopravy — a obrázek
            // z chybové stránky nevznikne, takže se rovnou zahazuje.
            guard response.statusCode == 200, let image = NSImage(data: response.body) else { return }
            images[url] = image
        } catch is CancellationError {
            // **Zrušení není zjištění** — tatáž zásada jako u `HealthMonitoru`. Řádky jsou
            // v líném seznamu, takže se `.task` ruší při odscrollování uprostřed stahování;
            // kdyby po sobě značka zůstala, ten avatar by se v celém běhu **nikdy** nenačetl,
            // i když nic neselhalo. Značka se proto uvolní a příští zobrazení řádku to zkusí
            // znovu. Chyceno vlastní revizí diffu, ne až v provozu.
            attempted.remove(url)
        } catch {
            // Chybějící avatar není chyba, o které by se mělo hlásit: řádek zůstane
            // s iniciálou a to je všechno, co se tím ztratí.
        }
    }
}
