import SwiftUI

struct EVECategoryStyle {
    let symbol: String
    let color: Color
}

func eveCategoryStyle(for name: String) -> EVECategoryStyle {
    let n = name.lowercased()
    if n == "ship" || n.hasSuffix(" ships")            { return .init(symbol: "airplane.fill",                   color: Color(red: 0.25, green: 0.55, blue: 0.95)) }
    if n.contains("module")                             { return .init(symbol: "gears",                           color: Color(red: 0.25, green: 0.72, blue: 0.75)) }
    if n.contains("drone")                              { return .init(symbol: "hexagon.fill",                    color: Color(red: 0.90, green: 0.72, blue: 0.10)) }
    if n.contains("charge") || n.contains("ammo")      { return .init(symbol: "bolt.fill",                       color: Color(red: 0.90, green: 0.50, blue: 0.15)) }
    if n.contains("skill")                              { return .init(symbol: "graduationcap.fill",              color: Color(red: 0.62, green: 0.30, blue: 0.90)) }
    if n.contains("infrastructure")                     { return .init(symbol: "wrench.and.screwdriver.fill",     color: Color(red: 0.55, green: 0.55, blue: 0.72)) }
    if n.contains("structure")                          { return .init(symbol: "building.2.fill",                 color: Color(red: 0.50, green: 0.52, blue: 0.68)) }
    if n.contains("deployable")                         { return .init(symbol: "antenna.radiowaves.left.and.right", color: Color(red: 0.20, green: 0.80, blue: 0.80)) }
    if n.contains("fighter")                            { return .init(symbol: "star.fill",                       color: Color(red: 0.90, green: 0.55, blue: 0.15)) }
    if n.contains("decryptor")                          { return .init(symbol: "key.fill",                        color: Color(red: 0.30, green: 0.70, blue: 0.60)) }
    if n.contains("expert")                             { return .init(symbol: "cpu.fill",                        color: Color(red: 0.70, green: 0.30, blue: 0.90)) }
    if n.contains("implant")                            { return .init(symbol: "waveform.path.ecg",               color: Color(red: 0.30, green: 0.80, blue: 0.45)) }
    if n.contains("material")                           { return .init(symbol: "cube.fill",                       color: Color(red: 0.65, green: 0.52, blue: 0.35)) }
    if n.contains("orbital")                            { return .init(symbol: "globe.americas.fill",             color: Color(red: 0.25, green: 0.55, blue: 0.90)) }
    if n.contains("personali")                          { return .init(symbol: "paintpalette.fill",               color: Color(red: 0.90, green: 0.40, blue: 0.70)) }
    if n.contains("planetary")                          { return .init(symbol: "globe.asia.australia.fill",       color: Color(red: 0.30, green: 0.70, blue: 0.42)) }
    if n.contains("reaction")                           { return .init(symbol: "atom",                            color: Color(red: 0.90, green: 0.50, blue: 0.20)) }
    if n.contains("asteroid") || n.contains("mineral") { return .init(symbol: "circle.hexagongrid.fill",         color: Color(red: 0.68, green: 0.64, blue: 0.60)) }
    if n.contains("blueprint")                          { return .init(symbol: "doc.badge.gearshape.fill",        color: Color(red: 0.25, green: 0.55, blue: 0.85)) }
    if n.contains("celestial")                          { return .init(symbol: "sun.max.fill",                    color: Color(red: 0.95, green: 0.80, blue: 0.15)) }
    if n.contains("apparel")                            { return .init(symbol: "tshirt.fill",                     color: Color(red: 0.70, green: 0.30, blue: 0.80)) }
    if n.contains("ancient") || n.contains("relic")    { return .init(symbol: "scroll.fill",                     color: Color(red: 0.80, green: 0.60, blue: 0.20)) }
    if n.contains("subsystem")                          { return .init(symbol: "puzzlepiece.fill",                color: Color(red: 0.22, green: 0.70, blue: 0.75)) }
    if n.contains("mutaplasmid")                        { return .init(symbol: "staroflife.fill",                 color: Color(red: 0.90, green: 0.20, blue: 0.25)) }
    if n.contains("faction") || n.contains("sovereignty") { return .init(symbol: "crown.fill",                   color: Color(red: 0.90, green: 0.70, blue: 0.15)) }
    if n.contains("skin")                               { return .init(symbol: "paintbrush.fill",                 color: Color(red: 0.90, green: 0.40, blue: 0.65)) }
    if n.contains("commodity")                          { return .init(symbol: "shippingbox.fill",                color: Color(red: 0.65, green: 0.55, blue: 0.38)) }
    if n.contains("trading")                            { return .init(symbol: "arrow.left.arrow.right",          color: Color(red: 0.30, green: 0.70, blue: 0.55)) }
    if n.contains("station")                            { return .init(symbol: "building.columns.fill",           color: Color(red: 0.50, green: 0.60, blue: 0.75)) }
    return .init(symbol: "square.grid.2x2.fill", color: Color(red: 0.40, green: 0.45, blue: 0.55))
}
