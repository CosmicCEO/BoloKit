import Testing
import BoloKit
import CXBolo
import Foundation

@Suite struct VectorDifferentialTests {

    // MARK: - Constants & Conversions
    
    @Test func testConstants() {
        #expect(CXBolo.kPif == BoloKit.kPif)
        #expect(CXBolo.k2Pif == BoloKit.k2Pif)
    }

    @Test func testConversions() {
        let values: [Float] = [-100.5, -1.0, -0.0, 0.0, 1.0, 100.5]
        for v in values {
            // ftoi16
            let c_ftoi16 = CXBolo.ftoi16(v)
            let s_ftoi16 = BoloKit.ftoi16(v)
            #expect(c_ftoi16 == s_ftoi16)
            
            // ftou16
            let c_ftou16 = CXBolo.ftou16(v)
            let s_ftou16 = BoloKit.ftou16(v)
            #expect(c_ftou16 == s_ftou16)
        }
        
        let u16Values: [UInt16] = [0, 1, 255, 256, 32767, 32768, 65535]
        for v in u16Values {
            let c_u16tof = CXBolo.u16tof(v)
            let s_u16tof = BoloKit.u16tof(v)
            #expect(c_u16tof == s_u16tof)
        }
        
        let i16Values: [Int16] = [-32768, -100, -1, 0, 1, 100, 32767]
        for v in i16Values {
            let c_i16tof = CXBolo.i16tof(v)
            let s_i16tof = BoloKit.i16tof(v)
            #expect(c_i16tof == s_i16tof)
        }
    }

    // MARK: - Helper Mapping Functions

    private func toC(_ v: BoloKit.Vec2f) -> CXBolo.Vec2f {
        return CXBolo.Vec2f(x: v.x, y: v.y)
    }

    private func toC(_ v: BoloKit.Vec2i32) -> CXBolo.Vec2i32 {
        return CXBolo.Vec2i32(x: v.x, y: v.y)
    }

    private func toC(_ v: BoloKit.Vec2i16) -> CXBolo.Vec2i16 {
        return CXBolo.Vec2i16(x: v.x, y: v.y)
    }

    private func toC(_ v: BoloKit.Vec2i8) -> CXBolo.Vec2i8 {
        return CXBolo.Vec2i8(x: v.x, y: v.y)
    }

    // MARK: - Vec2f Tests

    @Test func testVec2fOperations() {
        let fuzzedCoords: [Float] = [-100.0, -50.5, -1.0, -0.5, 0.0, 0.5, 1.0, 50.5, 100.0]
        var swiftVectors: [BoloKit.Vec2f] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                swiftVectors.append(BoloKit.Vec2f(x: x, y: y))
            }
        }

        for v1 in swiftVectors {
            let cv1 = toC(v1)

            // neg2f
            let c_neg = CXBolo.neg2f(cv1)
            let s_neg = BoloKit.neg2f(v1)
            #expect(c_neg.x == s_neg.x && c_neg.y == s_neg.y)

            // mag2f
            let c_mag = CXBolo.mag2f(cv1)
            let s_mag = BoloKit.mag2f(v1)
            if !c_mag.isNaN && !s_mag.isNaN {
                #expect(c_mag == s_mag)
            }

            // unit2f (skip zero vector to avoid NaN)
            if v1.x != 0 || v1.y != 0 {
                let c_unit = CXBolo.unit2f(cv1)
                let s_unit = BoloKit.unit2f(v1)
                #expect(c_unit.x == s_unit.x && c_unit.y == s_unit.y)
            }

            // _atan2f
            let c_atan = CXBolo._atan2f(cv1)
            let s_atan = BoloKit._atan2f(v1)
            #expect(c_atan == s_atan)

            for v2 in swiftVectors {
                let cv2 = toC(v2)

                // add2f
                let c_add = CXBolo.add2f(cv1, cv2)
                let s_add = BoloKit.add2f(v1, v2)
                #expect(c_add.x == s_add.x && c_add.y == s_add.y)

                // sub2f
                let c_sub = CXBolo.sub2f(cv1, cv2)
                let s_sub = BoloKit.sub2f(v1, v2)
                #expect(c_sub.x == s_sub.x && c_sub.y == s_sub.y)

                // dot2f
                let c_dot = CXBolo.dot2f(cv1, cv2)
                let s_dot = BoloKit.dot2f(v1, v2)
                #expect(c_dot == s_dot)

                // isequal2f
                let c_eq = CXBolo.isequal2f(cv1, cv2)
                let s_eq = BoloKit.isequal2f(v1, v2)
                #expect(c_eq == s_eq)

                // prj2f and cmp2f (skip zero projection vector to avoid NaN)
                if v1.x != 0 || v1.y != 0 {
                    let c_prj = CXBolo.prj2f(cv1, cv2)
                    let s_prj = BoloKit.prj2f(v1, v2)
                    #expect(c_prj.x == s_prj.x && c_prj.y == s_prj.y)

                    let c_cmp = CXBolo.cmp2f(cv1, cv2)
                    let s_cmp = BoloKit.cmp2f(v1, v2)
                    #expect(c_cmp == s_cmp)
                }
            }

            // mul2f and div2f with scalar
            for s in fuzzedCoords {
                let c_mul = CXBolo.mul2f(cv1, s)
                let s_mul = BoloKit.mul2f(v1, s)
                #expect(c_mul.x == s_mul.x && c_mul.y == s_mul.y)

                if s != 0 {
                    let c_div = CXBolo.div2f(cv1, s)
                    let s_div = BoloKit.div2f(v1, s)
                    #expect(c_div.x == s_div.x && c_div.y == s_div.y)
                }
            }
        }
    }

    // MARK: - Vec2i32 Tests

    @Test func testVec2i32Operations() {
        let fuzzedCoords: [Int32] = [-1000, -500, -1, 0, 1, 500, 1000]
        var swiftVectors: [BoloKit.Vec2i32] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                swiftVectors.append(BoloKit.Vec2i32(x: x, y: y))
            }
        }

        for v1 in swiftVectors {
            let cv1 = toC(v1)

            // neg2i32
            let c_neg = CXBolo.neg2i32(cv1)
            let s_neg = BoloKit.neg2i32(v1)
            #expect(c_neg.x == s_neg.x && c_neg.y == s_neg.y)

            // mag2i32
            let c_mag = CXBolo.mag2i32(cv1)
            let s_mag = BoloKit.mag2i32(v1)
            #expect(c_mag == s_mag)

            for v2 in swiftVectors {
                let cv2 = toC(v2)

                // add2i32
                let c_add = CXBolo.add2i32(cv1, cv2)
                let s_add = BoloKit.add2i32(v1, v2)
                #expect(c_add.x == s_add.x && c_add.y == s_add.y)

                // sub2i32
                let c_sub = CXBolo.sub2i32(cv1, cv2)
                let s_sub = BoloKit.sub2i32(v1, v2)
                #expect(c_sub.x == s_sub.x && c_sub.y == s_sub.y)

                // dot2i32
                let c_dot = CXBolo.dot2i32(cv1, cv2)
                let s_dot = BoloKit.dot2i32(v1, v2)
                #expect(c_dot == s_dot)

                // isequal2i32
                let c_eq = CXBolo.isequal2i32(cv1, cv2)
                let s_eq = BoloKit.isequal2i32(v1, v2)
                #expect(c_eq == s_eq)

                // prj2i32 and cmp2i32 (skip zero projection vector to avoid crash/division by zero)
                if v1.x != 0 || v1.y != 0 {
                    let c_prj = CXBolo.prj2i32(cv1, cv2)
                    let s_prj = BoloKit.prj2i32(v1, v2)
                    #expect(c_prj.x == s_prj.x && c_prj.y == s_prj.y)

                    let c_cmp = CXBolo.cmp2i32(cv1, cv2)
                    let s_cmp = BoloKit.cmp2i32(v1, v2)
                    #expect(c_cmp == s_cmp)
                }
            }

            // mul2i32 and div2i32
            for s in fuzzedCoords {
                let c_mul = CXBolo.mul2i32(cv1, s)
                let s_mul = BoloKit.mul2i32(v1, s)
                #expect(c_mul.x == s_mul.x && c_mul.y == s_mul.y)

                if s != 0 {
                    let c_div = CXBolo.div2i32(cv1, s)
                    let s_div = BoloKit.div2i32(v1, s)
                    #expect(c_div.x == s_div.x && c_div.y == s_div.y)
                }
            }
        }
    }

    // MARK: - Vec2i16 Tests

    @Test func testVec2i16Operations() {
        let fuzzedCoords: [Int16] = [-100, -50, -1, 0, 1, 50, 100]
        var swiftVectors: [BoloKit.Vec2i16] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                swiftVectors.append(BoloKit.Vec2i16(x: x, y: y))
            }
        }

        for v1 in swiftVectors {
            let cv1 = toC(v1)

            // neg2i16
            let c_neg = CXBolo.neg2i16(cv1)
            let s_neg = BoloKit.neg2i16(v1)
            #expect(c_neg.x == s_neg.x && c_neg.y == s_neg.y)

            // mag2i16
            let c_mag = CXBolo.mag2i16(cv1)
            let s_mag = BoloKit.mag2i16(v1)
            #expect(c_mag == s_mag)

            for v2 in swiftVectors {
                let cv2 = toC(v2)

                // add2i16
                let c_add = CXBolo.add2i16(cv1, cv2)
                let s_add = BoloKit.add2i16(v1, v2)
                #expect(c_add.x == s_add.x && c_add.y == s_add.y)

                // sub2i16
                let c_sub = CXBolo.sub2i16(cv1, cv2)
                let s_sub = BoloKit.sub2i16(v1, v2)
                #expect(c_sub.x == s_sub.x && c_sub.y == s_sub.y)

                // dot2i16
                let c_dot = CXBolo.dot2i16(cv1, cv2)
                let s_dot = BoloKit.dot2i16(v1, v2)
                #expect(c_dot == s_dot)

                // isequal2i16
                let c_eq = CXBolo.isequal2i16(cv1, cv2)
                let s_eq = BoloKit.isequal2i16(v1, v2)
                #expect(c_eq == s_eq)

                // prj2i16 and cmp2i16 (skip zero projection vector to avoid crash/division by zero)
                if v1.x != 0 || v1.y != 0 {
                    let c_prj = CXBolo.prj2i16(cv1, cv2)
                    let s_prj = BoloKit.prj2i16(v1, v2)
                    #expect(c_prj.x == s_prj.x && c_prj.y == s_prj.y)

                    let c_cmp = CXBolo.cmp2i16(cv1, cv2)
                    let s_cmp = BoloKit.cmp2i16(v1, v2)
                    #expect(c_cmp == s_cmp)
                }
            }

            // mul2i16 and div2i16
            for s in fuzzedCoords {
                let c_mul = CXBolo.mul2i16(cv1, s)
                let s_mul = BoloKit.mul2i16(v1, s)
                #expect(c_mul.x == s_mul.x && c_mul.y == s_mul.y)

                if s != 0 {
                    let c_div = CXBolo.div2i16(cv1, s)
                    let s_div = BoloKit.div2i16(v1, s)
                    #expect(c_div.x == s_div.x && c_div.y == s_div.y)
                }
            }
        }
    }

    // MARK: - Trig & Scaling Tests

    @Test func testTrigAndScaling() {
        for dir in UInt8(0)...UInt8(255) {
            // tan2i32
            let c_tan32 = CXBolo.tan2i32(dir)
            let s_tan32 = BoloKit.tan2i32(dir)
            #expect(c_tan32.x == s_tan32.x && c_tan32.y == s_tan32.y)

            // tan2i16
            let c_tan16 = CXBolo.tan2i16(dir)
            let s_tan16 = BoloKit.tan2i16(dir)
            #expect(c_tan16.x == s_tan16.x && c_tan16.y == s_tan16.y)

            // scale2i32
            let scale32Values: [Int32] = [1, 10, 100, 1000]
            for scale in scale32Values {
                let c_scale32 = CXBolo.scale2i32(dir, scale)
                let s_scale32 = BoloKit.scale2i32(dir, scale)
                #expect(c_scale32.x == s_scale32.x && c_scale32.y == s_scale32.y)
            }

            // scale2i16
            let scale16Values: [Int16] = [1, 10, 100, 1000]
            for scale in scale16Values {
                let c_scale16 = CXBolo.scale2i16(dir, scale)
                let s_scale16 = BoloKit.scale2i16(dir, scale)
                #expect(c_scale16.x == s_scale16.x && c_scale16.y == s_scale16.y)
            }
        }
    }

    // MARK: - Cast & Type Tests

    @Test func testCasts() {
        let values32: [Int32] = [0, 100, -100, 32767, -32768, 65535, -65536, Int32.max, Int32.min]
        for x in values32 {
            for y in values32 {
                let v = BoloKit.Vec2i32(x: x, y: y)
                let cv = toC(v)

                let c_cast = CXBolo.c2i32to2i16(cv)
                let s_cast = BoloKit.c2i32to2i16(v)
                #expect(c_cast.x == s_cast.x && c_cast.y == s_cast.y)
            }
        }

        let values16: [Int16] = [0, 100, -100, 127, -128, 255, -256, Int16.max, Int16.min]
        for x in values16 {
            for y in values16 {
                let v = BoloKit.Vec2i16(x: x, y: y)
                let cv = toC(v)

                let c_cast = CXBolo.c2i16to2i8(cv)
                let s_cast = BoloKit.c2i16to2i8(v)
                #expect(c_cast.x == s_cast.x && c_cast.y == s_cast.y)
            }
        }
    }

    @Test func testVec2i8() {
        let values8: [Int8] = [-128, -50, 0, 50, 127]
        for x1 in values8 {
            for y1 in values8 {
                let v1 = BoloKit.Vec2i8(x: x1, y: y1)
                let cv1 = toC(v1)

                // make2i8
                let c_make = CXBolo.make2i8(x1, y1)
                #expect(c_make.x == v1.x && c_make.y == v1.y)

                for x2 in values8 {
                    for y2 in values8 {
                        let v2 = BoloKit.Vec2i8(x: x2, y: y2)
                        let cv2 = toC(v2)

                        let c_eq = CXBolo.isequal2i8(cv1, cv2)
                        let s_eq = BoloKit.isequal2i8(v1, v2)
                        #expect(c_eq == s_eq)
                    }
                }
            }
        }
    }

    // MARK: - Wave 1 Helper Mapping Functions

    private func toC(_ p: BoloKit.Pointi) -> CXBolo.Pointi {
        return CXBolo.Pointi(x: p.x, y: p.y)
    }
    private func toSwift(_ p: CXBolo.Pointi) -> BoloKit.Pointi {
        return BoloKit.Pointi(x: p.x, y: p.y)
    }
    private func toC(_ r: BoloKit.Rangei) -> CXBolo.Rangei {
        return CXBolo.Rangei(origin: r.origin, size: r.size)
    }
    private func toSwift(_ r: CXBolo.Rangei) -> BoloKit.Rangei {
        return BoloKit.Rangei(origin: r.origin, size: r.size)
    }
    private func toC(_ s: BoloKit.Sizei) -> CXBolo.Sizei {
        return CXBolo.Sizei(width: s.width, height: s.height)
    }
    private func toSwift(_ s: CXBolo.Sizei) -> BoloKit.Sizei {
        return BoloKit.Sizei(width: s.width, height: s.height)
    }
    private func toC(_ r: BoloKit.Recti) -> CXBolo.Recti {
        return CXBolo.Recti(origin: toC(r.origin), size: toC(r.size))
    }
    private func toSwift(_ r: CXBolo.Recti) -> BoloKit.Recti {
        return BoloKit.Recti(origin: toSwift(r.origin), size: toSwift(r.size))
    }

    // MARK: - Wave 1 Rect Differential Tests

    @Test func testRectOperations() {
        let fuzzedCoords: [Int32] = [-100, -50, 0, 50, 100]
        let fuzzedSizes: [UInt32] = [0, 10, 50, 100]

        // 1. Pointi
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                let s_p = BoloKit.makepoint(x, y)
                let c_p = CXBolo.makepoint(x, y)
                #expect(s_p.x == c_p.x && s_p.y == c_p.y)
            }
        }

        // 2. Rangei
        for x in fuzzedCoords {
            for size in fuzzedSizes {
                let s_r1 = BoloKit.makerange(x, size)
                let c_r1 = CXBolo.makerange(x, size)
                #expect(s_r1.origin == c_r1.origin && s_r1.size == c_r1.size)
                
                for y in fuzzedCoords {
                    for size2 in fuzzedSizes {
                        let s_r2 = BoloKit.makerange(y, size2)
                        let c_r2 = CXBolo.makerange(y, size2)
                        
                        // intersectsrange
                        #expect(BoloKit.intersectsrange(s_r1, s_r2) == CXBolo.intersectsrange(c_r1, c_r2))
                        // containsrange
                        #expect(BoloKit.containsrange(s_r1, s_r2) == CXBolo.containsrange(c_r1, c_r2))
                    }
                }
                
                // inrange
                for val in fuzzedCoords {
                    #expect(BoloKit.inrange(s_r1, val) == CXBolo.inrange(c_r1, val))
                }
            }
        }

        // 3. Sizei & Recti
        var swiftRects: [BoloKit.Recti] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                for w in fuzzedSizes {
                    for h in fuzzedSizes {
                        let s_r = BoloKit.makerect(x, y, w, h)
                        let c_r = CXBolo.makerect(x, y, w, h)
                        
                        #expect(s_r.origin.x == c_r.origin.x && s_r.origin.y == c_r.origin.y)
                        #expect(s_r.size.width == c_r.size.width && s_r.size.height == c_r.size.height)
                        
                        #expect(BoloKit.heightrect(s_r) == CXBolo.heightrect(c_r))
                        #expect(BoloKit.widthrect(s_r) == CXBolo.widthrect(c_r))
                        #expect(BoloKit.maxxrect(s_r) == CXBolo.maxxrect(c_r))
                        #expect(BoloKit.maxyrect(s_r) == CXBolo.maxyrect(c_r))
                        #expect(BoloKit.midxrect(s_r) == CXBolo.midxrect(c_r))
                        #expect(BoloKit.midyrect(s_r) == CXBolo.midyrect(c_r))
                        #expect(BoloKit.minxrect(s_r) == CXBolo.minxrect(c_r))
                        #expect(BoloKit.minyrect(s_r) == CXBolo.minyrect(c_r))
                        #expect(BoloKit.isemptyrect(s_r) == CXBolo.isemptyrect(c_r))
                        
                        swiftRects.append(s_r)
                    }
                }
            }
        }

        // We cap the combinations checking to avoid excessively long running tests
        let limitedRects = Array(swiftRects.prefix(35))
        for r1 in limitedRects {
            let cr1 = toC(r1)
            
            // offsetrect
            let s_offset = BoloKit.offsetrect(r1, 10, -10)
            let c_offset = CXBolo.offsetrect(cr1, 10, -10)
            #expect(s_offset.origin.x == c_offset.origin.x && s_offset.origin.y == c_offset.origin.y)
            
            // insetrect
            let s_inset = BoloKit.insetrect(r1, 5, 5)
            let c_inset = CXBolo.insetrect(cr1, 5, 5)
            #expect(s_inset.origin.x == c_inset.origin.x && s_inset.size.width == c_inset.size.width)
            
            for r2 in limitedRects {
                let cr2 = toC(r2)
                
                // containsrect
                #expect(BoloKit.containsrect(r1, r2) == CXBolo.containsrect(cr1, cr2))
                // isequalrect
                #expect(BoloKit.isequalrect(r1, r2) == CXBolo.isequalrect(cr1, cr2))
                // intersectsrect
                #expect(BoloKit.intersectsrect(r1, r2) == CXBolo.intersectsrect(cr1, cr2))
                
                // unionrect
                let s_union = BoloKit.unionrect(r1, r2)
                let c_union = CXBolo.unionrect(cr1, cr2)
                #expect(s_union.origin.x == c_union.origin.x && s_union.size.width == c_union.size.width)
                
                // intersectionrect
                let s_inter = BoloKit.intersectionrect(r1, r2)
                let c_inter = CXBolo.intersectionrect(cr1, cr2)
                #expect(s_inter.origin.x == c_inter.origin.x && s_inter.size.width == c_inter.size.width)

                // splitrect
                var s_splits = [BoloKit.Recti](repeating: BoloKit.makerect(0,0,0,0), count: 4)
                var c_splits = [CXBolo.Recti](repeating: CXBolo.makerect(0,0,0,0), count: 4)
                BoloKit.splitrect(r1, 10, 10, &s_splits)
                CXBolo.splitrect(cr1, 10, 10, &c_splits)
                for i in 0..<4 {
                    #expect(s_splits[i].origin.x == c_splits[i].origin.x && s_splits[i].size.width == c_splits[i].size.width)
                }

                // subtractrect
                var s_subs = [BoloKit.Recti](repeating: BoloKit.makerect(0,0,0,0), count: 4)
                var c_subs = [CXBolo.Recti](repeating: CXBolo.makerect(0,0,0,0), count: 4)
                BoloKit.subtractrect(r1, r2, &s_subs)
                CXBolo.subtractrect(cr1, cr2, &c_subs)
                for i in 0..<4 {
                    #expect(s_subs[i].origin.x == c_subs[i].origin.x && s_subs[i].size.width == c_subs[i].size.width)
                }
            }
        }
    }

    // MARK: - Wave 1 List Differential Tests

        @Test func testListOperations() {
        let s_head = UnsafeMutablePointer<BoloKit.ListNode>.allocate(capacity: 1)
        let c_head = UnsafeMutablePointer<CXBolo.ListNode>.allocate(capacity: 1)
        
        BoloKit.initlist(s_head)
        CXBolo.initlist(c_head)
        
        #expect(s_head.pointee.prev == nil && s_head.pointee.next == nil)
        
        let ptr1 = UnsafeMutableRawPointer(bitPattern: 111)
        let ptr2 = UnsafeMutableRawPointer(bitPattern: 222)
        let ptr3 = UnsafeMutableRawPointer(bitPattern: 333)
        
        BoloKit.addlist(s_head, ptr1)
        BoloKit.addlist(s_head, ptr2)
        BoloKit.addlist(s_head, ptr3)
        
        CXBolo.addlist(c_head, ptr1)
        CXBolo.addlist(c_head, ptr2)
        CXBolo.addlist(c_head, ptr3)
        
        var s_curr = BoloKit.nextlist(s_head)
        var c_curr = CXBolo.nextlist(c_head)
        
        while s_curr != nil && c_curr != nil {
            #expect(BoloKit.ptrlist(s_curr!) == CXBolo.ptrlist(c_curr!))
            s_curr = BoloKit.nextlist(s_curr!)
            c_curr = CXBolo.nextlist(c_curr!)
        }
        #expect(s_curr == nil && c_curr == nil)
        
        BoloKit.clearlist(s_head, { _ in })
        CXBolo.clearlist(c_head, { _ in })
        
        #expect(s_head.pointee.next == nil && c_head.pointee.next == nil)
        
        s_head.deallocate()
        c_head.deallocate()
    }

    // MARK: - Wave 1 Buf Differential Tests

    @Test func testBufOperations() {
        var s_buf = BoloKit.Buf()
        var c_buf = CXBolo.Buf()
        
        BoloKit.initbuf(&s_buf)
        CXBolo.initbuf(&c_buf)
        
        #expect(s_buf.nbytes == c_buf.nbytes)
        #expect(s_buf.size == c_buf.size)
        
        let testString = "XBolo / BoloKit 2026 Test Dynamic Buffer"
        let dataBytes = Array(testString.utf8)
        
        dataBytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            BoloKit.writebuf(&s_buf, baseAddress, rawBuffer.count)
            CXBolo.writebuf(&c_buf, baseAddress, rawBuffer.count)
        }
        
        #expect(s_buf.nbytes == c_buf.nbytes)
        #expect(s_buf.size == c_buf.size)
        
        if let s_ptr = s_buf.ptr, let c_ptr = c_buf.ptr {
            #expect(memcmp(s_ptr, c_ptr, s_buf.nbytes) == 0)
        }
        
        let s_out = UnsafeMutableRawPointer.allocate(byteCount: s_buf.nbytes, alignment: 1)
        let c_out = UnsafeMutableRawPointer.allocate(byteCount: c_buf.nbytes, alignment: 1)
        
        let count = s_buf.nbytes
        BoloKit.readbuf(&s_buf, s_out, count)
        CXBolo.readbuf(&c_buf, c_out, count)
        
        #expect(s_buf.nbytes == c_buf.nbytes)
        #expect(memcmp(s_out, c_out, count) == 0)
        
        s_out.deallocate()
        c_out.deallocate()
        
        BoloKit.freebuf(&s_buf)
        CXBolo.freebuf(&c_buf)
    }

    // MARK: - Wave 1 ErrChk Differential Tests

    @Test func testErrChkOperations() {
        #expect(BoloKit.ELAST == CXBolo.ELAST)
        #expect(BoloKit.EBADPASS == CXBolo.EBADPASS)
        
        BoloKit.errchkcleanup()
        CXBolo.errchkcleanup()
        
        let file = "rect.c"
        let function = "makerect"
        
        file.withCString { filePtr in
            function.withCString { funcPtr in
                BoloKit.pushlineinfo(filePtr, funcPtr, 123)
                CXBolo.pushlineinfo(filePtr, funcPtr, 123)
            }
        }
        
        let s_trace = BoloKit.gettrace()
        #expect(s_trace.count == 1)
        #expect(s_trace[0].file == "rect.c")
        #expect(s_trace[0].function == "makerect")
        #expect(s_trace[0].line == 123)
        
        BoloKit.errchkcleanup()
        CXBolo.errchkcleanup()
        #expect(BoloKit.gettrace().count == 0)
    }

    // MARK: - Wave 2 Terrain Differential Tests

    @Test func testTerrainEnumAndPredicate() {
        #expect(BoloKit.Terrain.sea.rawValue == CXBolo.kSeaTerrain)
        #expect(BoloKit.Terrain.boat.rawValue == CXBolo.kBoatTerrain)
        #expect(BoloKit.Terrain.wall.rawValue == CXBolo.kWallTerrain)
        #expect(BoloKit.Terrain.river.rawValue == CXBolo.kRiverTerrain)
        #expect(BoloKit.Terrain.swamp0.rawValue == CXBolo.kSwampTerrain0)
        #expect(BoloKit.Terrain.swamp3.rawValue == CXBolo.kSwampTerrain3)
        #expect(BoloKit.Terrain.crater.rawValue == CXBolo.kCraterTerrain)
        #expect(BoloKit.Terrain.road.rawValue == CXBolo.kRoadTerrain)
        #expect(BoloKit.Terrain.forest.rawValue == CXBolo.kForestTerrain)
        #expect(BoloKit.Terrain.rubble0.rawValue == CXBolo.kRubbleTerrain0)
        #expect(BoloKit.Terrain.rubble3.rawValue == CXBolo.kRubbleTerrain3)
        #expect(BoloKit.Terrain.grass0.rawValue == CXBolo.kGrassTerrain0)
        #expect(BoloKit.Terrain.grass3.rawValue == CXBolo.kGrassTerrain3)
        #expect(BoloKit.Terrain.damagedWall0.rawValue == CXBolo.kDamagedWallTerrain0)
        #expect(BoloKit.Terrain.damagedWall3.rawValue == CXBolo.kDamagedWallTerrain3)
        #expect(BoloKit.Terrain.minedSea.rawValue == CXBolo.kMinedSeaTerrain)
        #expect(BoloKit.Terrain.minedGrass.rawValue == CXBolo.kMinedGrassTerrain)

        for t in Int32(0)...Int32(50) {
            #expect(BoloKit.isWaterLikeTerrain(t) == CXBolo.isWaterLikeTerrain(t))
        }
    }

    // MARK: - Wave 2 Tile Differential Tests

    @Test func testTileEnumAndPredicates() {
        #expect(BoloKit.Tile.wall.rawValue == CXBolo.kWallTile)
        #expect(BoloKit.Tile.river.rawValue == CXBolo.kRiverTile)
        #expect(BoloKit.Tile.swamp.rawValue == CXBolo.kSwampTile)
        #expect(BoloKit.Tile.crater.rawValue == CXBolo.kCraterTile)
        #expect(BoloKit.Tile.road.rawValue == CXBolo.kRoadTile)
        #expect(BoloKit.Tile.forest.rawValue == CXBolo.kForestTile)
        #expect(BoloKit.Tile.rubble.rawValue == CXBolo.kRubbleTile)
        #expect(BoloKit.Tile.grass.rawValue == CXBolo.kGrassTile)
        #expect(BoloKit.Tile.damagedWall.rawValue == CXBolo.kDamagedWallTile)
        #expect(BoloKit.Tile.boat.rawValue == CXBolo.kBoatTile)
        #expect(BoloKit.Tile.minedSwamp.rawValue == CXBolo.kMinedSwampTile)
        #expect(BoloKit.Tile.minedCrater.rawValue == CXBolo.kMinedCraterTile)
        #expect(BoloKit.Tile.minedRoad.rawValue == CXBolo.kMinedRoadTile)
        #expect(BoloKit.Tile.minedForest.rawValue == CXBolo.kMinedForestTile)
        #expect(BoloKit.Tile.minedRubble.rawValue == CXBolo.kMinedRubbleTile)
        #expect(BoloKit.Tile.minedGrass.rawValue == CXBolo.kMinedGrassTile)
        #expect(BoloKit.Tile.sea.rawValue == CXBolo.kSeaTile)
        #expect(BoloKit.Tile.minedSea.rawValue == CXBolo.kMinedSeaTile)
        #expect(BoloKit.Tile.friendlyBase.rawValue == CXBolo.kFriendlyBaseTile)
        #expect(BoloKit.Tile.hostileBase.rawValue == CXBolo.kHostileBaseTile)
        #expect(BoloKit.Tile.neutralBase.rawValue == CXBolo.kNeutralBaseTile)
        #expect(BoloKit.Tile.friendlyPill00.rawValue == CXBolo.kFriendlyPill00Tile)
        #expect(BoloKit.Tile.friendlyPill15.rawValue == CXBolo.kFriendlyPill15Tile)
        #expect(BoloKit.Tile.hostilePill00.rawValue == CXBolo.kHostilePill00Tile)
        #expect(BoloKit.Tile.hostilePill15.rawValue == CXBolo.kHostilePill15Tile)
        #expect(BoloKit.Tile.unknown.rawValue == CXBolo.kUnknownTile)

        var grid = [Int32](repeating: 0, count: 256 * 256)
        
        let validTiles: [Int32] = BoloKit.Tile.allCases.map { $0.rawValue }
        for i in 0..<grid.count {
            grid[i] = validTiles[i % validTiles.count]
        }
        
        grid.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!
            let testCoords: [Int32] = [-1, 0, 1, 50, 100, 255, 256]
            
            for y in testCoords {
                for x in testCoords {
                    #expect(BoloKit.isForestLikeTile(ptr, x, y) == CXBolo.isForestLikeTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isCraterLikeTile(ptr, x, y) == CXBolo.isCraterLikeTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isRoadLikeTile(ptr, x, y) == CXBolo.isRoadLikeTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isWaterLikeToLandTile(ptr, x, y) == CXBolo.isWaterLikeToLandTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isWaterLikeToWaterTile(ptr, x, y) == CXBolo.isWaterLikeToWaterTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isWallLikeTile(ptr, x, y) == CXBolo.isWallLikeTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isSeaLikeTile(ptr, x, y) == CXBolo.isSeaLikeTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                    #expect(BoloKit.isMinedTile(ptr, x, y) == CXBolo.isMinedTile_flat(UnsafeMutablePointer(mutating: ptr), x, y))
                }
            }
        }
    }
}
