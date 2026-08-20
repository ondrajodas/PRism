import SwiftUI

/// Věta nad kartami nálezů o tom, **proti kterému kódu platí** (#392).
///
/// Od #392 je panel i v tabu `Commity`, takže vedle nálezů může stát jiný commit, než na kterém
/// vznikly. Nálezy jsou klíčované `headSha` (tvrdá podmínka č. 5) — a tohle je ta podmínka
/// přepsaná do věty: nálezy se nekreslí proti kódu, který neexistuje, jen je u nich napsané,
/// ke kterému kódu patří.
///
/// **Dvě podoby, ne jedna se dvěma barvami.** Nad seznamem commitů nálezy platí, takže stačí klidná
/// věta (`.tl-impact` z návrhu). U rozkliknutého staršího commitu **neplatí pro to, co je na
/// obrazovce**, a to je výstraha (`.warnbox`) — s ní se karty ztlumí, o čemž rozhoduje
/// `Policy.FindingsHeadNotice.dimsFindings`.
struct FindingsHeadNoticeView: View {
    let notice: Policy.FindingsHeadNotice

    /// `--radius-sm` z návrhu.
    private static let radius = 7.0

    var body: some View {
        // **Text je z `Policy`**, ne odsud: je to jediná věta, ze které se pozná, ke kterému kódu
        // nálezy patří, a testuje se tam, kde se rozhoduje.
        if let sentence = notice.czechSentence {
            box(
                background: notice.dimsFindings ? 0.11 : 0.09,
                border: notice.dimsFindings ? 0.4 : 0.45,
                icon: notice.dimsFindings ? "exclamationmark.triangle" : nil,
                sentence: sentence
            )
            .padding(.horizontal, 11)
            .padding(.top, 4)
            .padding(.bottom, notice.dimsFindings ? 8 : 0)
        }
    }

    /// Sazba obou podob. Odstíny jsou z návrhu doslova — `.tl-impact` míchá `stale` na 9 %,
    /// `.warnbox` na 11 %, obtažení 45 % a 40 %.
    private func box(
        background: Double,
        border: Double,
        icon: String?,
        sentence: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon {
                Image(systemName: icon).foregroundStyle(Palette.stale)
            }
            Text(verbatim: sentence)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Palette.stale.opacity(background), in: .rect(cornerRadius: Self.radius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius)
                .strokeBorder(Palette.stale.opacity(border))
        }
    }
}
