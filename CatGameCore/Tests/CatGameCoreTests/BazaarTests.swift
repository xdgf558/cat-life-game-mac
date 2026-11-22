import Foundation
import Testing
@testable import CatGameCore

@Suite("3.2 bazaar: swapping with neighbours and selling to the shop")
struct BazaarTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func piece(_ id: String, blueprint: String, quality: OutingDecorQuality = .common,
                       attributes: [HandmadeAttributeRoll] = [HandmadeAttributeRoll(attribute: .dailyMood, value: 3)],
                       durability: Int = 20, cap: Int = 20) -> HandmadeItem {
        HandmadeItem(id: id, blueprintID: blueprint, quality: quality, attributes: attributes, madeAt: now,
                     durability: durability, durabilityCap: cap)
    }

    /// A save with today's key and one piece that the first open request accepts.
    private func ready() throws -> (GameSnapshot, BazaarRequest, HandmadeItem) {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.synchronize(&state, now: now)
        let today = try #require(state.tasks.dailyDayKey)
        for request in BazaarCatalog.requests(day: today) {
            for definition in CraftCatalog.craftableBlueprints {
                let fragile = request.want == .fragile
                let item = piece("handmade-1", blueprint: definition.id, durability: fragile ? 2 : 20)
                if request.want.accepts(item) {
                    state.craft.handmade = [item]
                    state.craft.nextSerial = 2
                    return (state, request, item)
                }
            }
        }
        Issue.record("No request accepts any piece"); throw CancellationError()
    }

    @Test func requestsAreTheSameAllDayAndChangeWithTheDay() {
        let first = BazaarCatalog.requests(day: "2026-11-20")
        #expect(first == BazaarCatalog.requests(day: "2026-11-20"))
        #expect(first.count == CommunityCatalog.neighbors.count)
        let week = (10...16).map { BazaarCatalog.requests(day: "2026-11-\($0)") }
        #expect(Set(week.map { $0.map(\.want.key).joined() }).count > 1)
    }

    @Test func everyRequestCanBeMetByAWearableBlueprint() {
        for day in 1...28 {
            for request in BazaarCatalog.requests(day: String(format: "2026-11-%02d", day)) {
                let fits = CraftCatalog.craftableBlueprints.contains { definition in
                    request.want.accepts(piece("handmade-1", blueprint: definition.id, durability: request.want == .fragile ? 1 : 20))
                }
                #expect(fits, "\(request.neighborID) \(request.want.key)")
            }
        }
    }

    @Test func betterAndFresherPiecesEarnMore() throws {
        let request = BazaarRequest(neighborID: "neighbor_mira", want: .slot(.body), gold: 40,
                                    materials: [CraftCost(material: .wood, count: 3)], blueprintID: nil)
        let treasured = BazaarCatalog.deal(request, for: piece("handmade-1", blueprint: "baristaApron", quality: .treasured))
        #expect(treasured.gold == 70 && treasured.materials.first?.count == 4)
        #expect(treasured.goldChange == 30 && treasured.materialChange == 1)
        let worn = BazaarCatalog.deal(request, for: piece("handmade-2", blueprint: "baristaApron", durability: 8))
        #expect(worn.gold == 30 && worn.goldChange == -10 && worn.materialChange == 0)
    }

    @Test func shopPriceFollowsTheFormula() {
        // (60 × 1.8 + 2 × 12) × (50% + 50% × 36/38) = 132 × 97% = 128.
        let apron = piece("handmade-1", blueprint: "baristaApron", quality: .treasured,
                          attributes: [HandmadeAttributeRoll(attribute: .napRecovery, value: 20),
                                       HandmadeAttributeRoll(attribute: .dailyMood, value: 5)],
                          durability: 36, cap: 38)
        let quote = BazaarCatalog.saleQuote(for: apron)
        #expect(quote.basePrice == 60 && quote.qualityPercent == 180 && quote.attributeBonus == 24)
        #expect(quote.durabilityPercent == 97 && quote.price == 128 && !quote.isFragile)
        // About to break: half of fabric 3 × 8 + thread 1 × 6.
        let fragile = BazaarCatalog.saleQuote(for: piece("handmade-2", blueprint: "baristaApron", durability: 1, cap: 20))
        #expect(fragile.isFragile && fragile.materialValue == 30 && fragile.price == 15)
    }

    @Test func aTradeGivesTheDealOnceAndTheMarkIsDurable() throws {
        var (state, request, item) = try ready()
        let deal = BazaarCatalog.deal(request, for: item)
        let gold = state.player.gold
        let friendship = state.community.relationship(for: request.neighborID).friendship
        #expect(GameEngine.tradeHandmade(&state, neighborID: request.neighborID, itemID: item.id, now: now).succeeded)
        #expect(state.craft.item(id: item.id) == nil)
        #expect(state.player.gold >= gold + deal.gold)
        for cost in deal.materials { #expect(state.craft.count(of: cost.material) >= cost.count) }
        #expect(state.community.relationship(for: request.neighborID).friendship == friendship + BazaarCatalog.tradeFriendship)
        #expect(state.craft.bazaar.totalTrades == 1 && state.craft.bazaar.tradedToday == [request.neighborID])
        // The same neighbour won't swap again today, even for another fitting piece.
        state.craft.handmade = [piece("handmade-2", blueprint: item.blueprintID, durability: item.durability)]
        let before = state
        #expect(GameEngine.tradeHandmade(&state, neighborID: request.neighborID, itemID: "handmade-2", now: now).failure == .bazaarTradedToday)
        #expect(state == before)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(GameSnapshot.self, from: data).craft.bazaar == state.craft.bazaar)
    }

    @Test func wornOrUnwantedPiecesAreRefusedAndKept() throws {
        var (state, request, item) = try ready()
        let slot = try #require(item.blueprint?.product.slot)
        state.craft.appearance[slot] = item.id
        var before = state
        #expect(GameEngine.tradeHandmade(&state, neighborID: request.neighborID, itemID: item.id, now: now).failure == .bazaarWorn)
        #expect(GameEngine.sellHandmade(&state, itemID: item.id, now: now).failure == .bazaarWorn)
        #expect(state == before)
        state.craft.appearance = [:]
        // A piece that doesn't fit the request.
        let other = try #require(CraftCatalog.craftableBlueprints.first { definition in
            !request.want.accepts(piece("handmade-3", blueprint: definition.id))
        })
        state.craft.handmade.append(piece("handmade-3", blueprint: other.id))
        before = state
        #expect(GameEngine.tradeHandmade(&state, neighborID: request.neighborID, itemID: "handmade-3", now: now).failure == .bazaarNotWanted)
        #expect(state == before)
    }

    @Test func sellingPaysTheQuoteAndRemovesThePiece() throws {
        var (state, _, item) = try ready()
        let quote = BazaarCatalog.saleQuote(for: item)
        let gold = state.player.gold
        let outcome = GameEngine.sellHandmade(&state, itemID: item.id, now: now)
        #expect(outcome.succeeded && outcome.amount == quote.price)
        #expect(state.player.gold == gold + quote.price && state.craft.handmade.isEmpty)
        #expect(state.craft.bazaar.totalSold == 1 && state.craft.bazaar.totalTrades == 0)
    }

    @Test func fiveTradesTeachTheLuckyCharm() throws {
        var (state, _, _) = try ready()
        state.craft.bazaar.totalTrades = 4
        #expect(!state.craft.grantedSources.contains("luckyCharm"))
        let (fresh, request, item) = try ready()
        state.craft.handmade = fresh.craft.handmade
        #expect(GameEngine.tradeHandmade(&state, neighborID: request.neighborID, itemID: item.id, now: now).succeeded)
        #expect(state.craft.grantedSources.contains("luckyCharm"))
        #expect(state.craft.usesLeft("luckyCharm") > 0)
    }

    @Test func aDamagedBazaarRecordIsInvalid() {
        var state = GameSnapshot.fresh(now: now)
        state.craft.bazaar.tradedToday = ["neighbor_mira"]
        #expect(!state.isValid)
        state.craft.bazaar.dayKey = "2026-11-20"
        state.craft.bazaar.totalTrades = 1
        #expect(state.isValid)
        state.craft.bazaar.tradedToday = ["neighbor_mira", "neighbor_mira"]
        state.craft.bazaar.totalTrades = 2
        #expect(!state.isValid)
    }
}
