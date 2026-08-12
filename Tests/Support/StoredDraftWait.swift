import Foundation
import Testing

@testable import PRism

/// Čekání na to, až se rozdělané review propíše **na disk** (#296).
///
/// Store si zápis draftu rozjede vlastním `Task`em, o kterém si nedrží handle
/// (`AppStore.persistDraft`) — hodnota se u toho čte až v tasku, aby dvě rychlé úpravy zapsaly
/// stejný konečný stav. Test tedy nemá co `await`nout a jediný jev, na který se dá čekat, je
/// **soubor**.
///
/// Do #296 se na tohle místo dával drain naslepo (`for _ in 0..<100 { await Task.yield() }`, pak
/// krátká odmlka). Na volném stroji to vycházelo, ale je to strop odvozený od volného stroje: při
/// třech souběžných clean buildech se zápis do 100 ms nestihl a `AppStoreSubmissionTests` hlásily,
/// že draft na disku není — tedy chybu aplikace tam, kde jen nebyl procesor.
///
/// **Používá se jen tam, kde se pak z disku doopravdy čte** (druhým storem, nebo `drafts.load()`).
/// Tam, kde test kouká na stav v paměti, se drain nechal: `mutateDraft` zapisuje do paměti
/// synchronně, takže tam není na co čekat.
/// **Ptá se po 10 ms, ne po milisekundě** jako ostatní čekání: každé kolo je čtení a dekódování
/// souboru, takže na milisekundovém taktu by z dvouminutového stropu bylo 120 tisíc čtení disku —
/// a to je tatáž zátěž, kvůli které se čeká. Zelený běh se tím nezdrží, zápis dosedne za jedno
/// dvě kola.
///
/// `try?` je tady na místě: chybějící soubor je normální mezistav, na který se čeká. Rozbitý soubor
/// se tím schová, ale nemá se odkud vzít — zapisuje ho ten samý test — a projeví se tím, že se
/// čekání nedočká.
func waitForStoredDraft(
    of pr: PRIdentifier,
    in drafts: ReviewDraftStore,
    exists: Bool = true,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let event = exists ? "draft dosedne na disk" : "draft z disku zmizí"
    await waitUntil(event, step: .milliseconds(10), sourceLocation: sourceLocation) {
        let stored = (try? await drafts.load(for: pr)) ?? nil
        return (stored != nil) == exists
    }
}

/// Totéž pro počet draftů v celém úložišti — některé testy se ptají na výpis, ne na jeden PR.
func waitForStoredDrafts(
    _ count: Int,
    in drafts: ReviewDraftStore,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    await waitUntil(
        "na disku bude \(count) draftů",
        step: .milliseconds(10),
        sourceLocation: sourceLocation
    ) {
        (try? await drafts.load().drafts.count) == count
    }
}
