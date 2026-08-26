import SwiftUI

/// Jedna bublina rozhovoru v tabu `Zeptat se` (#452).
///
/// **Bublina, ne karta pod sebou.** Kdo mluví, se pozná **stranou a barvou**, ne hlavičkou se
/// jménem u každé zprávy — a bublina **není přes celou šířku** (`max-width: 78 %`), protože
/// právě to z rozhovoru dělá chat a ne log. Karty (`ConversationEntryView`) zůstávají tam, kam
/// patří: v konverzaci na PR, která odpovídá na „kdo co kdy řekl“.
struct AskBubbleView: View {
    let message: AskMessage
    /// Kam se dá skočit z odpovědi. `nil` = odkazy se nekreslí (náhledy a testy skládání).
    var jump: ((AskReference) -> Void)?

    private var isMine: Bool { message.speaker == .mine }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if !message.readFiles.isEmpty { readFiles }
            bubble
            meta
        }
        // `max-width: 78 %` z návrhu. **Podíl, ne pevné číslo**: v tabu s panelem i bez něj má
        // bublina zabrat týž díl šířky, jinak by v užším okně vypadala jako karta přes celou
        // plochu — a to je zrovna ta podoba, které se `.ask-msg` vyhýbá.
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    /// Co si session otevřela — **nad** odpovědí a tiše: je to doklad, ne obsah.
    private var readFiles: some View {
        HStack(spacing: 6) {
            AskAvatar()
            Text(verbatim: "přečetl \(message.readFiles.joined(separator: " · "))")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .lineLimit(2)
        }
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !message.text.isEmpty { prose }
            if let failure = message.failure { failureNote(failure) }
            references
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(background)
        .foregroundStyle(isMine ? Palette.surface : Palette.ink)
    }

    /// Moje otázka se sází **inline**, odpověď celým markdownem.
    ///
    /// Obojí je z návrhu: v mojí bublině kreslí `<code>` a `<b>`, v Claudově odstavce. Rozdíl je
    /// v tom, co v nich může být — otázka je jedna věta, kdežto odpověď je próza s úryvky kódu,
    /// takže potřebuje bloky (`MarkdownText`, tatáž cesta jako komentáře na PR).
    ///
    /// **Inline kód v mojí bublině se nemůže obarvit z `Palette.codeFill`** — leželo by fialové na
    /// fialovém. Bere proto průhledný podklad z barvy plochy, tedy světlý na světlém motivu
    /// a tmavý na tmavém, přesně jako text kolem; návrh to má stejně
    /// (`.ask-msg.mine .ask-bub code`).
    @ViewBuilder private var prose: some View {
        if isMine {
            Text(MarkdownInlineText.rendered(
                message.text,
                size: 12.5,
                codeBackground: Palette.surface.opacity(0.22)
            ))
            .font(.system(size: 12.5))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            MarkdownText(text: message.text, size: 12.5)
                .textSelection(.enabled)
        }
    }

    /// Kapsle bubliny. Ustupující roh **na straně mluvčího** je jediná ozdoba, kterou si to bere.
    ///
    /// Barvy jsou z návrhu jedna ku jedné: moje na plném akcentu s textem v barvě panelu (tentýž
    /// pár jako `state-chip`, změřený kontrast 6,14 ve světlém a 5,64 v tmavém), Claudova tichý
    /// podklad s okrajem.
    private var background: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: isMine ? 14 : 5,
            bottomTrailingRadius: isMine ? 5 : 14,
            topTrailingRadius: 14
        )
        .fill(isMine ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.chrome))
        .overlay {
            if !isMine {
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 14,
                    topTrailingRadius: 14
                )
                .stroke(Palette.line, lineWidth: 1)
            }
        }
    }

    /// Odkazy na místo v kódu (`.fd-to`).
    ///
    /// **Pod prózou, ne uvnitř věty** — a je to vědomá odchylka od návrhu, kde odkaz stojí přímo
    /// v textu. Udělat ho inline znamená obarvit `path:line` v `AttributedString`u, který skládá
    /// `MarkdownInlineText` — a ten sází **i popis PR a cizí komentáře**, takže by se `file:80`
    /// stalo klikatelným všude v okně, včetně míst, kde to není odkaz. Kapsle pod odstavcem drží
    /// to, kvůli čemu odkaz v návrhu je (klik skočí do `Změněných souborů` na to místo), a nemění
    /// chování nikde jinde.
    @ViewBuilder private var references: some View {
        let references = isMine ? [] : Policy.askReferences(in: message.text)
        if let jump, !references.isEmpty {
            FlowRow(spacing: 8, lineSpacing: 5) {
                ForEach(references) { reference in
                    Button { jump(reference) } label: {
                        Text(verbatim: "→ \(reference.label)")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    .buttonStyle(AccentLinkButtonStyle())
                    .help("Otevře \(reference.label) ve Změněných souborech")
                }
            }
        }
    }

    /// Proč odpověď není celá. **Text u toho zůstává** — session, která odpověděla a pak
    /// vytimeoutovala, řekla něco pravdivého a zahodit to by znamenalo zaplatit odpověď
    /// a nezobrazit ji.
    private func failureNote(_ failure: String) -> some View {
        Label {
            Text(verbatim: failure).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.stale)
    }

    /// Čas a cena drobně pod bublinou.
    ///
    /// **U mojí otázky je to `před 2 min`, u odpovědi `12 s · 0,04 $`** — a je to schválně jiný
    /// údaj, ne nedůslednost: u otázky je zajímavé, kdy jsem se ptal, u odpovědi kolik trvala
    /// a stála. Když session trvání nenahlásila (zabitý běh), zbyde i u odpovědi čas — **ne
    /// nula**, která by tvrdila, že byla okamžitá.
    ///
    /// **Cena jen tam, kde dorazila**, ze stejného důvodu.
    private var meta: some View {
        HStack(spacing: 5) {
            if let duration = message.usage?.duration {
                Text(verbatim: RunUsageText.duration(duration))
            } else {
                Text(message.at, format: .relative(presentation: .named))
            }
            if let cost = message.usage?.cost {
                Text(verbatim: "· \(RunUsageText.cost(cost))")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Palette.ink3)
    }
}

/// Kolečko s `C` u odpovědi (`.av.sm` z návrhu).
///
/// **Ne `AvatarView`**: ten kreslí iniciály **člověka** a bere je z loginu, kdežto tady žádný
/// login není — je to druhá strana rozhovoru, ne autor na GitHubu. Přetížit `AvatarView`
/// prázdným loginem by znamenalo, že se kolečko kreslí z hodnoty, kterou nikdo nezná.
struct AskAvatar: View {
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Palette.accent, Palette.accent2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(verbatim: "C")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Palette.surface)
            }
            .accessibilityHidden(true)
    }
}
