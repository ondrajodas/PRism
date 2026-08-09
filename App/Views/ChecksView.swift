import SwiftUI

/// Blok `Kontroly na GitHubu` v tabu `Přehled` (#209).
///
/// Odpovídá na druhou půlku otázky „dá se to mergnout“ — tu první (nálezy) v okně už je, takže
/// se nad zeleným review pořád muselo do prohlížeče.
///
/// **Log se nestahuje.** Spadlý check nabídne odkaz; megabajty logu kvůli jednomu přečtení do
/// aplikace nepatří a čtení logu není doména review.
struct ChecksView: View {
    let checks: [PullRequestCheck]

    /// Přeskočené se sbalí za číslo. Na skutečném PR jich bývá většina (změřeno na
    /// `keboola/platform-libraries#557`: 28 checků, 22 přeskočených) a rozepsané by utopily
    /// ten jeden, na kterém záleží.
    @State private var showsSkipped = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(visible) { check in
                row(check)
                if check.id != visible.last?.id || skipped > 0 {
                    Rectangle().fill(Palette.lineSoft).frame(height: 1)
                }
            }
            if skipped > 0 { skippedRow }
        }
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Kontroly na GitHubu")
                .font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 8)
            Text(verbatim: summaryText)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .monospacedDigit()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    private func row(_ check: PullRequestCheck) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(of: check.outcome))
                .font(.system(size: 11))
                .foregroundStyle(color(of: check.outcome))
                .frame(width: 14)
            Text(verbatim: check.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: detail(of: check))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink3)
            // Odkaz jen u toho, co se nepovedlo — u zeleného checku není proč chodit pryč.
            if let link = check.link, check.outcome == .failed || check.outcome == .cancelled {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                }
                .help("Otevřít log na GitHubu")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }

    private var skippedRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { showsSkipped.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showsSkipped ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink3)
                    .frame(width: 14)
                Text(verbatim: "\(skipped) přeskočeno")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Co se kreslí: bez přeskočených, dokud si o ně někdo neřekne.
    private var visible: [PullRequestCheck] {
        Policy.sorted(checks).filter { showsSkipped || $0.outcome != .skipped }
    }

    private var skipped: Int { checks.count { $0.outcome == .skipped } }

    /// `2 prošly · 1 běží · 1 selhala` — jen to, čeho je aspoň jeden. Nula v souhrnu je slovo
    /// navíc, ze kterého nic neplyne.
    private var summaryText: String {
        let summary = Policy.summary(of: checks)
        var parts: [String] = []
        if summary.failed > 0 {
            parts.append(Plural.czech(summary.failed, one: "selhala", few: "selhaly", many: "selhalo"))
        }
        if summary.running > 0 { parts.append("\(summary.running) běží") }
        if summary.passed > 0 {
            parts.append(Plural.czech(summary.passed, one: "prošla", few: "prošly", many: "prošlo"))
        }
        if summary.skipped > 0 { parts.append("\(summary.skipped) přeskočeno") }
        return parts.joined(separator: " · ")
    }

    private func detail(of check: PullRequestCheck) -> String {
        let state = switch check.outcome {
        case .passed: "prošlo"
        case .failed: "selhalo"
        case .running: "běží"
        case .skipped: "přeskočeno"
        case .cancelled: "zrušeno"
        }
        guard let duration = check.duration else { return state }
        return "\(state) · \(RunUsageText.duration(.seconds(duration)))"
    }

    private func symbol(of outcome: PullRequestCheck.Outcome) -> String {
        switch outcome {
        case .passed: "checkmark"
        case .failed: "xmark"
        case .running: "circle.dashed"
        case .skipped: "minus"
        case .cancelled: "slash.circle"
        }
    }

    /// Tatáž škála jako všude jinde v okně: červená se musí řešit teď, fialová běží, zelená je
    /// v pořádku, šedá nic netvrdí.
    private func color(of outcome: PullRequestCheck.Outcome) -> Color {
        switch outcome {
        case .passed: .green
        case .failed, .cancelled: .red
        case .running: Palette.accent
        case .skipped: Palette.ink3
        }
    }
}
