import Foundation
import Testing

/// Zakóduje a zase dekóduje — základ testů, že model přežije cestu na disk a zpět.
///
/// Hodnota se balí do pole schválně: `RepoID` i `PRIdentifier` se kódují na holý řetězec
/// a ten by na nejvyšší úrovni byl JSON fragment. Pole je nejlevnější obal, který to obejde
/// a zároveň nic neschovává.
func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode([value])
    let decoded = try JSONDecoder().decode([T].self, from: data)
    return try #require(decoded.first)
}

/// JSON zápis hodnoty (opět zabalené v poli) — na kontrolu skutečného tvaru na disku.
func encodedJSON<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode([value]), as: UTF8.self)
}
