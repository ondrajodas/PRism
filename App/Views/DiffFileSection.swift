import SwiftUI

/// Jeden soubor v diffu: hlavička a pod ní řádky (#469).
///
/// Do #469 to byla `Section` v `LazyVStack(pinnedViews: [.sectionHeaders])`. Líný seznam z diffu
/// odešel (proč, je u `Policy.mountBand(visible:)`) a s ním i jediné SwiftUI zařízení, které
/// ukotvené hlavičky umí. **Zahodit je nešlo** — v návrhu je `.fhead { position: sticky; top: 0 }`,
/// takže je to vzhled —, takže se ukotvená hlavička kreslí **jednou, přes výřez**
/// (`DiffView.pinnedHeader`) a tahle sekce k tomu dodá jedinou věc, kterou to potřebuje: **kde
/// v obsahu její soubor leží**.
///
/// Rozsah se čte v souřadnicích **obsahu**, takže se scrollováním nemění a nic nestojí.
struct DiffFileSection<Header: View, Content: View>: View {
    /// Kam se zapíše rozsah tohohle souboru. Krabice mimo observable stav — zápis z geometrie
    /// nesmí překreslovat (#358).
    let extents: DiffFileExtents
    let fileID: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(DiffView.contentSpace))
        } action: { rect in
            extents.note(fileID, rect.minY...max(rect.maxY, rect.minY))
        }
    }
}

/// Kde v obsahu diffu leží který soubor.
///
/// Třída mimo observable stav, jako `DiffRowFrames` a `DiffBlockPlacement`: zapisuje se do ní
/// z geometrie a čte ji ukotvená hlavička, která se překresluje z jiného důvodu (posun výřezu).
@MainActor final class DiffFileExtents {
    private var ranges: [String: ClosedRange<Double>] = [:]
    /// Co krabice popisuje. `@State` detailu **přetéká mezi pull requesty** (jeden `DiffView`
    /// obslouží všechny otevřené záložky), takže bez tohohle by se v ní vrstvily rozsahy každého
    /// prohlédnutého PR — tentýž důvod jako `subject` u `DiffRowFrames`.
    private var subject: String?

    func reset(for subject: String) {
        guard self.subject != subject else { return }
        self.subject = subject
        ranges.removeAll()
    }

    func note(_ fileID: String, _ range: ClosedRange<Double>) {
        ranges[fileID] = range
    }

    /// Rozsahy v pořadí souborů. **Vrací je jedině tehdy, když jsou změřené všechny** — díra
    /// uprostřed by znamenala, že se u horní hrany drží hlavička souboru, který je jinde.
    func ordered(of files: [FileDiff]) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        result.reserveCapacity(files.count)
        for file in files {
            guard let range = ranges[file.id] else { return [] }
            result.append(range)
        }
        return result
    }
}

/// Hlavička souboru, který je právě u horní hrany výřezu (#469).
///
/// **Vlastní view, ne `@ViewBuilder` v `DiffView` — a je to výkonová podmínka.** Čte
/// `DiffViewport.top`, tedy hodnotu, která se mění při **každém** otočení kolečka; kdyby se to
/// čtení odehrálo v těle `DiffView`, překládalo by se při každém snímku celé tělo diffu — a v něm
/// se skládají řádky všech souborů (`DiffRow.rows(of:)`). Takhle se překresluje jedna hlavička.
///
/// Do #469 ukotvení obstarával `LazyVStack(pinnedViews: [.sectionHeaders])`. Proč se nekreslí
/// posunem u každé hlavičky, je u `Policy.pinnedFileHeader(files:top:headerHeight:)`.
struct DiffPinnedHeader<Header: View>: View {
    let files: [FileDiff]
    let extents: DiffFileExtents
    let viewport: DiffViewport
    @ViewBuilder let header: (FileDiff) -> Header

    /// Výška hlavičky, změřená **na ní samotné**. Nasadit ji konstantou by znamenalo druhé místo,
    /// které se s kresbou umí rozejít (#236).
    @State private var height = 0.0

    var body: some View {
        if let pinned = Policy.pinnedFileHeader(
            files: extents.ordered(of: files),
            top: viewport.top,
            headerHeight: height
        ), files.indices.contains(pinned.index) {
            header(files[pinned.index])
                .onGeometryChange(for: Double.self) { $0.size.height } action: { height = $0 }
                .offset(y: pinned.offset)
                // Bez ořezu by vysunutá hlavička přetekla nad diff — do lišty nad ním.
                .clipped()
        }
    }
}
