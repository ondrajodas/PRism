import SwiftUI

/// Nápověda a klik nad pásem mapy PR — **vlastní vrstva, ne kus těla kresby** (#501).
///
/// **Proč zvlášť: hover nemá překreslovat kresbu.** Je to tatáž věta jako u #358 (zpětná vazba
/// z každého snímku nesmí bezpodmínečně zapisovat do `@State`) a #438 (modifikátor se nepřipojuje
/// tam, kde jeho výsledek nikdo nepřečte), jen o krok dál: dokud `hovered` drželo tělo pásu, čtl
/// ho `hoveredTooltip` **v témže těle jako `Canvas`** — a přejezd hranice segmentu tedy přeložil
/// tělo mapy a překreslil celou kresbu, u PR o 158 souborech všech 158 segmentů. Přejezd pásu myší
/// je přitom **158 hranic za jedno gesto**, protože segment má při té hustotě 2 až 3 body.
///
/// Odsud se čte i **šířka pro gesta**: kresba si ji bere z `Canvas`u (tam je vždycky přesná),
/// kdežto gesto hlásí jen polohu. Měřit ji tady znamená, že se `onGeometryChange` z resizu okna
/// zapíše do stavu **téhle** vrstvy, ne do stavu pásu.
///
/// **Trefení má pořád jediný zdroj** (`PullRequestMapGeometry`) — jak nápověda, tak klik, tak
/// kresba. Dvě aritmetiky by znamenaly, že nápověda mluví o jiném souboru, než na který se skočí.
struct PullRequestMapHoverLayer: View {
    let segments: [PullRequestMapSegment]
    let spacing: Double
    /// Co nese nápověda nad prázdným místem. V úzké podobě, kde popisek s počty mizí, je to
    /// **jediné** místo, kde se `3 prošlé` dá přečíst.
    let summary: String
    let jump: (PullRequestMapSegment) -> Void

    /// Šířka pásu pro gesta. Čte se do stavu, ne v každém snímku — při nezměněné hodnotě se akce
    /// `onGeometryChange` nespustí (#361).
    @State private var width = 0.0
    /// Segment pod kurzorem. Zapisuje se **jen při změně** (`Policy.hoverChange`, #358).
    @State private var hovered: Int?

    var body: some View {
        // `Color.clear` sama plochu ke kliknutí nedělá, `contentShape` ano — a je to celá vrstva,
        // takže gesto i hover mají tentýž obdélník jako kresba pod nimi.
        Color.clear
            .contentShape(Rectangle())
            .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
            // Nápověda je **jedna**, ne na segment: text se mění podle toho, co je pod kurzorem.
            .help(tooltip)
            .onContinuousHover(coordinateSpace: .local) { phase in
                let next: Int? = if case .active(let point) = phase { geometry.index(at: point.x) } else { nil }
                if case .write(let value) = Policy.hoverChange(from: hovered, to: next) { hovered = value }
            }
            .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                guard let index = geometry.index(at: value.location.x),
                      segments.indices.contains(index)
                else { return }
                jump(segments[index])
            })
    }

    private var geometry: PullRequestMapGeometry {
        PullRequestMapGeometry(segments: segments, width: width, spacing: spacing)
    }

    private var tooltip: String {
        guard let hovered, segments.indices.contains(hovered) else { return summary }
        return Policy.mapTooltip(of: segments[hovered])
    }
}
