//
//  ContentView.swift
//  Bolo 2026
//

import BoloKit
import SwiftUI

/// Wave 7.1 placeholder. This is the "minimal window" the sub-wave is scoped to — it exists to
/// prove the app shell is wired up, and is replaced wholesale by Wave 7.2's draw loop.
///
/// It deliberately reports the two things 7.1 is responsible for delivering, so a regression in
/// either is visible the moment the app launches rather than at 7.2:
///   - `BoloKit` is linked (reads a constant from `Physics.swift`),
///   - the D72 Run Script phase put both generated sheets in the bundle.
struct ContentView: View {
    private static let sheetNames = ["Tiles", "Sprites"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bolo 2026")
                .font(.title)
            Text("Wave 7.1 shell — no game rendering yet (Wave 7.2).")
                .foregroundStyle(.secondary)
            Divider()
            Text("BoloKit linked: \(Int(ticksPerSec)) ticks/sec")
            ForEach(Self.sheetNames, id: \.self) { name in
                Text("\(name).png in bundle: \(Self.isInBundle(name) ? "yes" : "NO")")
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 200)
    }

    private static func isInBundle(_ name: String) -> Bool {
        Bundle.main.url(forResource: name, withExtension: "png") != nil
    }
}

#Preview {
    ContentView()
}
