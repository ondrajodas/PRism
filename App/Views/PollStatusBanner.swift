import SwiftUI

/// Pruh nad seznamem, když data nejsou čerstvá.
///
/// Když je všechno v pořádku, nekreslí se vůbec — trvalý pruh „vše OK“ by jen ubíral
/// místo seznamu a naučil by oko ho přehlížet.
struct PollStatusBanner: View {
    let status: PollStatus
    let lastSuccess: Date?

    var body: some View {
        if let content {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: content.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.headline).fontWeight(.medium)
                    Text(content.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(content.tint)
            .padding(10)
            .background(content.tint.opacity(0.12))
        }
    }

    private struct Content {
        let symbol: String
        let headline: String
        let detail: String
        let tint: Color
    }

    private var content: Content? {
        switch status {
        case .notStarted, .upToDate:
            nil
        case .rateLimited(_, let retryAt):
            Content(
                symbol: "hourglass",
                headline: "GitHub omezuje dotazy — zkusím to v \(time(retryAt))",
                detail: freshness,
                tint: .orange
            )
        case .failing(let since, let reason):
            Content(
                symbol: "exclamationmark.triangle",
                headline: headline(failingSince: since),
                detail: reason.userDescription,
                tint: .red
            )
        }
    }

    /// Když se ještě nikdy nepovedlo načíst, není co označit za neaktuální — je prázdno.
    private func headline(failingSince since: Date) -> String {
        lastSuccess == nil
            ? "Seznam PR se nepodařilo načíst"
            : "Neaktuální — obnovení se nedaří od \(time(since))"
    }

    private var freshness: String {
        guard let lastSuccess else { return "Zatím se nepodařilo načíst žádná data." }
        return "Zobrazená data jsou z \(time(lastSuccess))."
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    VStack(spacing: 0) {
        PollStatusBanner(
            status: .failing(since: .now, reason: .network("error connecting to api.github.com")),
            lastSuccess: .now.addingTimeInterval(-600)
        )
        PollStatusBanner(
            status: .rateLimited(since: .now, retryAt: .now.addingTimeInterval(120)),
            lastSuccess: .now.addingTimeInterval(-600)
        )
        PollStatusBanner(
            status: .failing(since: .now, reason: .notAuthenticated),
            lastSuccess: nil
        )
    }
    .frame(width: 380)
}
