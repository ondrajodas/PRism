import Foundation

/// Místa v aplikaci, která běží **uvnitř aktualizace grafu** — tedy uvnitř toho kola, které
/// u #361 nekonverguje (#361).
///
/// ## Proč zrovna tahle místa
///
/// V hořícím kole se **nepřeloží ani jedno tělo** (doloženo ve čtvrtém i sedmém záchvatu:
/// `MarkdownText` a `DiffRowView` mají ve vzorku nulu), takže `RenderDiagnostics.pass(_:)` v tom
/// stavu nezaznamená nic. Jediné, co z aplikace v kole doopravdy běží, jsou dvě věci — a obě jsou
/// tady:
///
/// - **dotazy na identitu**, které si `ForEach` čte při každém přerovnání obsahu líného seznamu
///   (`FileDiff.id` 140+84 vzorků a `DiffRow` 54 v sedmém záchvatu; `initializeWithCopy for
///   ConversationRow` 54+13+8 ve čtvrtém — u osy konverzace je to **jediná** přítomnost aplikace
///   v kole),
/// - **`of:` closure u `onGeometryChange`**, tedy čtení geometrie (`DiffPairBlockRowView.swift:50`
///   má v sedmém záchvatu 140 vzorků — přitom ablace nad usazenou scénou ji u #386 vyloučila).
///
/// Z obou se dá vzít evaluační zásobník (ověřeno spuštěním, viz `GraphProbe`), takže z nich jde
/// odpovědět na otázku, kterou #361 pořád má: **kdo si o to kolo řekl.**
///
/// ## Čím to nesmí být
///
/// - **Není to nový vstup do rozvržení.** Hák nic neměří a nic nezapisuje do stavu — jen
///   inkrementuje počitadlo v `RenderDiagnostics` (#252: počitadlo mimo observable stav) a případně
///   odebere vzorek zásobníku. Kdyby přidával `onGeometryChange` nebo `GeometryReader`, měnil by
///   graf, který má diagnostikovat.
/// - **Vypnutá diagnostika ho stojí jeden load `Optional`u**, protože celý `inGraph(_:)` je
///   `current?.…`. Proto smí být i na cestě identity, která je z těch dvou ta výrazně horkejší.
enum GraphSite: String, Sendable, CaseIterable {
    /// Identita řádku diffu, jak si ji čte `ForEach` v `DiffView`.
    case diffRowIdentity = "DiffRow.id"
    /// Identita souboru — sekce líného seznamu v `DiffView`.
    case fileIdentity = "FileDiff.id"
    /// Identita řádku osy konverzace.
    case conversationRowIdentity = "ConversationRow.id"
    /// Rámeček bloku dvojic v souřadnicích obsahu diffu (split).
    case pairBlockGeometry = "DiffPairBlockRow.geometry"
    /// Totéž v pohledu pod sebou.
    case blockGeometry = "DiffBlockRow.geometry"
    /// Rámeček jednoho řádku diffu.
    case lineGeometry = "DiffLine.geometry"
    /// Výřez a šířka obsahu celého diffu.
    case viewportGeometry = "DiffView.viewport"
}

/// Identita pro `ForEach` **a zároveň hák diagnostiky** (#361).
///
/// Proč extension a ne úprava `id` v modelu: `id` je vlastnost domény a čte ji i kód, který
/// s diagnostikou nemá nic společného (skoky na nález, `Policy`). Hák patří k diagnostice, takže
/// žije u ní — a v seznamu se pozná na první pohled, že je tam kvůli měření (`id: \.diagnosedID`).
///
/// Hodnota je **táž** jako `id`, takže se identita řádků nemění; kdyby se lišila, líný seznam by
/// při zapnuté diagnostice přerovnal obsah a měřilo by se něco jiného než při vypnuté.
extension DiffRow {
    var diagnosedID: String {
        RenderDiagnostics.inGraph(.diffRowIdentity)
        return id
    }
}

extension FileDiff {
    var diagnosedID: String {
        RenderDiagnostics.inGraph(.fileIdentity)
        return id
    }
}

extension ConversationRow {
    var diagnosedID: String {
        RenderDiagnostics.inGraph(.conversationRowIdentity)
        return id
    }
}
