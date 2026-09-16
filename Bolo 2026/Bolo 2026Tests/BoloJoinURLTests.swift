import Foundation
import Testing
@testable import Bolo_2026

// v1.3.0 #20 — bolo://join?host=&port= parse/make. Password is never
// written into generated URLs; a password query on paste is ignored.

struct BoloJoinURLTests {
    @Test func parseReadsHostAndPort() {
        let url = URL(string: "bolo://join?host=192.0.2.10&port=50000")!
        let join = BoloJoinURL.parse(url)
        #expect(join?.host == "192.0.2.10")
        #expect(join?.port == 50000)
    }

    @Test func parseRejectsWrongSchemeMissingOrBadFields() {
        #expect(BoloJoinURL.parse(URL(string: "https://join?host=a&port=50000")!) == nil)
        #expect(BoloJoinURL.parse(URL(string: "bolo://join?host=a")!) == nil)
        #expect(BoloJoinURL.parse(URL(string: "bolo://join?port=50000")!) == nil)
        #expect(BoloJoinURL.parse(URL(string: "bolo://join?host=a&port=nope")!) == nil)
        #expect(BoloJoinURL.parse(URL(string: "bolo://other?host=a&port=50000")!) == nil)
        #expect(BoloJoinURL.parse(URL(string: "file:///tmp/x.map")!) == nil)
    }

    @Test func parseIgnoresPasswordQuery() {
        let url = URL(string: "bolo://join?host=192.0.2.10&port=50000&password=secret")!
        let join = BoloJoinURL.parse(url)
        #expect(join?.host == "192.0.2.10")
        #expect(join?.port == 50000)
    }

    @Test func makeRoundTripsAndOmitsPassword() {
        let url = BoloJoinURL.make(host: "192.0.2.10", port: 50000)
        #expect(url.scheme == "bolo")
        #expect(!(url.absoluteString.contains("password")))
        let join = BoloJoinURL.parse(url)
        #expect(join?.host == "192.0.2.10")
        #expect(join?.port == 50000)
    }
}
