import os

/// v1.4.0 #16 — Instruments signposts. Subsystem matches the app bundle id.
/// Categories: `tick` / `render` / `net`. No gameplay effect.
public enum BoloSignposts {
    public static let subsystem = "com.cosmicceo.Bolo-2026"
    public static let tickCategory = "tick"
    public static let renderCategory = "render"
    public static let netCategory = "net"

    public static let runTickName: StaticString = "runTick"
    public static let drawName: StaticString = "draw"
    public static let clUpdateName: StaticString = "clUpdate"

    // v1.6.9 baseline benchmark: the paths #16 left untimed. Same categories.
    public static let guestTickName: StaticString = "guestTick"
    public static let udpApplyName: StaticString = "udpApply"
    public static let tcpDispatchName: StaticString = "tcpDispatch"
    public static let metalFrameName: StaticString = "metalFrame"

    public static let tick = OSSignposter(subsystem: subsystem, category: tickCategory)
    public static let render = OSSignposter(subsystem: subsystem, category: renderCategory)
    public static let net = OSSignposter(subsystem: subsystem, category: netCategory)
}
