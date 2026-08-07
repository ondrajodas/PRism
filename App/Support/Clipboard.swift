import AppKit

/// Zápis do schránky. Jedno místo, protože `NSPasteboard` chce dvě volání v pořadí a zapomenout
/// `clearContents()` znamená, že se text přilepí k tomu, co ve schránce zůstalo.
///
/// Vzniklo u #157 jako **třetí** výskyt (kopírování příkazu v kontrole prostředí a `claude
/// --resume` v ose běhu byly první dva). Dva výskyty jsou náhoda, tři už je vzor.
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
