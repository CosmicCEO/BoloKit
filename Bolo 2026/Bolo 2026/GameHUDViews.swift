//
//  GameHUDViews.swift
//  Bolo 2026
//
//  D148(B): the always-visible main-window HUD Jerod's own reference screenshot of the original
//  Mac Bolo showed -- a persistent build-tool strip (left) and player/pill/base status grid +
//  shell/mine/armor gauges (right), replacing today's "open a sheet to see any of this" shape.
//  Event-log bar landed in D154 Wave 3 / D163. Win/loss overlay (`MatchEndOverlay`) is display-
//  only: it latches on the C catalog reached-strings already written to `GameSession.messages`.
//
//  Both panels poll `session.state` on a `TimelineView`, the same "poll, don't observe" shape
//  `PlayerStatusView`/`GameRenderView` already use -- `GameSession` isn't `ObservableObject` by
//  design (see that file's own header).

import BoloKit
import BoloNet
import SwiftUI

// MARK: - Shared HUD chrome (D154 Wave 2 / D158)

/// Shared beveled-panel treatment for the always-visible HUD surfaces (`BuilderToolStrip`,
/// `ResourceGaugesPanel`, `EventLogBar`, and -- applied at the call site in `GameView.swift`,
/// not here -- `PlayerStatusGrid`'s embedded-HUD usage only, per D158 ruling #2). Opaque fill is
/// non-negotiable, unchanged from D148(B)/D157's flat `Color(nsColor: .windowBackgroundColor)`
/// background: the original bug this port fixed was text rendering directly over the (frequently
/// bright/busy) map, so translucency (`.regularMaterial` or similar) risks reproducing that
/// legibility problem. The two overlaid `strokeBorder` gradients are the "beveled metal panel"
/// read the reference's `StatusBackground.png` idiom has -- original procedural drawing, no
/// pixel/palette data taken from that asset (D67/D154 posture).
struct HUDPanelChrome: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func hudPanelChrome(cornerRadius: CGFloat = 8) -> some View {
        modifier(HUDPanelChrome(cornerRadius: cornerRadius))
    }
}

/// D154 Wave 2: the pillbox tool's icon deliberately reuses Wave 1's already-approved 8-spoke
/// sunburst glyph language (`Sources/BoloGlyphsCore/GlyphSource.swift`'s `drawPill`) rather than
/// inventing a second visual vocabulary for the same object -- same 8 spokes radiating from a
/// central hub, redrawn procedurally as a SwiftUI `Shape` (vector, not `Canvas16` pixel data)
/// since this lives in a different rendering context (HUD chrome vs. in-game tile art).
struct PillSunburstShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let short = min(rect.width, rect.height)
        let innerRadius = short * 0.16
        let outerRadius = short * 0.5
        let halfWidth = short * 0.07
        for i in 0..<8 {
            let angle = CGFloat(i) * (.pi / 4)
            let dx = cos(angle)
            let dy = sin(angle)
            let perp = CGVector(dx: -dy, dy: dx)
            let start = CGPoint(x: center.x + dx * innerRadius, y: center.y + dy * innerRadius)
            let end = CGPoint(x: center.x + dx * outerRadius, y: center.y + dy * outerRadius)
            path.move(to: CGPoint(x: start.x + perp.dx * halfWidth, y: start.y + perp.dy * halfWidth))
            path.addLine(to: CGPoint(x: end.x + perp.dx * halfWidth, y: end.y + perp.dy * halfWidth))
            path.addLine(to: CGPoint(x: end.x - perp.dx * halfWidth, y: end.y - perp.dy * halfWidth))
            path.addLine(to: CGPoint(x: start.x - perp.dx * halfWidth, y: start.y - perp.dy * halfWidth))
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(
            x: center.x - innerRadius, y: center.y - innerRadius,
            width: innerRadius * 2, height: innerRadius * 2
        ))
        return path
    }
}

// MARK: - Build-tool strip

/// A vertical strip of the 5 builder-tool choices (`BuilderCommandKind`), supplementing D137's
/// silent digit-key selection with a visible, clickable equivalent. Reads/writes the same
/// `GameRenderView.selectedBuilderTool` the digit keys already drive -- no second source of
/// truth (see `GameRenderView.selectBuilderTool(_:)`'s own doc comment).
struct BuilderToolStrip: View {
    let session: GameSession
    /// Called after every tap -- see `GameView.reclaimMapFocus`'s doc comment for why this is
    /// mandatory, not optional polish.
    let reclaimFocus: () -> Void

    /// Faster than the 0.5s cadence `PlayerStatusGrid`/`ResourceGaugesPanel` poll at: this strip's
    /// whole point is visible feedback for a keyboard shortcut (digit keys 1-5) that already
    /// applies instantly, so a slower poll here would visibly lag a key press. Disclosed judgment
    /// call, not an oversight -- flagged in the D148(B) completion report.
    private static let pollInterval = 0.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.pollInterval)) { _ in
            VStack(spacing: 4) {
                ForEach(BuilderCommandKind.allCases, id: \.self) { tool in
                    let selected = session.renderView.selectedBuilderTool == tool
                    Button {
                        session.renderView.selectBuilderTool(tool)
                        reclaimFocus()
                    } label: {
                        VStack(spacing: 2) {
                            // D158 ruling #1: SF Symbols for Wave 2 (not fully bespoke `Shape`s),
                            // except the pill icon, which reuses Wave 1's own sunburst glyph
                            // language instead of a generic system symbol. D158 ruling #4:
                            // per-tool tint so the 5 tools read as visually distinct at a glance,
                            // not just by selection state.
                            if tool == .pill {
                                PillSunburstShape()
                                    .fill(Self.tint(for: tool))
                                    .frame(width: 15, height: 15)
                            } else {
                                Image(systemName: Self.iconName(for: tool))
                                    .font(.system(size: 14))
                                    .foregroundStyle(Self.tint(for: tool))
                            }
                            // Text kept as a visible fallback/accessibility label, not deleted --
                            // D154's pre-brief specifically called out not removing it.
                            Text(Self.label(for: tool))
                                .font(.system(size: 8))
                        }
                        .frame(width: 36, height: 28)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selected ? Color.accentColor : Color.secondary, lineWidth: selected ? 2 : 1)
                    )
                }
            }
            .padding(6)
            .hudPanelChrome()
        }
    }

    static func label(for tool: BuilderCommandKind) -> String {
        switch tool {
        case .tree: return "Tree"
        case .road: return "Road"
        case .wall: return "Wall"
        case .pill: return "Pill"
        case .mine: return "Mine"
        }
    }

    /// SF Symbol names, verified to resolve (`NSImage(systemSymbolName:accessibilityDescription:)`)
    /// on this project's toolchain/deployment target (macOS 27) before landing. `.pill` isn't
    /// listed here -- it uses `PillSunburstShape` instead, see the call site above.
    static func iconName(for tool: BuilderCommandKind) -> String {
        switch tool {
        case .tree: return "leaf.fill"
        case .road: return "road.lanes"
        case .wall: return "square.grid.3x3.fill"
        case .mine: return "xmark.seal.fill"
        case .pill: return "" // unused -- PillSunburstShape instead
        }
    }

    static func tint(for tool: BuilderCommandKind) -> Color {
        switch tool {
        case .tree: return .green
        case .road: return .gray
        case .wall: return .brown
        case .mine: return .red
        case .pill: return .blue
        }
    }
}

extension BuilderCommandKind: @retroactive CaseIterable {
    public static var allCases: [BuilderCommandKind] { [.tree, .road, .wall, .pill, .mine] }
}

// MARK: - Resource gauges

/// D148(B): shell/mine/armor gauges, mirroring the reference's `playerShellsStatusBar`/
/// `playerMinesStatusBar` (`GSXBoloController.m:278-279,2554-2555`) and base ammo bars
/// (`~2673-2674`). Pure display of existing `GameState` fields -- no new simulation state.
///
/// D150(1)/(2): extended with the reference's 4th player gauge (`playerTreesStatusBar`,
/// `:2557-2558`) and its separate "nearest allied base within 8 tiles" cluster
/// (`baseArmourStatusBar`/`baseShellsStatusBar`/`baseMinesStatusBar`, `:2652-2680`) -- see the
/// D150 pre-brief in `docs/AGENT_NOTES.md` for the full trace against the reference's `dist`/
/// mutual-alliance scan.
struct ResourceGaugesPanel: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let snapshot = session.state
            let localPlayer = snapshot.localPlayer
            // D148(B) (advisor-flagged): `mines`/`trees` live per-player (`state.players[localPlayer]`,
            // not `state.local`, per D105/D106), and this panel polls from first frame -- including
            // `#Preview`'s demo state and any moment `localPlayer` isn't a valid index yet. Guard
            // it the same way `GameSession` itself does everywhere else, rather than trapping like
            // D146's crash.
            let mines = snapshot.players.indices.contains(localPlayer)
                ? snapshot.players[localPlayer].mines : 0
            let trees = snapshot.players.indices.contains(localPlayer)
                ? snapshot.players[localPlayer].trees : 0
            let base = Self.nearestBase(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 8) {
                gauge(icon: "burst.fill", label: "Shells", value: Int(snapshot.local.shells), max: maxShells, color: .orange)
                gauge(icon: "xmark.seal.fill", label: "Mines", value: mines, max: maxMines, color: .purple)
                gauge(icon: "shield.fill", label: "Armor", value: Int(snapshot.local.armour), max: maxArmour, color: .green)
                gauge(icon: "leaf.fill", label: "Trees", value: trees, max: maxTrees, color: .brown)
                gauge(icon: "shield.fill", label: "Base Armor", value: Int(base?.armour ?? 0), max: maxBaseArmour, color: .green)
                gauge(icon: "burst.fill", label: "Base Shells", value: Int(base?.shells ?? 0), max: maxBaseShells, color: .orange)
                gauge(icon: "xmark.seal.fill", label: "Base Mines", value: Int(base?.mines ?? 0), max: maxBaseMines, color: .purple)
            }
            .padding(8)
            .hudPanelChrome()
        }
    }

    /// **D150(2):** ported from `GSXBoloController.m:2562-2563,2652-2669`'s `refresh:` timer --
    /// nearest base (by real Euclidean distance, `mag2f`/`vector.c:82-84` is `sqrt(dot2f(...))`,
    /// not squared) owned by a player mutually allied with the local player, within 8 tiles of
    /// the local tank. `nil` (all-zero display, `:2675-2679`) when no such base exists, or the
    /// local player index isn't valid yet (same guard style as `mines`/`trees` above).
    static func nearestBase(snapshot: GameState) -> Base? {
        guard snapshot.players.indices.contains(snapshot.localPlayer) else { return nil }
        let tank = snapshot.players[snapshot.localPlayer].tank
        var best: Base?
        var bestDist: Float = 8.0
        for candidate in snapshot.bases where candidate.owner != playerNeutral {
            guard testAlliance(snapshot.localPlayer, Int(candidate.owner), players: snapshot.players)
            else { continue }
            let d = mag2f(sub2f(tank, make2f(Float(candidate.x) + 0.5, Float(candidate.y) + 0.5)))
            if d < bestDist {
                best = candidate
                bestDist = d
            }
        }
        return best
    }

    /// D158 ruling #3: pure display addition (icon + `"\(value)/\(max)"` trailing readout) --
    /// `GameHUDMath.gaugeFraction` itself is untouched, so `GameHUDViewsTests.swift`'s existing
    /// coverage of it stays valid as-is.
    @ViewBuilder
    private func gauge(icon: String, label: String, value: Int, max: Int, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(value)/\(max)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(GameHUDMath.gaugeFraction(value: value, max: max)))
                    .tint(color)
            }
        }
    }
}

// MARK: - Event log bar (D154 Wave 3 / D163)

/// Pure logic for `EventLogBar` -- last-N window and tint kind, extracted so
/// `GameHUDViewsTests` can cover them without hosting a live window (D144).
enum EventLogBarMath {
    static let visibleLineCount = 3

    enum TintKind: Equatable {
        case everyone
        case allies
        case nearby
        case game
    }

    static func visibleMessages(_ messages: [ChatMessage], limit: Int = visibleLineCount) -> [ChatMessage] {
        guard messages.count > limit else { return messages }
        return Array(messages.suffix(limit))
    }

    static func tintKind(to: UInt8) -> TintKind {
        switch to {
        case MessageTarget.allies.rawValue: return .allies
        case MessageTarget.nearby.rawValue: return .nearby
        case EventLogText.gameTarget: return .game
        default: return .everyone
        }
    }
}

/// Always-visible bottom log of `GameSession.messages`. Display-only (D163 #9/#10): no tap
/// target, no send field. Newest at the bottom. Empty = blank chrome, not placeholder copy.
struct EventLogBar: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let visible = EventLogBarMath.visibleMessages(session.messages)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visible) { message in
                    Text(message.displayText)
                        .font(.callout)
                        .foregroundStyle(Self.tint(EventLogBarMath.tintKind(to: message.to)))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .bottomLeading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .hudPanelChrome()
            .accessibilityIdentifier("event-log-bar")
            .allowsHitTesting(false)
            .focusable(false)
        }
    }

    /// Inspired SwiftUI tints, not xbolo's `NSColor.blueColor`/`purpleColor`/`redColor` (D163 #11).
    static func tint(_ kind: EventLogBarMath.TintKind) -> Color {
        switch kind {
        case .everyone: return .primary
        case .allies: return .purple
        case .nearby: return .red
        case .game: return .cyan
        }
    }
}

// MARK: - Match end overlay

/// Display-only latch over `GameSession.messages`. Does not add a `GameState` flag:
/// `RunTick` already freezes on the reached tick, and C's `client.timelimitreached` /
/// `client.basecontrolreached` are set from the same `printmessage` strings.
enum MatchEndKind: Equatable {
    case timeLimit
    case baseControl
}

enum MatchEndMath {
    static func kind(from messages: [ChatMessage]) -> MatchEndKind? {
        var found: MatchEndKind?
        for message in messages {
            if message.text == EventLogText.timeLimitReached {
                found = .timeLimit
            } else if message.text == EventLogText.baseControlReached {
                found = .baseControl
            }
        }
        return found
    }

    static func title(_ kind: MatchEndKind) -> String {
        switch kind {
        case .timeLimit: return EventLogText.timeLimitReached
        case .baseControl: return EventLogText.baseControlReached
        }
    }
}

/// Polls `session.messages` the same way `EventLogBar` does — `GameSession` is not
/// `ObservableObject`. Hit-testing is off so scroll/quit still work while the sim is frozen.
struct MatchEndOverlay: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let kind = MatchEndMath.kind(from: session.messages) {
                MatchEndOverlayPanel(title: MatchEndMath.title(kind))
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("match-end-overlay")
    }
}

/// Host-only pause / allow-join. Polls live `HostGameEngine` state; join and
/// single-process paths render nothing (`canHostAdmin` is false).
struct HostAdminBar: View {
    let session: GameSession
    var reclaimFocus: () -> Void = {}

    var body: some View {
        if session.canHostAdmin {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: 8) {
                    Button(session.isServerPaused ? "Resume" : "Pause") {
                        session.pauseResumeServer()
                        reclaimFocus()
                    }
                    Toggle(
                        "Allow Join",
                        isOn: Binding(
                            get: { session.allowJoin },
                            set: { newValue in
                                session.setAllowJoin(newValue)
                                reclaimFocus()
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

struct MatchEndOverlayPanel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .hudPanelChrome()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityIdentifier("match-end-overlay-title")
    }
}

/// D148(B): extracted per D144/D145/D146's precedent of pulling pure logic out of view code so
/// it's directly unit-testable (`Bolo 2026Tests/GameHUDViewsTests.swift`).
enum GameHUDMath {
    /// Clamped 0...1 -- neither a negative `value` (shouldn't happen, but `mines`/`shells`/
    /// `armour` are plain `Int`/`UInt8` with no invariant enforced at this layer) nor a `value`
    /// above `max` (a real, transient possibility: `TankLocalTick.swift`'s refuel logic can leave
    /// `shells`/`armour` briefly reconciling) should ever produce an out-of-range `ProgressView`.
    static func gaugeFraction(value: Int, max: Int) -> Float {
        guard max > 0 else { return 0 }
        let fraction = Float(value) / Float(max)
        return Swift.min(1, Swift.max(0, fraction))
    }
}
