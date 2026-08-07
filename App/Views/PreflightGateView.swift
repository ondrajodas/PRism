import AppKit
import SwiftUI

/// Blokující obrazovka, když prostředí není v pořádku.
///
/// Vypíše **všechny** nástroje naráz — nalezené s cestou, chybějící s důvodem a příkazem
/// k instalaci. Tři chybějící binárky se tak vyřeší jedním průchodem, ne třemi spuštěními
/// aplikace.
struct PreflightGateView: View {
    let report: PreflightReport
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    ToolStatusRow(
                        tool: tool,
                        state: report.toolStates[tool] ?? .missing,
                        authState: tool == .gh ? report.ghAuth : nil
                    )
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Zkusit znovu", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 540, minHeight: 420, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRism nemůže začít")
                .font(.title2.bold())
            Text(
                """
                Aplikace potřebuje tyhle nástroje. Hledá je absolutní cestou — spuštěná \
                z Finderu nedědí PATH ze shellu.
                """
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Jeden řádek obrazovky: stav jednoho nástroje.
private struct ToolStatusRow: View {
    let tool: Tool
    let state: ToolState
    /// Jen u `gh` — u ostatních `nil`.
    let authState: GhAuthState?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: isSatisfied ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isSatisfied ? Color.green : Color.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 5) {
                Text(tool.executableName)
                    .font(.headline)
                detail
            }
        }
    }

    private var isSatisfied: Bool {
        guard state.url != nil else { return false }
        switch authState {
        case .loggedOut, .checkFailed: return false
        case .loggedIn, .none: return true
        }
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .missing:
            Text(tool.purpose)
                .foregroundStyle(.secondary)
            CommandToCopy(tool.installHint)
        case .found(let url, let source):
            FoundPath(url: url, source: source)
            authDetail
        }
    }

    @ViewBuilder private var authDetail: some View {
        switch authState {
        case .loggedOut:
            Text("Není přihlášený.")
                .foregroundStyle(.secondary)
            CommandToCopy("gh auth login")
        case .checkFailed(let detail):
            Text("Stav přihlášení se nepodařilo zjistit.")
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .loggedIn, .none:
            EmptyView()
        }
    }
}

/// Nalezená cesta. U nálezu přes login shell se to řekne — je to vodítko, když aplikace
/// najde jinou verzi než terminál.
private struct FoundPath: View {
    let url: URL
    let source: LocationSource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.path(percentEncoded: false))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if source == .loginShellPath {
                Text("Nalezeno přes PATH login shellu.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Příkaz k opsání do terminálu. Kopírovat je tady praktičtější než přepisovat ručně.
private struct CommandToCopy: View {
    private let command: String
    @State private var didCopy = false

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(didCopy ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Kopírovat příkaz")
            .accessibilityLabel("Kopírovat příkaz")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func copy() {
        Clipboard.copy(command)
        didCopy = true
    }
}

#Preview("Chybějící binárka") {
    PreflightGateView(
        report: PreflightReport(
            toolStates: [
                .gh: .found(URL(filePath: "/opt/homebrew/bin/gh"), source: .knownLocation),
                .git: .found(URL(filePath: "/usr/bin/git"), source: .knownLocation),
                .claude: .missing,
            ],
            ghAuth: .loggedIn
        ),
        onRetry: {}
    )
}

#Preview("gh nepřihlášený") {
    PreflightGateView(
        report: PreflightReport(
            toolStates: [
                .gh: .found(URL(filePath: "/opt/homebrew/bin/gh"), source: .knownLocation),
                .git: .found(URL(filePath: "/usr/bin/git"), source: .knownLocation),
                .claude: .found(
                    URL(filePath: "/Users/ondra/.local/bin/claude"),
                    source: .loginShellPath
                ),
            ],
            ghAuth: .loggedOut
        ),
        onRetry: {}
    )
}
