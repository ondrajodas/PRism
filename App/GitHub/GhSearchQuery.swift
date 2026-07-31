import Foundation

/// Převod search dotazu na argumenty `gh search prs`.
///
/// `gh` bere **každý argument jako jeden výraz** a hodnotu s mezerou si sám uzávorkuje.
/// Celý dotaz v jednom argumentu proto skončí `Invalid search query`
/// (`review-requested:"@me is:open"`), zatímco naslepo rozdělený dotaz nespadne — jen
/// tiše hledá něco jiného: z `label:"help wanted"` se stane `label:help` plus fulltextové
/// `wanted`, což vrací úplně jiné PR.
enum GhSearchQuery {
    static func arguments(from query: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var insideQuotes = false

        for character in query {
            if character == "\"" {
                // Uvozovky drží frázi pohromadě, ale do argumentu nepatří — jinak by je
                // gh uzávorkoval podruhé.
                insideQuotes.toggle()
            } else if character.isWhitespace, !insideQuotes {
                appendIfNotEmpty(current, to: &arguments)
                current = ""
            } else {
                current.append(character)
            }
        }

        // Neuzavřená uvozovka se dobere do konce dotazu. Odmítat ji by znamenalo přidat
        // chybový stav do konfigurace kvůli překlepu, který gh stejně jen zúží.
        appendIfNotEmpty(current, to: &arguments)
        return arguments
    }

    private static func appendIfNotEmpty(_ argument: String, to arguments: inout [String]) {
        guard !argument.isEmpty else { return }
        arguments.append(argument)
    }
}
