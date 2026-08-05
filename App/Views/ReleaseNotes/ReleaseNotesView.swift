import SwiftUI

/// Novinky a historie verzí: vlevo seznam vydání, vpravo release notes vybraného.
///
/// Rozdělení se kreslí **jen nad načtenou historií**. Prázdný boční panel s chybou vedle by
/// říkal totéž dvakrát a hůř — dokud není co vybírat, je stav odpovědí na celé okno.
struct ReleaseNotesView: View {
    @Bindable var model: ReleaseNotesModel

    var body: some View {
        content
            .frame(minWidth: 640, minHeight: 420)
            .task {
                await model.load()
                // Otevřené okno znamená, že novinky někdo viděl — značka se posune i tehdy,
                // když se okno otevřelo z menu, ne po aktualizaci. Odznaky `nové` zůstanou:
                // počítají se proti značce **před** posunutím.
                model.markAsSeen()
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .notLoaded, .loading:
            ProgressView("Načítám vydání…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            failure(reason)
        case .loaded(let releases) where releases.isEmpty:
            ContentUnavailableView(
                "Žádná vydání",
                systemImage: "shippingbox",
                description: Text("V repozitáři \(Release.repository.description) zatím žádné vydání není.")
            )
        case .loaded(let releases):
            split(releases)
        }
    }

    /// Selhání s důvodem a tlačítkem — ne mlčení a ne prázdný seznam. Bez sítě se nesmí
    /// z výpadku stát „nic tu není“.
    private func failure(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("Novinky se nepodařilo načíst", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            Button("Zkusit znovu") {
                Task { await model.reload() }
            }
        }
    }

    private func split(_ releases: [Release]) -> some View {
        NavigationSplitView {
            List(rows(of: releases), selection: $model.selection) { row in
                ReleaseRowView(row: row)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail(of: releases)
        }
        // Titulek okna je jméno okna, vybraná verze jde do **podtitulku**. `navigationTitle`
        // v detailu přebije titulek scény, takže by v liště stálo jen `v1.1.23` a nešlo by
        // poznat, o jaké okno jde — chytilo se to na běžící aplikaci.
        .navigationTitle(ReleaseNotesWindow.title)
        .navigationSubtitle(model.selection ?? "")
    }

    /// Řádky se skládají **tady**, ne uvnitř buňky: `List` staví řádky líně a mimo sledování
    /// závislostí rodiče, takže odznak `nové` by se po načtení nemusel překreslit. Tatáž past
    /// jako u stavů v seznamu PR.
    private func rows(of releases: [Release]) -> [ReleaseRow] {
        releases.map { ReleaseRow(release: $0, isUnseen: model.unseen.contains($0.tag)) }
    }

    @ViewBuilder private func detail(of releases: [Release]) -> some View {
        if let release = releases.first(where: { $0.tag == model.selection }) {
            ReleaseNotesDetailView(release: release)
        } else {
            ContentUnavailableView(
                "Vyber verzi",
                systemImage: "sidebar.left",
                description: Text("Vlevo je seznam vydání, vpravo se ukáže, co se v něm změnilo.")
            )
        }
    }
}

/// Jedno vydání v seznamu: tag, název bez tagu a datum.
struct ReleaseRowView: View {
    let row: ReleaseRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // `verbatim`: `v1.1.23` není číslo a interpolace by ho protáhla přes locale.
                Text(verbatim: row.tag)
                    .font(.headline)
                if row.isUnseen {
                    Text("nové")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            if !row.title.isEmpty {
                Text(row.title)
                    .font(.callout)
                    .lineLimit(2)
            }
            // **S časem, ne jen datum.** Verze se vydávají po mergnutí PR, takže jich v jednom
            // dni vyjde klidně šest — a seznam, ve kterém stojí `5. 8. 2026` šestkrát pod
            // sebou, o pořadí neříká nic. Nahlášené při zkoušení.
            Text(row.publishedAt.formatted(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Release notes jedné verze.
struct ReleaseNotesDetailView: View {
    let release: Release

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Rectangle().fill(.separator).frame(height: 1)
                notes(of: release)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        let row = ReleaseRow(release: release, isUnseen: false)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: row.tag)
                .font(.title2)
                .bold()
            if !row.title.isEmpty {
                Text(row.title)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(release.publishedAt.formatted(date: .long, time: .shortened))
                Link("Otevřít na GitHubu", destination: release.url)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Prázdné tělo dostane větu, ne prázdno: vydání bez popisu se od nenačteného textu
    /// jinak nepozná.
    @ViewBuilder private func notes(of release: Release) -> some View {
        if release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Tohle vydání popis nemá.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            MarkdownText(text: release.body, font: .body)
        }
    }
}
