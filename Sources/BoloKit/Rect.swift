import Darwin

// MARK: - Structures

public struct Pointi: Hashable, Sendable {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}

public struct Rangei: Hashable, Sendable {
    public var origin: Int32
    public var size: Int32

    public init(origin: Int32, size: Int32) {
        self.origin = origin
        self.size = size
    }
}

public struct Sizei: Hashable, Sendable {
    public var width: Int32
    public var height: Int32

    public init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }
}

public struct Recti: Hashable, Sendable {
    public var origin: Pointi
    public var size: Sizei

    public init(origin: Pointi, size: Sizei) {
        self.origin = origin
        self.size = size
    }
}

// MARK: - Pointi Functions

public func makepoint(_ x: Int32, _ y: Int32) -> Pointi {
    return Pointi(x: x, y: y)
}

public func isequalpoint(_ p1: Pointi, _ p2: Pointi) -> Int32 {
    return (p1.x == p2.x && p1.y == p2.y) ? 1 : 0
}

// MARK: - Rangei Functions

public func makerange(_ origin: Int32, _ size: UInt32) -> Rangei {
    return Rangei(origin: origin, size: Int32(bitPattern: size))
}

public func intersectsrange(_ r1: Rangei, _ r2: Rangei) -> Int32 {
    if r1.origin < r2.origin {
        let r1End = Int64(r1.origin) + Int64(UInt32(bitPattern: r1.size))
        if r1End > Int64(r2.origin) {
            return 1
        }
    } else {
        let r2End = Int64(r2.origin) + Int64(UInt32(bitPattern: r2.size))
        if r2End > Int64(r1.origin) {
            return 1
        }
    }
    return 0
}

public func containsrange(_ r1: Rangei, _ r2: Rangei) -> Int32 {
    let r1End = Int64(r1.origin) + Int64(UInt32(bitPattern: r1.size))
    let r2End = Int64(r2.origin) + Int64(UInt32(bitPattern: r2.size))
    return (r1.origin <= r2.origin && r1End >= r2End) ? 1 : 0
}

public func inrange(_ r: Rangei, _ x: Int32) -> Int32 {
    let end = r.origin &+ r.size
    return (r.origin <= x && end < x) ? 1 : 0
}

// MARK: - Sizei Functions

public func makesize(_ w: UInt32, _ h: UInt32) -> Sizei {
    return Sizei(width: Int32(bitPattern: w), height: Int32(bitPattern: h))
}

public func equalsizes(_ s1: Sizei, _ s2: Sizei) -> Int32 {
    return (s1.width == s2.width && s1.height == s2.height) ? 1 : 0
}

// MARK: - Recti Functions

public func makerect(_ x: Int32, _ y: Int32, _ w: UInt32, _ h: UInt32) -> Recti {
    return Recti(origin: Pointi(x: x, y: y), size: Sizei(width: Int32(bitPattern: w), height: Int32(bitPattern: h)))
}

public func heightrect(_ r: Recti) -> UInt32 {
    return UInt32(bitPattern: r.size.height)
}

public func widthrect(_ r: Recti) -> UInt32 {
    return UInt32(bitPattern: r.size.width)
}

public func maxxrect(_ r: Recti) -> Int32 {
    return r.origin.x &+ r.size.width &- 1
}

public func maxyrect(_ r: Recti) -> Int32 {
    return r.origin.y &+ r.size.height &- 1
}

public func midxrect(_ r: Recti) -> Int32 {
    return r.origin.x &+ (r.size.width / 2)
}

public func midyrect(_ r: Recti) -> Int32 {
    return r.origin.y &+ (r.size.height / 2)
}

public func minxrect(_ r: Recti) -> Int32 {
    return r.origin.x
}

public func minyrect(_ r: Recti) -> Int32 {
    return r.origin.y
}

public func offsetrect(_ r: Recti, _ dx: Int32, _ dy: Int32) -> Recti {
    return Recti(origin: Pointi(x: r.origin.x &+ dx, y: r.origin.y &+ dy), size: r.size)
}

public func ispointinrect(_ r: Recti, _ p: Pointi) -> Int32 {
    return (minxrect(r) <= p.x && minyrect(r) <= p.y && maxxrect(r) >= p.x && maxyrect(r) >= p.y) ? 1 : 0
}

public func unionrect(_ r1: Recti, _ r2: Recti) -> Recti {
    let ox = r1.origin.x < r2.origin.x ? r1.origin.x : r2.origin.x
    let oy = r1.origin.y < r2.origin.y ? r1.origin.y : r2.origin.y
    
    let r1MaxX = Int64(r1.origin.x) + Int64(UInt32(bitPattern: r1.size.width))
    let r2MaxX = Int64(r2.origin.x) + Int64(UInt32(bitPattern: r2.size.width))
    let maxX = r1MaxX > r2MaxX ? r1MaxX : r2MaxX
    
    let r1MaxY = Int64(r1.origin.y) + Int64(UInt32(bitPattern: r1.size.height))
    let r2MaxY = Int64(r2.origin.y) + Int64(UInt32(bitPattern: r2.size.height))
    let maxY = r1MaxY > r2MaxY ? r1MaxY : r2MaxY
    
    let w = UInt32(bitPattern: Int32(truncatingIfNeeded: maxX - Int64(ox)))
    let h = UInt32(bitPattern: Int32(truncatingIfNeeded: maxY - Int64(oy)))
    
    return makerect(ox, oy, w, h)
}

public func containsrect(_ r1: Recti, _ r2: Recti) -> Int32 {
    let c1 = containsrange(makerange(r1.origin.x, UInt32(bitPattern: r1.size.width)), makerange(r2.origin.x, UInt32(bitPattern: r2.size.width)))
    let c2 = containsrange(makerange(r1.origin.y, UInt32(bitPattern: r1.size.height)), makerange(r2.origin.y, UInt32(bitPattern: r2.size.height)))
    return (c1 != 0 && c2 != 0) ? 1 : 0
}

public func isequalrect(_ r1: Recti, _ r2: Recti) -> Int32 {
    return (r1.origin.x == r2.origin.x && r1.origin.y == r2.origin.y && r1.size.width == r2.size.width && r1.size.height == r2.size.height) ? 1 : 0
}

public func isemptyrect(_ r: Recti) -> Int32 {
    return (r.size.width <= 0 || r.size.height <= 0) ? 1 : 0
}

public func insetrect(_ r: Recti, _ dx: Int32, _ dy: Int32) -> Recti {
    let w = UInt32(bitPattern: r.size.width &- (dx &* 2))
    let h = UInt32(bitPattern: r.size.height &- (dy &* 2))
    return makerect(r.origin.x &+ dx, r.origin.y &+ dy, w, h)
}

public func intersectionrect(_ r1: Recti, _ r2: Recti) -> Recti {
    let ox = r1.origin.x > r2.origin.x ? r1.origin.x : r2.origin.x
    let oy = r1.origin.y > r2.origin.y ? r1.origin.y : r2.origin.y
    
    let r1MaxX = Int64(r1.origin.x) + Int64(UInt32(bitPattern: r1.size.width))
    let r2MaxX = Int64(r2.origin.x) + Int64(UInt32(bitPattern: r2.size.width))
    let minX = r1MaxX < r2MaxX ? r1MaxX : r2MaxX
    
    let r1MaxY = Int64(r1.origin.y) + Int64(UInt32(bitPattern: r1.size.height))
    let r2MaxY = Int64(r2.origin.y) + Int64(UInt32(bitPattern: r2.size.height))
    let minY = r1MaxY < r2MaxY ? r1MaxY : r2MaxY
    
    let w = UInt32(bitPattern: Int32(truncatingIfNeeded: minX - Int64(ox)))
    let h = UInt32(bitPattern: Int32(truncatingIfNeeded: minY - Int64(oy)))
    
    return makerect(ox, oy, w, h)
}

public func intersectsrect(_ r1: Recti, _ r2: Recti) -> Int32 {
    let i1 = intersectsrange(makerange(r1.origin.x, UInt32(bitPattern: r1.size.width)), makerange(r2.origin.x, UInt32(bitPattern: r2.size.width)))
    let i2 = intersectsrange(makerange(r1.origin.y, UInt32(bitPattern: r1.size.height)), makerange(r2.origin.y, UInt32(bitPattern: r2.size.height)))
    return (i1 != 0 && i2 != 0) ? 1 : 0
}

public func splitrect(_ r: Recti, _ x: Int32, _ y: Int32, _ rects: UnsafeMutablePointer<Recti>) {
    rects[0] = makerect(r.origin.x, r.origin.y, UInt32(bitPattern: x - r.origin.x), UInt32(bitPattern: y - r.origin.y))
    rects[1] = makerect(x, r.origin.y, UInt32(bitPattern: (r.origin.x + r.size.width) - x), UInt32(bitPattern: y - r.origin.y))
    rects[2] = makerect(r.origin.x, y, UInt32(bitPattern: x - r.origin.x), UInt32(bitPattern: (r.origin.y + r.size.height) - y))
    rects[3] = makerect(x, y, UInt32(bitPattern: (r.origin.x + r.size.width) - x), UInt32(bitPattern: (r.origin.y + r.size.height) - y))
}

public func subtractrect(_ r1: Recti, _ r2: Recti, _ rects: UnsafeMutablePointer<Recti>) {
    let minx = r2.origin.x
    let miny = r2.origin.y
    let maxx = r2.origin.x &+ r2.size.width
    let maxy = r2.origin.y &+ r2.size.height

    let lxly = ispointinrect(r1, makepoint(minx - 1, miny - 1))
    let lxhy = ispointinrect(r1, makepoint(minx - 1, maxy))
    let hxly = ispointinrect(r1, makepoint(maxx, miny - 1))
    let hxhy = ispointinrect(r1, makepoint(maxx, maxy))

    // Clear buffer with empty rects first to match C behavior
    rects[0] = makerect(0, 0, 0, 0)
    rects[1] = makerect(0, 0, 0, 0)
    rects[2] = makerect(0, 0, 0, 0)
    rects[3] = makerect(0, 0, 0, 0)

    if lxly != 0 && lxhy == 0 && hxly == 0 && hxhy == 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(r1.origin.x, miny, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
    }
    else if lxly == 0 && lxhy != 0 && hxly == 0 && hxhy == 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: r1.size.height))
        rects[1] = makerect(minx, maxy, UInt32(bitPattern: (r1.origin.x + r1.size.width) - minx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
    }
    else if lxly == 0 && lxhy == 0 && hxly != 0 && hxhy == 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(maxx, miny, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
    }
    else if lxly == 0 && lxhy == 0 && hxly == 0 && hxhy != 0 {
        rects[0] = makerect(maxx, r1.origin.y, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: r1.size.height))
        rects[1] = makerect(r1.origin.x, maxy, UInt32(bitPattern: maxx - r1.origin.x), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
    }
    else if lxly != 0 && lxhy == 0 && hxly != 0 && hxhy == 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(r1.origin.x, miny, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
        rects[2] = makerect(maxx, miny, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
    }
    else if lxly == 0 && lxhy == 0 && hxly != 0 && hxhy != 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(maxx, miny, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
        rects[2] = makerect(r1.origin.x, maxy, UInt32(bitPattern: maxx - r1.origin.x), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
    }
    else if lxly == 0 && lxhy != 0 && hxly == 0 && hxhy != 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: r1.size.height))
        rects[1] = makerect(maxx, r1.origin.y, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: r1.size.height))
        rects[2] = makerect(minx, maxy, UInt32(bitPattern: maxx - minx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
    }
    else if lxly != 0 && lxhy != 0 && hxly == 0 && hxhy == 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(r1.origin.x, miny, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
        rects[2] = makerect(minx, maxy, UInt32(bitPattern: (r1.origin.x + r1.size.width) - minx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
    }
    else if lxly != 0 && lxhy != 0 && hxly != 0 && hxhy != 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: maxx - r1.origin.x), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(r1.origin.x, miny, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: (r1.origin.y + r1.size.height) - miny))
        rects[2] = makerect(minx, maxy, UInt32(bitPattern: (r1.origin.x + r1.size.width) - minx), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
        rects[3] = makerect(maxx, r1.origin.y, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: maxy - r1.origin.y))
    }
    else if lxly == 0 && lxhy == 0 && hxly == 0 && hxhy == 0 {
        rects[0] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: miny - r1.origin.y))
        rects[1] = makerect(r1.origin.x, r1.origin.y, UInt32(bitPattern: minx - r1.origin.x), UInt32(bitPattern: r1.size.height))
        rects[2] = makerect(r1.origin.x, maxy, UInt32(bitPattern: r1.size.width), UInt32(bitPattern: (r1.origin.y + r1.size.height) - maxy))
        rects[3] = makerect(maxx, r1.origin.y, UInt32(bitPattern: (r1.origin.x + r1.size.width) - maxx), UInt32(bitPattern: r1.size.height))
    }
}
