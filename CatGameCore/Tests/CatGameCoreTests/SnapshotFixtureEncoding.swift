import Foundation
import Testing
@testable import CatGameCore

/// Older migration tests start with today's complete snapshot, then remove the
/// fields under test. Write the released orientation vocabulary for its header;
/// migration decoders must not accept today's strings under an older schema.
func snapshotFixtureData(_ object: [String: Any], options: JSONSerialization.WritingOptions = []) throws -> Data {
    var object = object
    if let snapshot = object["snapshot"] as? [String: Any] {
        object["snapshot"] = try JSONSerialization.jsonObject(with: snapshotFixtureData(snapshot))
    }
    if let schema = object["schemaVersion"] as? Int, (1...14).contains(schema),
       var inventory = object["inventory"] as? [String: Any],
       var items = inventory["furniture"] as? [[String: Any]] {
        for index in items.indices {
            items[index].removeValue(forKey: "usesLegacyFootprint")
            if items[index]["orientation"] as? String == "front" { items[index]["orientation"] = "normal" }
            if items[index]["orientation"] as? String == "left" { items[index]["orientation"] = "mirrored" }
        }
        inventory["furniture"] = items
        object["inventory"] = inventory
    }
    return try JSONSerialization.data(withJSONObject: object, options: options)
}

func snapshotFixtureData(_ state: GameSnapshot) throws -> Data {
    let data = try JSONEncoder().encode(state)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try snapshotFixtureData(object)
}

/// Independent schema-15 expectation: released placed mirrors acquire only this marker.
func expectedLegacyFootprintMigration(_ original: GameSnapshot) throws -> GameSnapshot {
    var expected = original
    for index in expected.inventory.furniture.indices {
        let item = expected.inventory.furniture[index]
        guard item.orientation == .left, expected.home.furniture.contains(where: { $0.itemID == item.id }) else { continue }
        let data = try JSONSerialization.data(withJSONObject: ["id": item.id, "kind": item.kind.rawValue,
            "orientation": "left", "usesLegacyFootprint": true])
        expected.inventory.furniture[index] = try JSONDecoder().decode(FurnitureItem.self, from: data)
    }
    return expected
}
