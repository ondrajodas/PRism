import Foundation

/// Místo, na které se právě skočilo z tabulky. Bublina na něm se na chvíli zvýrazní, aby
/// bylo poznat, kam skok mířil — samotný scroll to neřekne.
struct FindingHighlight: Equatable, Sendable {
    let file: String
    let line: Int?

    func matches(_ group: FindingGroup) -> Bool {
        group.file == file && group.line == line
    }
}
