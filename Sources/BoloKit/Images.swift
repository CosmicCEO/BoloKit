import Darwin

// MARK: - Image Tile Constants

public let WALL46IMAGE: Int32 = 0x00
public let WALL17IMAGE: Int32 = 0x01
public let WALL01IMAGE: Int32 = 0x02
public let WALL20IMAGE: Int32 = 0x03
public let WALL04IMAGE: Int32 = 0x04
public let WALL05IMAGE: Int32 = 0x05
public let WALL27IMAGE: Int32 = 0x06
public let WALL28IMAGE: Int32 = 0x07
public let WALL38IMAGE: Int32 = 0x08
public let WALL32IMAGE: Int32 = 0x09
public let WALL25IMAGE: Int32 = 0x0a
public let WALL23IMAGE: Int32 = 0x0b
public let RIVE15IMAGE: Int32 = 0x0c
public let RIVE09IMAGE: Int32 = 0x0d
public let RIVE10IMAGE: Int32 = 0x0e
public let RIVE11IMAGE: Int32 = 0x0f
public let WALL22IMAGE: Int32 = 0x10
public let WALL12IMAGE: Int32 = 0x11
public let WALL13IMAGE: Int32 = 0x12
public let WALL14IMAGE: Int32 = 0x13
public let WALL00IMAGE: Int32 = 0x14
public let WALL02IMAGE: Int32 = 0x15
public let WALL29IMAGE: Int32 = 0x16
public let WALL30IMAGE: Int32 = 0x17
public let WALL33IMAGE: Int32 = 0x18
public let WALL35IMAGE: Int32 = 0x19
public let WALL26IMAGE: Int32 = 0x1a
public let WALL24IMAGE: Int32 = 0x1b
public let RIVE14IMAGE: Int32 = 0x1c
public let RIVE06IMAGE: Int32 = 0x1d
public let RIVE07IMAGE: Int32 = 0x1e
public let RIVE08IMAGE: Int32 = 0x1f
public let WALL03IMAGE: Int32 = 0x20
public let WALL09IMAGE: Int32 = 0x21
public let WALL10IMAGE: Int32 = 0x22
public let WALL11IMAGE: Int32 = 0x23
public let WALL40IMAGE: Int32 = 0x24
public let WALL39IMAGE: Int32 = 0x25
public let WALL19IMAGE: Int32 = 0x26
public let WALL16IMAGE: Int32 = 0x27
public let WALL31IMAGE: Int32 = 0x28
public let WALL37IMAGE: Int32 = 0x29
public let WALL44IMAGE: Int32 = 0x2a
public let WALL43IMAGE: Int32 = 0x2b
public let RIVE13IMAGE: Int32 = 0x2c
public let RIVE03IMAGE: Int32 = 0x2d
public let RIVE04IMAGE: Int32 = 0x2e
public let RIVE05IMAGE: Int32 = 0x2f
public let WALL15IMAGE: Int32 = 0x30
public let WALL06IMAGE: Int32 = 0x31
public let WALL07IMAGE: Int32 = 0x32
public let WALL08IMAGE: Int32 = 0x33
public let WALL42IMAGE: Int32 = 0x34
public let WALL41IMAGE: Int32 = 0x35
public let WALL21IMAGE: Int32 = 0x36
public let WALL18IMAGE: Int32 = 0x37
public let WALL36IMAGE: Int32 = 0x38
public let WALL34IMAGE: Int32 = 0x39
public let WALL45IMAGE: Int32 = 0x3a
public let FORE09IMAGE: Int32 = 0x3b
public let RIVE12IMAGE: Int32 = 0x3c
public let RIVE00IMAGE: Int32 = 0x3d
public let RIVE01IMAGE: Int32 = 0x3e
public let RIVE02IMAGE: Int32 = 0x3f
public let ROAD12IMAGE: Int32 = 0x40
public let ROAD13IMAGE: Int32 = 0x41
public let ROAD14IMAGE: Int32 = 0x42
public let ROAD24IMAGE: Int32 = 0x43
public let ROAD29IMAGE: Int32 = 0x44
public let ROAD25IMAGE: Int32 = 0x45
public let SEAA00IMAGE: Int32 = 0x46
public let SEAA02IMAGE: Int32 = 0x47
public let SEAA01IMAGE: Int32 = 0x48
public let FORE02IMAGE: Int32 = 0x49
public let FORE05IMAGE: Int32 = 0x4a
public let FORE06IMAGE: Int32 = 0x4b
public let CRAT15IMAGE: Int32 = 0x4c
public let CRAT09IMAGE: Int32 = 0x4d
public let CRAT10IMAGE: Int32 = 0x4e
public let CRAT11IMAGE: Int32 = 0x4f
public let ROAD09IMAGE: Int32 = 0x50
public let ROAD10IMAGE: Int32 = 0x51
public let ROAD11IMAGE: Int32 = 0x52
public let ROAD27IMAGE: Int32 = 0x53
public let ROAD30IMAGE: Int32 = 0x54
public let ROAD28IMAGE: Int32 = 0x55
public let SEAA04IMAGE: Int32 = 0x56
public let SEAA08IMAGE: Int32 = 0x57
public let SEAA06IMAGE: Int32 = 0x58
public let FORE08IMAGE: Int32 = 0x59
public let FORE03IMAGE: Int32 = 0x5a
public let FORE04IMAGE: Int32 = 0x5b
public let CRAT14IMAGE: Int32 = 0x5c
public let CRAT06IMAGE: Int32 = 0x5d
public let CRAT07IMAGE: Int32 = 0x5e
public let CRAT08IMAGE: Int32 = 0x5f
public let ROAD06IMAGE: Int32 = 0x60
public let ROAD07IMAGE: Int32 = 0x61
public let ROAD08IMAGE: Int32 = 0x62
public let ROAD20IMAGE: Int32 = 0x63
public let ROAD26IMAGE: Int32 = 0x64
public let ROAD22IMAGE: Int32 = 0x65
public let SEAA03IMAGE: Int32 = 0x66
public let SEAA07IMAGE: Int32 = 0x67
public let SEAA05IMAGE: Int32 = 0x68
public let FORE07IMAGE: Int32 = 0x69
public let FORE00IMAGE: Int32 = 0x6a
public let FORE01IMAGE: Int32 = 0x6b
public let CRAT13IMAGE: Int32 = 0x6c
public let CRAT03IMAGE: Int32 = 0x6d
public let CRAT04IMAGE: Int32 = 0x6e
public let CRAT05IMAGE: Int32 = 0x6f
public let ROAD00IMAGE: Int32 = 0x70
public let ROAD02IMAGE: Int32 = 0x71
public let ROAD04IMAGE: Int32 = 0x72
public let ROAD05IMAGE: Int32 = 0x73
public let ROAD03IMAGE: Int32 = 0x74
public let ROAD01IMAGE: Int32 = 0x75
public let ROAD15IMAGE: Int32 = 0x76
public let ROAD18IMAGE: Int32 = 0x77
public let ROAD17IMAGE: Int32 = 0x78
public let ROAD16IMAGE: Int32 = 0x79
public let ROAD23IMAGE: Int32 = 0x7a
public let ROAD21IMAGE: Int32 = 0x7b
public let CRAT12IMAGE: Int32 = 0x7c
public let CRAT00IMAGE: Int32 = 0x7d
public let CRAT01IMAGE: Int32 = 0x7e
public let CRAT02IMAGE: Int32 = 0x7f
public let BOAT00IMAGE: Int32 = 0x80
public let BOAT01IMAGE: Int32 = 0x81
public let BOAT02IMAGE: Int32 = 0x82
public let BOAT03IMAGE: Int32 = 0x83
public let BOAT04IMAGE: Int32 = 0x84
public let BOAT05IMAGE: Int32 = 0x85
public let BOAT06IMAGE: Int32 = 0x86
public let BOAT07IMAGE: Int32 = 0x87
public let GRAS00IMAGE: Int32 = 0x88
public let SWAM00IMAGE: Int32 = 0x89
public let RUBB00IMAGE: Int32 = 0x8a
public let DAMG00IMAGE: Int32 = 0x8b
public let NBAS00IMAGE: Int32 = 0x8c
public let FBAS00IMAGE: Int32 = 0x8d
public let HBAS00IMAGE: Int32 = 0x8e
public let ROAD19IMAGE: Int32 = 0x8f
public let FPIL00IMAGE: Int32 = 0x90
public let FPIL01IMAGE: Int32 = 0x91
public let FPIL02IMAGE: Int32 = 0x92
public let FPIL03IMAGE: Int32 = 0x93
public let FPIL04IMAGE: Int32 = 0x94
public let FPIL05IMAGE: Int32 = 0x95
public let FPIL06IMAGE: Int32 = 0x96
public let FPIL07IMAGE: Int32 = 0x97
public let FPIL08IMAGE: Int32 = 0x98
public let FPIL09IMAGE: Int32 = 0x99
public let FPIL10IMAGE: Int32 = 0x9a
public let FPIL11IMAGE: Int32 = 0x9b
public let FPIL12IMAGE: Int32 = 0x9c
public let FPIL13IMAGE: Int32 = 0x9d
public let FPIL14IMAGE: Int32 = 0x9e
public let FPIL15IMAGE: Int32 = 0x9f
public let HPIL00IMAGE: Int32 = 0xa0
public let HPIL01IMAGE: Int32 = 0xa1
public let HPIL02IMAGE: Int32 = 0xa2
public let HPIL03IMAGE: Int32 = 0xa3
public let HPIL04IMAGE: Int32 = 0xa4
public let HPIL05IMAGE: Int32 = 0xa5
public let HPIL06IMAGE: Int32 = 0xa6
public let HPIL07IMAGE: Int32 = 0xa7
public let HPIL08IMAGE: Int32 = 0xa8
public let HPIL09IMAGE: Int32 = 0xa9
public let HPIL10IMAGE: Int32 = 0xaa
public let HPIL11IMAGE: Int32 = 0xab
public let HPIL12IMAGE: Int32 = 0xac
public let HPIL13IMAGE: Int32 = 0xad
public let HPIL14IMAGE: Int32 = 0xae
public let HPIL15IMAGE: Int32 = 0xaf
public let MINE00IMAGE: Int32 = 0xb0

// MARK: - Sprite Image Constants

public let PTKB00IMAGE: Int32 = 0x00
public let PTKB01IMAGE: Int32 = 0x01
public let PTKB02IMAGE: Int32 = 0x02
public let PTKB03IMAGE: Int32 = 0x03
public let PTKB04IMAGE: Int32 = 0x04
public let PTKB05IMAGE: Int32 = 0x05
public let PTKB06IMAGE: Int32 = 0x06
public let PTKB07IMAGE: Int32 = 0x07
public let PTKB08IMAGE: Int32 = 0x08
public let PTKB09IMAGE: Int32 = 0x09
public let PTKB10IMAGE: Int32 = 0x0a
public let PTKB11IMAGE: Int32 = 0x0b
public let PTKB12IMAGE: Int32 = 0x0c
public let PTKB13IMAGE: Int32 = 0x0d
public let PTKB14IMAGE: Int32 = 0x0e
public let PTKB15IMAGE: Int32 = 0x0f
public let PTNK00IMAGE: Int32 = 0x10
public let PTNK01IMAGE: Int32 = 0x11
public let PTNK02IMAGE: Int32 = 0x12
public let PTNK03IMAGE: Int32 = 0x13
public let PTNK04IMAGE: Int32 = 0x14
public let PTNK05IMAGE: Int32 = 0x15
public let PTNK06IMAGE: Int32 = 0x16
public let PTNK07IMAGE: Int32 = 0x17
public let PTNK08IMAGE: Int32 = 0x18
public let PTNK09IMAGE: Int32 = 0x19
public let PTNK10IMAGE: Int32 = 0x1a
public let PTNK11IMAGE: Int32 = 0x1b
public let PTNK12IMAGE: Int32 = 0x1c
public let PTNK13IMAGE: Int32 = 0x1d
public let PTNK14IMAGE: Int32 = 0x1e
public let PTNK15IMAGE: Int32 = 0x1f
public let FTKB00IMAGE: Int32 = 0x20
public let FTKB01IMAGE: Int32 = 0x21
public let FTKB02IMAGE: Int32 = 0x22
public let FTKB03IMAGE: Int32 = 0x23
public let FTKB04IMAGE: Int32 = 0x24
public let FTKB05IMAGE: Int32 = 0x25
public let FTKB06IMAGE: Int32 = 0x26
public let FTKB07IMAGE: Int32 = 0x27
public let FTKB08IMAGE: Int32 = 0x28
public let FTKB09IMAGE: Int32 = 0x29
public let FTKB10IMAGE: Int32 = 0x2a
public let FTKB11IMAGE: Int32 = 0x2b
public let FTKB12IMAGE: Int32 = 0x2c
public let FTKB13IMAGE: Int32 = 0x2d
public let FTKB14IMAGE: Int32 = 0x2e
public let FTKB15IMAGE: Int32 = 0x2f
public let FTNK00IMAGE: Int32 = 0x30
public let FTNK01IMAGE: Int32 = 0x31
public let FTNK02IMAGE: Int32 = 0x32
public let FTNK03IMAGE: Int32 = 0x33
public let FTNK04IMAGE: Int32 = 0x34
public let FTNK05IMAGE: Int32 = 0x35
public let FTNK06IMAGE: Int32 = 0x36
public let FTNK07IMAGE: Int32 = 0x37
public let FTNK08IMAGE: Int32 = 0x38
public let FTNK09IMAGE: Int32 = 0x39
public let FTNK10IMAGE: Int32 = 0x3a
public let FTNK11IMAGE: Int32 = 0x3b
public let FTNK12IMAGE: Int32 = 0x3c
public let FTNK13IMAGE: Int32 = 0x3d
public let FTNK14IMAGE: Int32 = 0x3e
public let FTNK15IMAGE: Int32 = 0x3f
public let ETKB00IMAGE: Int32 = 0x40
public let ETKB01IMAGE: Int32 = 0x41
public let ETKB02IMAGE: Int32 = 0x42
public let ETKB03IMAGE: Int32 = 0x43
public let ETKB04IMAGE: Int32 = 0x44
public let ETKB05IMAGE: Int32 = 0x45
public let ETKB06IMAGE: Int32 = 0x46
public let ETKB07IMAGE: Int32 = 0x47
public let ETKB08IMAGE: Int32 = 0x48
public let ETKB09IMAGE: Int32 = 0x49
public let ETKB10IMAGE: Int32 = 0x4a
public let ETKB11IMAGE: Int32 = 0x4b
public let ETKB12IMAGE: Int32 = 0x4c
public let ETKB13IMAGE: Int32 = 0x4d
public let ETKB14IMAGE: Int32 = 0x4e
public let ETKB15IMAGE: Int32 = 0x4f
public let ETNK00IMAGE: Int32 = 0x50
public let ETNK01IMAGE: Int32 = 0x51
public let ETNK02IMAGE: Int32 = 0x52
public let ETNK03IMAGE: Int32 = 0x53
public let ETNK04IMAGE: Int32 = 0x54
public let ETNK05IMAGE: Int32 = 0x55
public let ETNK06IMAGE: Int32 = 0x56
public let ETNK07IMAGE: Int32 = 0x57
public let ETNK08IMAGE: Int32 = 0x58
public let ETNK09IMAGE: Int32 = 0x59
public let ETNK10IMAGE: Int32 = 0x5a
public let ETNK11IMAGE: Int32 = 0x5b
public let ETNK12IMAGE: Int32 = 0x5c
public let ETNK13IMAGE: Int32 = 0x5d
public let ETNK14IMAGE: Int32 = 0x5e
public let ETNK15IMAGE: Int32 = 0x5f
public let SHELL0IMAGE: Int32 = 0x60
public let SHELL1IMAGE: Int32 = 0x61
public let SHELL2IMAGE: Int32 = 0x62
public let SHELL3IMAGE: Int32 = 0x63
public let SHELL4IMAGE: Int32 = 0x64
public let SHELL5IMAGE: Int32 = 0x65
public let EXPLO0IMAGE: Int32 = 0x70
public let EXPLO1IMAGE: Int32 = 0x71
public let EXPLO2IMAGE: Int32 = 0x72
public let EXPLO3IMAGE: Int32 = 0x73
public let EXPLO4IMAGE: Int32 = 0x74
public let EXPLO5IMAGE: Int32 = 0x75
public let BUILD0IMAGE: Int32 = 0x80
public let BUILD1IMAGE: Int32 = 0x81
public let BUILD2IMAGE: Int32 = 0x82
public let CROSSHIMAGE: Int32 = 0x90
public let SELETRIMAGE: Int32 = 0x91

// MARK: - Map Autotiling Predicate

public func mapimage(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    guard x >= 0 && x < 256 && y >= 0 && y < 256 else {
        return -1
    }

    let tile = tiles[Int(y) * 256 + Int(x)]

    switch tile {
    case Tile.sea.rawValue, Tile.minedSea.rawValue:
        let neighbors = (isSeaLikeTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isSeaLikeTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isSeaLikeTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isSeaLikeTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 0, 5, 10, 15:
            return SEAA00IMAGE
        case 1, 11:
            return SEAA01IMAGE
        case 4, 14:
            return SEAA02IMAGE
        case 8, 13:
            return SEAA03IMAGE
        case 2, 7:
            return SEAA04IMAGE
        case 9:
            return SEAA05IMAGE
        case 3:
            return SEAA06IMAGE
        case 12:
            return SEAA07IMAGE
        case 6:
            return SEAA08IMAGE
        default:
            return SEAA00IMAGE
        }

    case Tile.river.rawValue:
        let neighbors = (isWaterLikeToWaterTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToWaterTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isWaterLikeToWaterTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isWaterLikeToWaterTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 12:
            return RIVE00IMAGE
        case 13:
            return RIVE01IMAGE
        case 9:
            return RIVE02IMAGE
        case 14:
            return RIVE03IMAGE
        case 15:
            return RIVE04IMAGE
        case 11:
            return RIVE05IMAGE
        case 6:
            return RIVE06IMAGE
        case 7:
            return RIVE07IMAGE
        case 3:
            return RIVE08IMAGE
        case 4:
            return RIVE09IMAGE
        case 5:
            return RIVE10IMAGE
        case 1:
            return RIVE11IMAGE
        case 8:
            return RIVE12IMAGE
        case 10:
            return RIVE13IMAGE
        case 2:
            return RIVE14IMAGE
        case 0:
            return RIVE15IMAGE
        default:
            return RIVE15IMAGE
        }

    case Tile.swamp.rawValue, Tile.minedSwamp.rawValue:
        return SWAM00IMAGE

    case Tile.grass.rawValue, Tile.minedGrass.rawValue:
        return GRAS00IMAGE

    case Tile.forest.rawValue, Tile.minedForest.rawValue:
        let neighbors = (isForestLikeTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isForestLikeTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isForestLikeTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isForestLikeTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 12:
            return FORE00IMAGE
        case 9:
            return FORE01IMAGE
        case 5, 7, 10, 11, 13, 14, 15:
            return FORE02IMAGE
        case 6:
            return FORE03IMAGE
        case 3:
            return FORE04IMAGE
        case 4:
            return FORE05IMAGE
        case 1:
            return FORE06IMAGE
        case 8:
            return FORE07IMAGE
        case 2:
            return FORE08IMAGE
        case 0:
            return FORE09IMAGE
        default:
            return FORE09IMAGE
        }

    case Tile.crater.rawValue, Tile.minedCrater.rawValue:
        let neighbors = (isCraterLikeTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isCraterLikeTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isCraterLikeTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isCraterLikeTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 12:
            return CRAT00IMAGE
        case 13:
            return CRAT01IMAGE
        case 9:
            return CRAT02IMAGE
        case 14:
            return CRAT03IMAGE
        case 15:
            return CRAT04IMAGE
        case 11:
            return CRAT05IMAGE
        case 6:
            return CRAT06IMAGE
        case 7:
            return CRAT07IMAGE
        case 3:
            return CRAT08IMAGE
        case 4:
            return CRAT09IMAGE
        case 5:
            return CRAT10IMAGE
        case 1:
            return CRAT11IMAGE
        case 8:
            return CRAT12IMAGE
        case 10:
            return CRAT13IMAGE
        case 2:
            return CRAT14IMAGE
        case 0:
            return CRAT15IMAGE
        default:
            return CRAT15IMAGE
        }

    case Tile.road.rawValue, Tile.minedRoad.rawValue:
        let neighbors = (isRoadLikeTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isRoadLikeTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isRoadLikeTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isRoadLikeTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 0:
            let water = (isWaterLikeToLandTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isWaterLikeToLandTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y + 1) != 0 ? 8 : 0)
            switch water {
            case 15:
                return ROAD30IMAGE
            case 5:
                return ROAD23IMAGE
            case 10:
                return ROAD21IMAGE
            default:
                return ROAD10IMAGE
            }

        case 1, 4, 5:
            let water = (isWaterLikeToLandTile(tiles, x, y - 1) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y + 1) != 0 ? 2 : 0)
            switch water {
            case 3:
                return ROAD21IMAGE
            default:
                return ROAD01IMAGE
            }

        case 2, 8, 10:
            let water = (isWaterLikeToLandTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x + 1, y) != 0 ? 2 : 0)
            switch water {
            case 3:
                return ROAD23IMAGE
            default:
                return ROAD03IMAGE
            }

        case 6:
            let water = (isWaterLikeToLandTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y + 1) != 0 ? 2 : 0)
            switch water {
            case 3:
                return ROAD24IMAGE
            default:
                if isRoadLikeTile(tiles, x + 1, y - 1) != 0 {
                    return ROAD12IMAGE
                } else {
                    return ROAD04IMAGE
                }
            }

        case 3:
            let water = (isWaterLikeToLandTile(tiles, x + 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y + 1) != 0 ? 2 : 0)
            switch water {
            case 3:
                return ROAD25IMAGE
            default:
                if isRoadLikeTile(tiles, x - 1, y - 1) != 0 {
                    return ROAD14IMAGE
                } else {
                    return ROAD05IMAGE
                }
            }

        case 7:
            if isWaterLikeToLandTile(tiles, x, y + 1) != 0 {
                return ROAD29IMAGE
            } else {
                let diag = (isRoadLikeTile(tiles, x - 1, y - 1) != 0 ? 1 : 0) |
                           (isRoadLikeTile(tiles, x + 1, y - 1) != 0 ? 2 : 0)
                if diag == 0 {
                    return ROAD18IMAGE
                } else {
                    return ROAD13IMAGE
                }
            }

        case 12:
            let water = (isWaterLikeToLandTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y - 1) != 0 ? 2 : 0)
            switch water {
            case 3:
                return ROAD20IMAGE
            default:
                if isRoadLikeTile(tiles, x + 1, y + 1) != 0 {
                    return ROAD06IMAGE
                } else {
                    return ROAD00IMAGE
                }
            }

        case 14:
            if isWaterLikeToLandTile(tiles, x - 1, y) != 0 {
                return ROAD27IMAGE
            } else {
                let diag = (isRoadLikeTile(tiles, x + 1, y - 1) != 0 ? 1 : 0) |
                           (isRoadLikeTile(tiles, x + 1, y + 1) != 0 ? 2 : 0)
                if diag == 0 {
                    return ROAD15IMAGE
                } else {
                    return ROAD09IMAGE
                }
            }

        case 9:
            let water = (isWaterLikeToLandTile(tiles, x, y - 1) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x + 1, y) != 0 ? 2 : 0)
            switch water {
            case 3:
                return ROAD22IMAGE
            default:
                if isRoadLikeTile(tiles, x - 1, y + 1) != 0 {
                    return ROAD08IMAGE
                } else {
                    return ROAD02IMAGE
                }
            }

        case 13:
            if isWaterLikeToLandTile(tiles, x, y - 1) != 0 {
                return ROAD26IMAGE
            } else {
                let diag = (isRoadLikeTile(tiles, x - 1, y + 1) != 0 ? 1 : 0) |
                           (isRoadLikeTile(tiles, x + 1, y + 1) != 0 ? 2 : 0)
                if diag == 0 {
                    return ROAD17IMAGE
                } else {
                    return ROAD07IMAGE
                }
            }

        case 11:
            if isWaterLikeToLandTile(tiles, x + 1, y) != 0 {
                return ROAD28IMAGE
            } else {
                let diag = (isRoadLikeTile(tiles, x - 1, y - 1) != 0 ? 1 : 0) |
                           (isRoadLikeTile(tiles, x - 1, y + 1) != 0 ? 2 : 0)
                if diag == 0 {
                    return ROAD16IMAGE
                } else {
                    return ROAD11IMAGE
                }
            }

        case 15:
            let diag = (isRoadLikeTile(tiles, x - 1, y - 1) != 0 ? 1 : 0) |
                       (isRoadLikeTile(tiles, x + 1, y - 1) != 0 ? 2 : 0) |
                       (isRoadLikeTile(tiles, x - 1, y + 1) != 0 ? 4 : 0) |
                       (isRoadLikeTile(tiles, x + 1, y + 1) != 0 ? 8 : 0)
            if diag == 0 {
                return ROAD19IMAGE
            } else {
                return ROAD10IMAGE
            }

        default:
            return ROAD10IMAGE
        }

    case Tile.rubble.rawValue, Tile.minedRubble.rawValue:
        return RUBB00IMAGE

    case Tile.damagedWall.rawValue:
        return DAMG00IMAGE

    case Tile.wall.rawValue:
        let neighbors = (isWallLikeTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWallLikeTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isWallLikeTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isWallLikeTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 0:
            return WALL46IMAGE
        case 4:
            return WALL17IMAGE
        case 2:
            return WALL22IMAGE
        case 6:
            if isWallLikeTile(tiles, x + 1, y - 1) != 0 {
                return WALL12IMAGE
            } else {
                return WALL04IMAGE
            }
        case 1:
            return WALL20IMAGE
        case 5:
            return WALL01IMAGE
        case 3:
            if isWallLikeTile(tiles, x - 1, y - 1) != 0 {
                return WALL14IMAGE
            } else {
                return WALL05IMAGE
            }
        case 7:
            let diag = (isWallLikeTile(tiles, x - 1, y - 1) != 0 ? 1 : 0) |
                       (isWallLikeTile(tiles, x + 1, y - 1) != 0 ? 2 : 0)
            switch diag {
            case 0:
                return WALL16IMAGE
            case 1:
                return WALL38IMAGE
            case 2:
                return WALL37IMAGE
            case 3:
                return WALL13IMAGE
            default:
                return WALL13IMAGE
            }
        case 8:
            return WALL15IMAGE
        case 12:
            if isWallLikeTile(tiles, x + 1, y + 1) != 0 {
                return WALL06IMAGE
            } else {
                return WALL00IMAGE
            }
        case 10:
            return WALL03IMAGE
        case 14:
            let diag = (isWallLikeTile(tiles, x + 1, y - 1) != 0 ? 1 : 0) |
                       (isWallLikeTile(tiles, x + 1, y + 1) != 0 ? 2 : 0)
            switch diag {
            case 0:
                return WALL19IMAGE
            case 1:
                return WALL33IMAGE
            case 2:
                return WALL31IMAGE
            case 3:
                return WALL09IMAGE
            default:
                return WALL09IMAGE
            }
        case 9:
            if isWallLikeTile(tiles, x - 1, y + 1) != 0 {
                return WALL08IMAGE
            } else {
                return WALL02IMAGE
            }
        case 13:
            let diag = (isWallLikeTile(tiles, x - 1, y + 1) != 0 ? 1 : 0) |
                       (isWallLikeTile(tiles, x + 1, y + 1) != 0 ? 2 : 0)
            switch diag {
            case 0:
                return WALL21IMAGE
            case 1:
                return WALL36IMAGE
            case 2:
                return WALL35IMAGE
            case 3:
                return WALL07IMAGE
            default:
                return WALL07IMAGE
            }
        case 11:
            let diag = (isWallLikeTile(tiles, x - 1, y - 1) != 0 ? 1 : 0) |
                       (isWallLikeTile(tiles, x - 1, y + 1) != 0 ? 2 : 0)
            switch diag {
            case 0:
                return WALL18IMAGE
            case 1:
                return WALL34IMAGE
            case 2:
                return WALL32IMAGE
            case 3:
                return WALL11IMAGE
            default:
                return WALL11IMAGE
            }
        case 15:
            let diag = (isWallLikeTile(tiles, x - 1, y - 1) != 0 ? 1 : 0) |
                       (isWallLikeTile(tiles, x + 1, y - 1) != 0 ? 2 : 0) |
                       (isWallLikeTile(tiles, x - 1, y + 1) != 0 ? 4 : 0) |
                       (isWallLikeTile(tiles, x + 1, y + 1) != 0 ? 8 : 0)
            switch diag {
            case 0:
                return WALL45IMAGE
            case 1:
                return WALL29IMAGE
            case 2:
                return WALL30IMAGE
            case 3:
                return WALL26IMAGE
            case 4:
                return WALL27IMAGE
            case 5:
                return WALL25IMAGE
            case 6:
                return WALL44IMAGE
            case 7:
                return WALL42IMAGE
            case 8:
                return WALL28IMAGE
            case 9:
                return WALL43IMAGE
            case 10:
                return WALL24IMAGE
            case 11:
                return WALL41IMAGE
            case 12:
                return WALL23IMAGE
            case 13:
                return WALL40IMAGE
            case 14:
                return WALL39IMAGE
            case 15:
                return WALL10IMAGE
            default:
                return WALL10IMAGE
            }
        default:
            return WALL46IMAGE
        }

    case Tile.boat.rawValue:
        let neighbors = (isWaterLikeToLandTile(tiles, x - 1, y) != 0 ? 1 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y - 1) != 0 ? 2 : 0) |
                        (isWaterLikeToLandTile(tiles, x + 1, y) != 0 ? 4 : 0) |
                        (isWaterLikeToLandTile(tiles, x, y + 1) != 0 ? 8 : 0)
        switch neighbors {
        case 0, 6, 15:
            return BOAT00IMAGE
        case 2, 7, 10:
            return BOAT01IMAGE
        case 3:
            return BOAT02IMAGE
        case 1, 11:
            return BOAT03IMAGE
        case 9:
            return BOAT04IMAGE
        case 8, 13:
            return BOAT05IMAGE
        case 12:
            return BOAT06IMAGE
        case 4, 5, 14:
            return BOAT07IMAGE
        default:
            return BOAT00IMAGE
        }

    case Tile.friendlyBase.rawValue:
        return FBAS00IMAGE

    case Tile.friendlyPill00.rawValue...Tile.friendlyPill15.rawValue:
        return FPIL00IMAGE + (tile - Tile.friendlyPill00.rawValue)

    case Tile.hostileBase.rawValue:
        return HBAS00IMAGE

    case Tile.hostilePill00.rawValue...Tile.hostilePill15.rawValue:
        return HPIL00IMAGE + (tile - Tile.hostilePill00.rawValue)

    case Tile.neutralBase.rawValue:
        return NBAS00IMAGE

    default:
        return -1
    }
}

public func mapimage(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        mapimage(buf.baseAddress!, x, y)
    }
}
