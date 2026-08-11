import SwiftUI

/// Tab `Kontroly` (#215) — seznam checků z GitHub Actions.
///
/// Odpovídá na druhou půlku otázky „dá se to mergnout“ — tu první (nálezy) v okně už je, takže
/// se nad zeleným review pořád muselo do prohlížeče.
///
/// **Do #215 to byl blok v `Přehledu`** (#209). Se souhrnem to tam sedělo, ale detail spadlého
/// checku (#214) přidává anotace a konec logu, a tím blok vyroste natolik, že vytlačí popis PR
/// mimo obrazovku.
///
/// V `Přehledu` po tom stěhování **nezbylo nic** — ani souhrn, který tam zadání #215 chtělo nechat.
/// Tab odpovídá na celou otázku a „je to zelené“ nese chip v hlavičce PR, takže souhrn byl třetí
/// místo o téže věci. Rozhodnuto při zkoušení, viz specifikace.
///
/// **Log se stahuje až na kliknutí a jen u toho jednoho checku** (#214) — nikdy dopředu a nikdy
/// pro všechny. Podrobnosti u `AppStore+Checks` a v `CheckDetailView`.
struct ChecksView: View {
    let checks: [PullRequestCheck]
    /// Který check je rozbalený (#214). `nil` = žádný.
    var expanded: String?
    /// Co se ví o rozbaleném checku.
    var detail: CheckDetailState?
    /// Rozbalí nebo sbalí check. `nil` = detail se nenabízí vůbec (nemáme `AppStore`, náhledy).
    var toggle: ((PullRequestCheck) -> Void)?
    var jump: ((String, Int?) -> Void)?
    var showFullLog: ((PullRequestCheck, String) -> Void)?

    /// Přeskočené se sbalí za číslo. Na skutečném PR jich bývá většina (změřeno na
    /// `keboola/platform-libraries#557`: 28 checků, 22 přeskočených) a rozepsané by utopily
    /// ten jeden, na kterém záleží.
    @State private var showsSkipped = false

    var body: some View {
        ScrollView {
            card
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Jména jobů a časy si člověk kopíruje do issue; je to několik řádků textu, ne líný
        // seznam tisíců `Text`ů jako diff.
        .textSelection(.enabled)
    }

    /// Rámeček ze návrhu (`.checks`): obrys a `chrome`, ať je vidět, kde seznam začíná a končí.
    private var card: some View {
        VStack(spacing: 0) {
            header
            ForEach(visible) { check in
                row(check)
                if expanded == check.name, let detail {
                    CheckDetailView(
                        detail: detail,
                        link: check.link,
                        jump: jump,
                        showFullLog: showFullLog.map { show in { show(check, $0) } },
                        collapse: { toggle?(check) }
                    )
                }
                if check.id != visible.last?.id || skipped > 0 {
                    Rectangle().fill(Palette.lineSoft).frame(height: 1)
                }
            }
            if skipped > 0 { skippedRow }
        }
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
    }

    /// Hlavička s poměrem (`.checks > header`). Nadpis zůstává i v tabu: pruh záložek nese jen
    /// `Kontroly`, kdežto tady má být vidět, že jsou to kontroly **na GitHubu**, ne naše review.
    private var header: some View {
        HStack(spacing: 8) {
            Text("Kontroly na GitHubu")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            Text(verbatim: ChecksText.summary(of: Policy.summary(of: checks)))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Řádek checku. **Rozbalovací jen tehdy, když má číslo jobu** (#214) — u checku bez něj
    /// (CodeQL, bors) zbývá jen odkaz ven, protože tlačítko, které skončí chybou, je horší než
    /// tlačítko, které tam není.
    @ViewBuilder private func row(_ check: PullRequestCheck) -> some View {
        if canExpand(check) {
            Button { toggle?(check) } label: { rowContent(check) }
                .buttonStyle(.plain)
                .help(expanded == check.name ? "Sbalit detail" : "Ukázat anotace a konec logu")
        } else {
            rowContent(check)
        }
    }

    private func rowContent(_ check: PullRequestCheck) -> some View {
        let isOpen = expanded == check.name
        return HStack(spacing: 9) {
            Image(systemName: ChecksText.symbol(of: check.outcome))
                .font(.system(size: 11))
                .foregroundStyle(ChecksText.color(of: check.outcome))
                .frame(width: 13)
            Text(verbatim: check.name)
                // Rozbalený nese jméno výrazněji (návrh: `.chk.open .nm` má `--ink` a 560).
                .font(.system(size: 12, weight: isOpen ? .medium : .regular))
                .foregroundStyle(isOpen ? Palette.ink : Palette.ink2)
                .lineLimit(1)
            if canExpand(check) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            Text(verbatim: ChecksText.detail(of: check))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
            // Odkaz jen u toho, co se nepovedlo — u zeleného checku není proč chodit pryč.
            if let link = check.link, check.outcome == .failed || check.outcome == .cancelled {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                }
                .help("Otevřít log na GitHubu")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Rozbalený řádek je podbarvený (návrh: `.chk.open`), ať je vidět, ke kterému checku
        // detail pod ním patří.
        .background(isOpen ? Palette.crit.opacity(0.06) : .clear)
        .contentShape(.rect)
    }

    /// Dá se u checku otevřít detail? Rozhoduje **číslo jobu**, ne `outcome`.
    ///
    /// Nabízí se u všeho, co číslo má — i u prošlého checku: `phpunit`, který prošel, ale trval
    /// dvacet minut, je taky důvod se do logu podívat.
    private func canExpand(_ check: PullRequestCheck) -> Bool {
        toggle != nil && check.jobID != nil
    }

    private var skippedRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { showsSkipped.toggle() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: showsSkipped ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink3)
                    .frame(width: 13)
                Text(verbatim: "\(skipped) přeskočeno")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Co se kreslí: bez přeskočených, dokud si o ně někdo neřekne.
    private var visible: [PullRequestCheck] {
        Policy.sorted(checks).filter { showsSkipped || $0.outcome != .skipped }
    }

    private var skipped: Int { checks.count { $0.outcome == .skipped } }
}

#Preview {
    ChecksView(checks: [
        PullRequestCheck(
            name: "phpstan (level 8)",
            outcome: .failed,
            link: URL(string: "https://github.com/cli/cli/actions/runs/1/job/2"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 134)
        ),
        PullRequestCheck(
            name: "phpunit / 8.4",
            outcome: .running,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: nil
        ),
        PullRequestCheck(
            name: "phpcs",
            outcome: .passed,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 41)
        ),
        PullRequestCheck(name: "deploy", outcome: .skipped, link: nil, startedAt: nil, completedAt: nil),
    ])
    .frame(width: 720, height: 260)
}
