import Foundation

/// Zjištění, jestli na cestě leží spustitelný soubor. Za protokolem, aby se hledání
/// binárek testovalo bez skutečného filesystému.
protocol ExecutableProbe: Sendable {
    func isExecutable(at url: URL) -> Bool
}

/// Probe nad skutečným filesystémem.
struct FileSystemExecutableProbe: ExecutableProbe {
    func isExecutable(at url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        return !isDirectory(atPath: path)
    }

    /// Složky mají spustitelný bit taky — u nich znamená „průchozí" — takže `/usr/bin`
    /// samo by prošlo jako binárka. Symlinky se naopak následovat mají: `claude` je
    /// typicky symlink z `~/.local/bin` do konkrétní verze.
    private func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }
}
