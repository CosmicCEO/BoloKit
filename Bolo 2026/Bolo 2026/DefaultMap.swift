//
//  DefaultMap.swift
//  Bolo 2026
//
//  Bundled teaching map: compact grass island, one straight river, one road
//  bridge, 1 start, 2 pills, 3 bases. Bytes are `encodeBMap` of
//  `defaultBundledMapState()`. Host load still goes through decode +
//  `serverPostProcessLoadedMap`, then `applyDefaultBundledMapOwners`.
//

import BoloKit

let defaultMapFileBytes: [UInt8] = encodeBMap(defaultBundledMapState())
