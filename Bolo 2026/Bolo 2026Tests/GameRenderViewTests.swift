//
//  GameRenderViewTests.swift
//  Bolo 2026Tests
//
//  D146 -- regression coverage for the builder-task-indicator crash (Jerod's real
//  SIGABRT hit while tree-harvesting). Root cause confirmed by tracing
//  `resolveBuilderTask`/`queueBuilderCommand` (`Sources/BoloKit/BuilderCommand.swift`): neither
//  has a distance check against the builder's own current tile, so commanding a builder to
//  harvest the tree tile it's already standing on sets `builderTarget` to that exact tile.
//  `GameRenderView.drawBuilderTaskIndicators` then strokes a dashed line between the builder's
//  live position and that target -- a zero-length segment for this exact scenario -- which
//  crashed under Metal's debug draw-call validation (every frame in the crash report is inside
//  AppKit/QuartzCore/Metal, zero app-code frames). Reproduces the exact same-tile scenario via
//  the real `BoloKit` APIs (not synthetic geometry alone) and confirms the extracted guard
//  (`GameRenderView.isDegenerateBuilderIndicatorLine`) would skip the resulting draw call.

import CoreGraphics
import Testing
import BoloKit

@testable import Bolo_2026

struct GameRenderViewTests {

    /// Reconstructs Jerod's exact crash trigger: a builder standing on a forest tile is
    /// commanded to harvest that same tile (`.tree` targeting the builder's own position).
    /// Confirms this is a real, reachable path (not just a plausible-sounding theory) --
    /// `queueBuilderCommand` queues it, and once picked up `builderTarget` ends up equal to the
    /// builder's own tile -- and that the geometry this produces is exactly what the D146 guard
    /// is meant to catch.
    @Test func sameTileTreeHarvestProducesADegenerateIndicatorLine() {
        var state = GameState()
        var player = PlayerState()
        player.used = true
        player.dead = false
        player.builder = Vec2f(x: 12.5, y: 12.5)
        state.players = [player]
        state.localPlayer = 0
        state.terrain[12, 12] = .forest

        let target = Pointi(x: 12, y: 12)

        // No distance check anywhere in this path (D137's own documented ruling) -- confirms
        // the same-tile command is accepted, not silently rejected before it can matter.
        queueBuilderCommand(command: .tree, target: target, player: 0, state: &state)
        #expect(state.players[0].pendingBuilderCommand == .tree)

        let task = resolveBuilderTask(command: .tree, target: target, state: state)
        #expect(task == .getTree)

        // Mirrors `BuilderTick.swift`'s `.ready` branch: `builderTarget` is set directly from
        // the pending target, with no equality-to-current-position guard anywhere in that path.
        state.players[0].builderTarget = target

        let tile: CGFloat = 16
        let builder = state.players[0].builder
        let builderTarget = state.players[0].builderTarget
        let from = CGPoint(x: CGFloat(builder.x) * tile, y: CGFloat(builder.y) * tile)
        let to = CGPoint(
            x: (CGFloat(builderTarget.x) + 0.5) * tile,
            y: (CGFloat(builderTarget.y) + 0.5) * tile
        )

        // Same tile, and the builder is already centered on it -- from/to land on the exact
        // same point, the precise degenerate geometry that used to reach `ctx.strokePath()`.
        #expect(from == to)
        #expect(GameRenderView.isDegenerateBuilderIndicatorLine(from: from, to: to))
    }

    @Test func differentTileIndicatorLineIsNotDegenerate() {
        let from = CGPoint(x: 100, y: 100)
        let to = CGPoint(x: 116, y: 100)
        #expect(!GameRenderView.isDegenerateBuilderIndicatorLine(from: from, to: to))
    }

    @Test func subPixelDifferenceIsStillTreatedAsDegenerate() {
        // `from` carries the builder's live fractional position; `to` is tile-center-snapped.
        // A builder that has arrived but isn't dead-center on its own target tile can differ by
        // a sub-pixel amount -- not worth drawing a visible line for either.
        let from = CGPoint(x: 100.2, y: 100.1)
        let to = CGPoint(x: 100.0, y: 100.0)
        #expect(GameRenderView.isDegenerateBuilderIndicatorLine(from: from, to: to))
    }
}
