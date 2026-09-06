/// Pure orchestrator, the `SheetBuilder.swift` analogue: builds all 24 named sound buffers
/// deterministically from the 14-entry parameter table in `SoundSource.swift`. No I/O.
///
/// 24 names total, 23 unique generated buffers: 14 designed + 10 `far*` derived by lowpass
/// filtering (`farCutoffHz`), except `fshot`, which per D122 is shared between `tankshot`'s and
/// `pillshot`'s far variant (there is no separate `fpillshot` -- matches the reference's own
/// single `kFarShotSound` case).
public func buildSounds() -> [String: SampleBuffer] {
    var result: [String: SampleBuffer] = [:]

    for name in designedSoundNames {
        guard let buffer = renderSound(named: name) else {
            fatalError("designedSoundNames lists \"\(name)\" but renderSound(named:) has no case for it")
        }
        result[name] = buffer
    }

    for (farName, nearName) in farNameSources {
        guard let nearBuffer = result[nearName] else {
            fatalError("farNameSources maps \"\(farName)\" to unknown near name \"\(nearName)\"")
        }
        result[farName] = lowpass(nearBuffer, cutoffHz: farCutoffHz)
    }

    // fshot (mapped above from tankshot) is reused for pillshot's far variant too -- there is
    // deliberately no separate "fpillshot" entry (D122).
    return result
}

/// All 24 output names, in the exact spelling used for the `.aiff` filenames -- `fshot` covers
/// both `tankshot` and `pillshot`'s far variant, so it appears once in this list even though it
/// conceptually serves two near names.
public let allSoundNames: [String] = designedSoundNames + Array(farNameSources.keys).sorted()
