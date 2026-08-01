import Foundation

/// Složka, která po sobě uklidí, i když test spadne.
///
/// Testy checkoutu na disk **opravdu zapisují**, takže bez tohohle by po každém běhu
/// zůstávaly v `/tmp` kostry cache. Test si ji musí držet po celou dobu — úklid se
/// spustí, jakmile poslední reference zmizí.
final class TemporaryDirectory: @unchecked Sendable {
    let url: URL

    init() throws {
        url = URL(filePath: NSTemporaryDirectory()).appending(path: "prism-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
