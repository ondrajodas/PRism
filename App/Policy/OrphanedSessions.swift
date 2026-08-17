import Foundation

/// Co se se zapsanou session má stát při startu aplikace (#351).
enum OrphanVerdict: Equatable {
    /// Vlastník je pryč a pod zapsaným PID pořád běží tentýž proces — zabít.
    case kill
    /// Vlastník pořád běží, takže tohle není náš úklid; značka zůstává jemu.
    case keep
    /// Není co zabít: proces už neběží, nebo jeho PID mezitím dostal někdo jiný. Značka jde pryč.
    case discard
}

extension Policy {
    /// Co udělat se zapsanou session, když aplikace startuje.
    ///
    /// `ownerNow` a `processNow` je to, co pod zapsanými PID **právě teď** běží — `nil` znamená,
    /// že tam neběží nic. Rozhoduje se v tomhle pořadí a obojí je podstatné:
    ///
    /// 1. **Živý vlastník má přednost před vším ostatním.** Session, o kterou se stará běžící
    ///    instance, není sirotek — a bez tohohle kroku by `xcodebuild test` (testovací host je
    ///    tentýž bundle, tedy tatáž cache) zabil review běžící v aplikaci, se kterou se pracuje.
    ///    Vlastník, jehož PID dostal někdo jiný, se počítá jako pryč: identita se neshoduje.
    /// 2. **Zabíjí se jen na přesnou shodu identity.** Recyklované PID i doběhlý proces vedou
    ///    na `discard`, tedy na zahozenou značku a **žádný signál**. To je to cennější tvrzení
    ///    z celého #351, protože se rozbije potichu: zabít cizí `claude` je horší než nechat
    ///    běžet sirotka.
    static func orphanVerdict(
        for session: RunningSession,
        ownerNow: ProcessIdentity?,
        processNow: ProcessIdentity?
    ) -> OrphanVerdict {
        guard ownerNow != session.owner else { return .keep }
        return processNow == session.process ? .kill : .discard
    }
}
