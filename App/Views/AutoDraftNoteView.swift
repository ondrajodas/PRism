import SwiftUI

/// Co se dá udělat s návrhem review (#520).
///
/// Jeden parametr místo dvou closures, které patří k sobě — stejný vzor jako `DraftActions`.
/// Výchozí hodnoty jsou prázdné, aby se panel dal postavit i bez storu (náhledy, testy).
struct AutoDraftActions {
    /// `Zahodit návrh` — smaže razítko i draft. Po něm zbude dnešní prázdný panel.
    var discard: () -> Void = {}
    /// `Co je sporné ↓` — přepne panel na nálezy a skočí na první sporný.
    ///
    /// `nil` = **tlačítko se nekreslí**, ne zašedle: sporné nálezy buď jsou, nebo nejsou,
    /// a zakázané tlačítko by svádělo na něj kliknout a hledat, co je rozbité (tatáž úvaha jako
    /// u `Prompt →`, #333).
    var showContested: (() -> Void)?
}

/// Pruh nad rozdělaným review: **kdo ho složil a co v něm není** (#520, návrh `.rv-autonote`).
///
/// Existuje kvůli jediné větě: *když se část nálezů převezme sama a část ne, musí být z okna
/// poznat které a proč*. Bez něj by panel po doběhnutí reviewerů vypadal jako moje práce — a
/// odeslalo by se z něj víc, než jsem četl.
///
/// **Kreslí se i nad prázdným panelem.** Návrh, ve kterém zůstaly samé sporné nálezy, žádný
/// komentář nezaloží, takže je pruh to jediné, co vysvětlí, proč v panelu nic není.
///
/// **Žádná akce odsud nic neodesílá.** `Zahodit návrh` maže lokální stav, `Co je sporné ↓` jen
/// přepíná pohled — odeslat umí pořád jedině potvrzení pod ním (tvrdá podmínka č. 1).
struct AutoDraftNoteView: View {
    /// Celá věta `Návrh připravený automatem · 21:52 · z 5 nálezů 3 převzaty, 2 sporné`.
    /// Skládá ji `Policy.autoDraftNote`, ne tenhle pruh — týmiž počty mluví i řádek v `Dění`.
    let note: String
    /// Druhá řádka: **odkud je tělo review** (#521). `nil` = pruh o těle mlčí — tělo se nepsalo,
    /// nebo je razítko z doby před #521.
    ///
    /// Skládá ji `Policy.reviewBodyNote`, ne tenhle pruh, ze stejného důvodu jako tu první: je to
    /// rozhodnutí o tom, co se smí tvrdit, ne formátování.
    ///
    /// **Vlastní řádka, ne delší první věta.** První mluví o **nálezech** (co se převzalo a co
    /// zůstalo sporné), druhá o **próze** — a splynutí by znamenalo, že se nad prázdným composerem
    /// čte jako jedna zpráva, ve které je počet nálezů i selhání session dohromady.
    var bodyNote: String?
    var actions = AutoDraftActions()

    @State private var isConfirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(verbatim: note)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "wand.and.stars")
            }
            .font(.caption)
            // **Akcent, ne barva stavu.** Pruh neříká, jak review dopadlo (to je barva nálezů),
            // ale že tu něco leží připravené — tatáž role, jakou má akcent u pilulky agenta.
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let bodyNote {
                // **Bez ikony a odsazená pod text první řádky** (velikost ikony `Label`u v `.caption`
                // je 16 bodů): druhá ikona vedle první by z pruhu udělala dvě zprávy, a to je zrovna
                // to, čemu se tady vyhýbáme — je to **jedna** zpráva o dvou vrstvách návrhu.
                Text(verbatim: bodyNote)
                    .font(.caption)
                    // Sekundární, ne akcentní: první řádka je to, co pruh **tvrdí**, tahle to
                    // doplňuje. Dvě stejně výrazné řádky se přestanou číst obě.
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                discardButton
                if let showContested = actions.showContested {
                    Button("Co je sporné ↓", action: showContested)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Přepne na nálezy a skočí na první, který si návrh nevzal")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentWeak, in: .rect(cornerRadius: 6))
    }

    /// Ptá se, **jako `Zahodit review`** — je to totéž mazání týchž dat a dvě různá potvrzení nad
    /// jednou věcí by znamenala, že jedno z nich je zbytečné. Že draft složila aplikace, na ceně
    /// omylu nic nemění: mezitím se do něj mohlo psát.
    private var discardButton: some View {
        Button("Zahodit návrh", systemImage: "trash") {
            isConfirmingDiscard = true
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help("Smaže návrh i to, co z něj v panelu leží — nálezy zůstanou")
        .confirmationDialog(
            "Zahodit návrh review?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Zahodit", role: .destructive) { actions.discard() }
            Button("Zpět", role: .cancel) {}
        } message: {
            Text("Převzaté komentáře i značky sporných nálezů. Nálezy samotné zůstávají — panel bude prázdný jako bez návrhu.")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AutoDraftNoteView(
            note: Policy.autoDraftNote(at: "21:52", adopted: 3, contested: 2),
            bodyNote: Policy.reviewBodyNote(AutoDraftBody(samples: 7)),
            actions: AutoDraftActions(showContested: {})
        )
        AutoDraftNoteView(
            note: Policy.autoDraftNote(at: "08:04", adopted: 0, contested: 3),
            bodyNote: Policy.reviewBodyNote(AutoDraftBody(samples: 0))
        )
        AutoDraftNoteView(
            note: Policy.autoDraftNote(at: "08:04", adopted: 2, contested: 0),
            bodyNote: Policy.reviewBodyNote(
                AutoDraftBody(samples: 4, failure: .session(detail: "Tělo review nedoběhlo v limitu 3 minuty."))
            )
        )
    }
    .padding()
    .frame(width: 300)
}
