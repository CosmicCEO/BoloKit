// MARK: - Builder-need / would-kill literals
//
// C `printmessage` strings emitted from BoloKit (`BuilderTick`/`BuilderCommand`).
// `EventLogText` in BoloNet aliases these so the catalog stays one type without
// a BoloKit→BoloNet import (D165). Byte-identical to `client.c`.

public enum BuilderNeedText {
    public static let needMoreTrees = "You need more trees."
    public static let needAPill = "You need a pill."
    public static let needMoreMines = "You need more mines."
    /// Two spaces after the period, matching `client.c:6573`.
    public static let wouldKillBuilder = "Your builder cannot do that.  It would kill him."
}
