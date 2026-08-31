import Testing
import BoloCore
import CXBolo
import Foundation

@Suite struct VectorDifferentialTests {

    // MARK: - Constants & Conversions
    
    @Test func testConstants() {
        #expect(CXBolo.kPif == BoloCore.kPif)
        #expect(CXBolo.k2Pif == BoloCore.k2Pif)
    }

    @Test func testConversions() {
        let values: [Float] = [-100.5, -1.0, -0.0, 0.0, 1.0, 100.5]
        for v in values {
            // ftoi16
            let c_ftoi16 = CXBolo.ftoi16(v)
            let s_ftoi16 = BoloCore.ftoi16(v)
            #expect(c_ftoi16 == s_ftoi16)
            
            // ftou16
            let c_ftou16 = CXBolo.ftou16(v)
            let s_ftou16 = BoloCore.ftou16(v)
            #expect(c_ftou16 == s_ftou16)
        }
        
        let u16Values: [UInt16] = [0, 1, 255, 256, 32767, 32768, 65535]
        for v in u16Values {
            let c_u16tof = CXBolo.u16tof(v)
            let s_u16tof = BoloCore.u16tof(v)
            #expect(c_u16tof == s_u16tof)
        }
        
        let i16Values: [Int16] = [-32768, -100, -1, 0, 1, 100, 32767]
        for v in i16Values {
            let c_i16tof = CXBolo.i16tof(v)
            let s_i16tof = BoloCore.i16tof(v)
            #expect(c_i16tof == s_i16tof)
        }
    }

    // MARK: - Helper Mapping Functions

    private func toC(_ v: BoloCore.Vec2f) -> CXBolo.Vec2f {
        return CXBolo.Vec2f(x: v.x, y: v.y)
    }

    private func toC(_ v: BoloCore.Vec2i32) -> CXBolo.Vec2i32 {
        return CXBolo.Vec2i32(x: v.x, y: v.y)
    }

    private func toC(_ v: BoloCore.Vec2i16) -> CXBolo.Vec2i16 {
        return CXBolo.Vec2i16(x: v.x, y: v.y)
    }

    private func toC(_ v: BoloCore.Vec2i8) -> CXBolo.Vec2i8 {
        return CXBolo.Vec2i8(x: v.x, y: v.y)
    }

    // MARK: - Vec2f Tests

    @Test func testVec2fOperations() {
        let fuzzedCoords: [Float] = [-100.0, -50.5, -1.0, -0.5, 0.0, 0.5, 1.0, 50.5, 100.0]
        var swiftVectors: [BoloCore.Vec2f] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                swiftVectors.append(BoloCore.Vec2f(x: x, y: y))
            }
        }

        for v1 in swiftVectors {
            let cv1 = toC(v1)

            // neg2f
            let c_neg = CXBolo.neg2f(cv1)
            let s_neg = BoloCore.neg2f(v1)
            #expect(c_neg.x == s_neg.x && c_neg.y == s_neg.y)

            // mag2f
            let c_mag = CXBolo.mag2f(cv1)
            let s_mag = BoloCore.mag2f(v1)
            if !c_mag.isNaN && !s_mag.isNaN {
                #expect(c_mag == s_mag)
            }

            // unit2f (skip zero vector to avoid NaN)
            if v1.x != 0 || v1.y != 0 {
                let c_unit = CXBolo.unit2f(cv1)
                let s_unit = BoloCore.unit2f(v1)
                #expect(c_unit.x == s_unit.x && c_unit.y == s_unit.y)
            }

            // _atan2f
            let c_atan = CXBolo._atan2f(cv1)
            let s_atan = BoloCore._atan2f(v1)
            #expect(c_atan == s_atan)

            for v2 in swiftVectors {
                let cv2 = toC(v2)

                // add2f
                let c_add = CXBolo.add2f(cv1, cv2)
                let s_add = BoloCore.add2f(v1, v2)
                #expect(c_add.x == s_add.x && c_add.y == s_add.y)

                // sub2f
                let c_sub = CXBolo.sub2f(cv1, cv2)
                let s_sub = BoloCore.sub2f(v1, v2)
                #expect(c_sub.x == s_sub.x && c_sub.y == s_sub.y)

                // dot2f
                let c_dot = CXBolo.dot2f(cv1, cv2)
                let s_dot = BoloCore.dot2f(v1, v2)
                #expect(c_dot == s_dot)

                // isequal2f
                let c_eq = CXBolo.isequal2f(cv1, cv2)
                let s_eq = BoloCore.isequal2f(v1, v2)
                #expect(c_eq == s_eq)

                // prj2f and cmp2f (skip zero projection vector to avoid NaN)
                if v1.x != 0 || v1.y != 0 {
                    let c_prj = CXBolo.prj2f(cv1, cv2)
                    let s_prj = BoloCore.prj2f(v1, v2)
                    #expect(c_prj.x == s_prj.x && c_prj.y == s_prj.y)

                    let c_cmp = CXBolo.cmp2f(cv1, cv2)
                    let s_cmp = BoloCore.cmp2f(v1, v2)
                    #expect(c_cmp == s_cmp)
                }
            }

            // mul2f and div2f with scalar
            for s in fuzzedCoords {
                let c_mul = CXBolo.mul2f(cv1, s)
                let s_mul = BoloCore.mul2f(v1, s)
                #expect(c_mul.x == s_mul.x && c_mul.y == s_mul.y)

                if s != 0 {
                    let c_div = CXBolo.div2f(cv1, s)
                    let s_div = BoloCore.div2f(v1, s)
                    #expect(c_div.x == s_div.x && c_div.y == s_div.y)
                }
            }
        }
    }

    // MARK: - Vec2i32 Tests

    @Test func testVec2i32Operations() {
        let fuzzedCoords: [Int32] = [-1000, -500, -1, 0, 1, 500, 1000]
        var swiftVectors: [BoloCore.Vec2i32] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                swiftVectors.append(BoloCore.Vec2i32(x: x, y: y))
            }
        }

        for v1 in swiftVectors {
            let cv1 = toC(v1)

            // neg2i32
            let c_neg = CXBolo.neg2i32(cv1)
            let s_neg = BoloCore.neg2i32(v1)
            #expect(c_neg.x == s_neg.x && c_neg.y == s_neg.y)

            // mag2i32
            let c_mag = CXBolo.mag2i32(cv1)
            let s_mag = BoloCore.mag2i32(v1)
            #expect(c_mag == s_mag)

            for v2 in swiftVectors {
                let cv2 = toC(v2)

                // add2i32
                let c_add = CXBolo.add2i32(cv1, cv2)
                let s_add = BoloCore.add2i32(v1, v2)
                #expect(c_add.x == s_add.x && c_add.y == s_add.y)

                // sub2i32
                let c_sub = CXBolo.sub2i32(cv1, cv2)
                let s_sub = BoloCore.sub2i32(v1, v2)
                #expect(c_sub.x == s_sub.x && c_sub.y == s_sub.y)

                // dot2i32
                let c_dot = CXBolo.dot2i32(cv1, cv2)
                let s_dot = BoloCore.dot2i32(v1, v2)
                #expect(c_dot == s_dot)

                // isequal2i32
                let c_eq = CXBolo.isequal2i32(cv1, cv2)
                let s_eq = BoloCore.isequal2i32(v1, v2)
                #expect(c_eq == s_eq)

                // prj2i32 and cmp2i32 (skip zero projection vector to avoid crash/division by zero)
                if v1.x != 0 || v1.y != 0 {
                    let c_prj = CXBolo.prj2i32(cv1, cv2)
                    let s_prj = BoloCore.prj2i32(v1, v2)
                    #expect(c_prj.x == s_prj.x && c_prj.y == s_prj.y)

                    let c_cmp = CXBolo.cmp2i32(cv1, cv2)
                    let s_cmp = BoloCore.cmp2i32(v1, v2)
                    #expect(c_cmp == s_cmp)
                }
            }

            // mul2i32 and div2i32
            for s in fuzzedCoords {
                let c_mul = CXBolo.mul2i32(cv1, s)
                let s_mul = BoloCore.mul2i32(v1, s)
                #expect(c_mul.x == s_mul.x && c_mul.y == s_mul.y)

                if s != 0 {
                    let c_div = CXBolo.div2i32(cv1, s)
                    let s_div = BoloCore.div2i32(v1, s)
                    #expect(c_div.x == s_div.x && c_div.y == s_div.y)
                }
            }
        }
    }

    // MARK: - Vec2i16 Tests

    @Test func testVec2i16Operations() {
        let fuzzedCoords: [Int16] = [-100, -50, -1, 0, 1, 50, 100]
        var swiftVectors: [BoloCore.Vec2i16] = []
        for x in fuzzedCoords {
            for y in fuzzedCoords {
                swiftVectors.append(BoloCore.Vec2i16(x: x, y: y))
            }
        }

        for v1 in swiftVectors {
            let cv1 = toC(v1)

            // neg2i16
            let c_neg = CXBolo.neg2i16(cv1)
            let s_neg = BoloCore.neg2i16(v1)
            #expect(c_neg.x == s_neg.x && c_neg.y == s_neg.y)

            // mag2i16
            let c_mag = CXBolo.mag2i16(cv1)
            let s_mag = BoloCore.mag2i16(v1)
            #expect(c_mag == s_mag)

            for v2 in swiftVectors {
                let cv2 = toC(v2)

                // add2i16
                let c_add = CXBolo.add2i16(cv1, cv2)
                let s_add = BoloCore.add2i16(v1, v2)
                #expect(c_add.x == s_add.x && c_add.y == s_add.y)

                // sub2i16
                let c_sub = CXBolo.sub2i16(cv1, cv2)
                let s_sub = BoloCore.sub2i16(v1, v2)
                #expect(c_sub.x == s_sub.x && c_sub.y == s_sub.y)

                // dot2i16
                let c_dot = CXBolo.dot2i16(cv1, cv2)
                let s_dot = BoloCore.dot2i16(v1, v2)
                #expect(c_dot == s_dot)

                // isequal2i16
                let c_eq = CXBolo.isequal2i16(cv1, cv2)
                let s_eq = BoloCore.isequal2i16(v1, v2)
                #expect(c_eq == s_eq)

                // prj2i16 and cmp2i16 (skip zero projection vector to avoid crash/division by zero)
                if v1.x != 0 || v1.y != 0 {
                    let c_prj = CXBolo.prj2i16(cv1, cv2)
                    let s_prj = BoloCore.prj2i16(v1, v2)
                    #expect(c_prj.x == s_prj.x && c_prj.y == s_prj.y)

                    let c_cmp = CXBolo.cmp2i16(cv1, cv2)
                    let s_cmp = BoloCore.cmp2i16(v1, v2)
                    #expect(c_cmp == s_cmp)
                }
            }

            // mul2i16 and div2i16
            for s in fuzzedCoords {
                let c_mul = CXBolo.mul2i16(cv1, s)
                let s_mul = BoloCore.mul2i16(v1, s)
                #expect(c_mul.x == s_mul.x && c_mul.y == s_mul.y)

                if s != 0 {
                    let c_div = CXBolo.div2i16(cv1, s)
                    let s_div = BoloCore.div2i16(v1, s)
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
            let s_tan32 = BoloCore.tan2i32(dir)
            #expect(c_tan32.x == s_tan32.x && c_tan32.y == s_tan32.y)

            // tan2i16
            let c_tan16 = CXBolo.tan2i16(dir)
            let s_tan16 = BoloCore.tan2i16(dir)
            #expect(c_tan16.x == s_tan16.x && c_tan16.y == s_tan16.y)

            // scale2i32
            let scale32Values: [Int32] = [1, 10, 100, 1000]
            for scale in scale32Values {
                let c_scale32 = CXBolo.scale2i32(dir, scale)
                let s_scale32 = BoloCore.scale2i32(dir, scale)
                #expect(c_scale32.x == s_scale32.x && c_scale32.y == s_scale32.y)
            }

            // scale2i16
            let scale16Values: [Int16] = [1, 10, 100, 1000]
            for scale in scale16Values {
                let c_scale16 = CXBolo.scale2i16(dir, scale)
                let s_scale16 = BoloCore.scale2i16(dir, scale)
                #expect(c_scale16.x == s_scale16.x && c_scale16.y == s_scale16.y)
            }
        }
    }

    // MARK: - Cast & Type Tests

    @Test func testCasts() {
        let values32: [Int32] = [0, 100, -100, 32767, -32768, 65535, -65536, Int32.max, Int32.min]
        for x in values32 {
            for y in values32 {
                let v = BoloCore.Vec2i32(x: x, y: y)
                let cv = toC(v)

                let c_cast = CXBolo.c2i32to2i16(cv)
                let s_cast = BoloCore.c2i32to2i16(v)
                #expect(c_cast.x == s_cast.x && c_cast.y == s_cast.y)
            }
        }

        let values16: [Int16] = [0, 100, -100, 127, -128, 255, -256, Int16.max, Int16.min]
        for x in values16 {
            for y in values16 {
                let v = BoloCore.Vec2i16(x: x, y: y)
                let cv = toC(v)

                let c_cast = CXBolo.c2i16to2i8(cv)
                let s_cast = BoloCore.c2i16to2i8(v)
                #expect(c_cast.x == s_cast.x && c_cast.y == s_cast.y)
            }
        }
    }

    @Test func testVec2i8() {
        let values8: [Int8] = [-128, -50, 0, 50, 127]
        for x1 in values8 {
            for y1 in values8 {
                let v1 = BoloCore.Vec2i8(x: x1, y: y1)
                let cv1 = toC(v1)

                // make2i8
                let c_make = CXBolo.make2i8(x1, y1)
                #expect(c_make.x == v1.x && c_make.y == v1.y)

                for x2 in values8 {
                    for y2 in values8 {
                        let v2 = BoloCore.Vec2i8(x: x2, y: y2)
                        let cv2 = toC(v2)

                        let c_eq = CXBolo.isequal2i8(cv1, cv2)
                        let s_eq = BoloCore.isequal2i8(v1, v2)
                        #expect(c_eq == s_eq)
                    }
                }
            }
        }
    }
}
