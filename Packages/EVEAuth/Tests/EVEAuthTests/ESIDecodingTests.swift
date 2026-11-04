import Foundation
import Testing
@testable import EVEAuth

/// What ESI sends that doesn't read as text yet. Each case came from a real character.
@Suite("ESI decoding")
struct ESIDecodingTests {
    @Test func shipNameAsPythonLiteral() throws {
        let json = #"{"ship_item_id": 1, "ship_name": "u'Hurricane\\xa0\\u2014 Alexandr Gercog'", "ship_type_id": 24702}"#
        let ship = try JSONDecoder.esi.decode(ESICurrentShip.self, from: Data(json.utf8))
        #expect(ship.shipName == "Hurricane — Alexandr Gercog")
    }

    @Test func plainShipNameUnchanged() throws {
        let json = #"{"ship_item_id": 1, "ship_name": "Drake", "ship_type_id": 29984}"#
        #expect(try JSONDecoder.esi.decode(ESICurrentShip.self, from: Data(json.utf8)).shipName == "Drake")
        #expect("u'".esiPythonLiteralDecoded == "u'")
        #expect("it's u'mine'".esiPythonLiteralDecoded == "it's u'mine'")
    }

    @Test func fitNameEntities() throws {
        let json = #"{"fitting_id": 1, "name": "Cerberus*&lt;/lo", "description": "a &amp;lt; b", "ship_type_id": 11993, "items": []}"#
        let fit = try JSONDecoder.esi.decode(ESIFitting.self, from: Data(json.utf8))
        #expect(fit.name == "Cerberus*</lo")
        #expect(fit.description == "a &lt; b")
    }
}
