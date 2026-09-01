// MARK: - Minimal Game Object Stubs (Wave 5.0)
//
// Deliberately minimal — just enough for maxSpeed/maxTurnSpeed's pill/base
// overrides. Wave 5.1's GameState model supersedes these with the full
// field set (BMapPillInfo/BMapBaseInfo already carry the complete data).

public struct Pill: Sendable {
    public var x: Int
    public var y: Int
    public var armour: UInt8
    public var owner: UInt8

    public init(x: Int, y: Int, armour: UInt8, owner: UInt8) {
        self.x = x
        self.y = y
        self.armour = armour
        self.owner = owner
    }
}

public struct Base: Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}
