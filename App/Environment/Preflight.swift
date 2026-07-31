import Foundation

/// Co brání aplikaci v tom, aby začala.
enum PreflightProblem: Sendable, Equatable {
    case binaryMissing(Tool)
    case ghLoggedOut
    case ghAuthCheckFailed(String)
}

/// Co preflight zjistil o prostředí.
///
/// Jediná pravda — `problems` i `toolPaths` se z něj jen počítají, žádné I/O v nich není.
/// Díky tomu se rozhodnutí „co blokuje start" testuje bez mockování a UI nemusí skládat
/// vlastní `if`.
struct PreflightReport: Sendable, Equatable {
    let toolStates: [Tool: ToolState]
    /// `nil` když se `gh` nenašlo — pak není co kontrolovat.
    let ghAuth: GhAuthState?

    /// Problémy v pevném pořadí podle `Tool.allCases`, aby se gate obrazovka mezi pokusy
    /// nepřeskládala.
    var problems: [PreflightProblem] {
        var problems = Tool.allCases
            .filter { toolStates[$0] == .missing }
            .map { PreflightProblem.binaryMissing($0) }

        switch ghAuth {
        case .loggedOut:
            problems.append(.ghLoggedOut)
        case .checkFailed(let detail):
            problems.append(.ghAuthCheckFailed(detail))
        case .loggedIn, .none:
            break
        }
        return problems
    }

    /// Cesty k binárkám — ale jen když startu nic nebrání.
    var toolPaths: ToolPaths? {
        guard problems.isEmpty else { return nil }
        return ToolPaths(found: toolStates.compactMapValues(\.url))
    }
}

/// Kontroly prostředí, které musí projít, než aplikace může začít.
struct Preflight: Sendable {
    private let locator: BinaryLocator
    private let authCheck: GhAuthCheck

    init(locator: BinaryLocator, authCheck: GhAuthCheck) {
        self.locator = locator
        self.authCheck = authCheck
    }

    /// Sestavení proti skutečnému systému.
    static func live() -> Preflight {
        let runner = SubprocessRunner()
        return Preflight(
            locator: BinaryLocator(
                probe: FileSystemExecutableProbe(),
                shellPath: LoginShellPathReader(runner: runner)
            ),
            authCheck: GhAuthCheck(runner: runner)
        )
    }

    func run() async -> PreflightReport {
        let toolStates = await locator.locate()

        guard let gh = toolStates[.gh]?.url else {
            return PreflightReport(toolStates: toolStates, ghAuth: nil)
        }
        return PreflightReport(toolStates: toolStates, ghAuth: await authCheck.check(gh: gh))
    }
}
