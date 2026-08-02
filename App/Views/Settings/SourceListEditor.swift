import SwiftUI

/// Editor zdrojů — pojmenovaných search dotazů, ze kterých se skládá seznam PR.
struct SourceListEditor: View {
    @Binding var sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sources.indices, id: \.self) { index in
                row(at: index)
            }
            // Nový zdroj začíná od kanonického dotazu, ne od `is:open`: ten by se ptal na
            // **všechna** otevřená PR na GitHubu a ukládá se hned, takže by se na to
            // aplikace zeptala dřív, než se stihne dopsat.
            Button("Přidat zdroj", systemImage: "plus.circle") {
                sources.append(Source(name: "Nový zdroj", query: Source.reviewRequested.query))
            }
            .controlSize(.small)
        }
    }

    private func row(at index: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                // `prompt:` ze stejného důvodu jako u `StringListEditor` — první argument
                // by se ve `Form`u stal popiskem vlevo, ne nápovědou v poli.
                TextField("", text: binding(at: index, \.name), prompt: Text("Název"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                TextField(
                    "",
                    text: binding(at: index, \.query),
                    prompt: Text(verbatim: "review-requested:@me is:open")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
            Button {
                sources.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Odebrat zdroj")
            .padding(.top, 3)
        }
    }

    /// Stejná pojistka jako u `StringListEditor`: index je identita řádku, takže mezi
    /// odebráním a překreslením se sahá na prvek, který v poli už není.
    private func binding(at index: Int, _ field: WritableKeyPath<Source, String>) -> Binding<String> {
        Binding(
            get: { index < sources.count ? sources[index][keyPath: field] : "" },
            set: { newValue in
                guard index < sources.count else { return }
                sources[index][keyPath: field] = newValue
            }
        )
    }
}
