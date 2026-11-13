import Foundation
import CryptoKit
import CatGameCore

extension GameStore {
    static let sharedHomeSpaceNoticesKey = "catlife.sharedHome.spaceNotices.v1"

    func showSharedHomeSpaceNotice() {
        guard let snapshot, !isDecorating else { return }
        let placements = snapshot.home.placements(on: visibleHomeFloor).sorted { $0.itemID < $1.itemID }
        let placedIDs = Set(placements.map(\.itemID))
        let layout = SharedHomeNoticeLayout(floor: visibleHomeFloor, level: snapshot.home.roomLevel,
            bowl: snapshot.home.bowlPosition(on: visibleHomeFloor), placements: placements,
            items: snapshot.inventory.furniture.filter { placedIDs.contains($0.id) }.sorted { $0.id < $1.id },
            cats: snapshot.cats.map(\.id).sorted())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(layout) else { return }
        let signature = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let createdAt = snapshot.meta.createdAt.timeIntervalSince1970
        var history = sharedHomeNoticeDefaults.data(forKey: Self.sharedHomeSpaceNoticesKey)
            .flatMap { try? JSONDecoder().decode(SharedHomeNoticeHistory.self, from: $0) }
            ?? SharedHomeNoticeHistory(createdAt: createdAt, layouts: [])
        // Save encoding drops submillisecond precision; cold starts still identify the same save.
        if abs(history.createdAt - createdAt) >= 0.001 {
            history = SharedHomeNoticeHistory(createdAt: createdAt, layouts: [])
        }
        guard !history.layouts.contains(signature) else { return }
        // Keep local presentation history bounded as players repeatedly redecorate.
        history.layouts = Array(history.layouts.suffix(63)) + [signature]
        if let stored = try? encoder.encode(history) {
            sharedHomeNoticeDefaults.set(stored, forKey: Self.sharedHomeSpaceNoticesKey)
        }
        showFurnitureNotice("room.sharedHomeNoSpace")
    }
}

private struct SharedHomeNoticeLayout: Encodable {
    let floor: HomeFloor
    let level: Int
    let bowl: NormalizedPoint?
    let placements: [FurniturePlacement]
    let items: [FurnitureItem]
    let cats: [String]
}

private struct SharedHomeNoticeHistory: Codable {
    let createdAt: TimeInterval
    var layouts: [String]
}
