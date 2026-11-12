import Foundation

/// The native prototype's own save format. Web saves are never read or overwritten.
public struct GameSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 15
    public var schemaVersion: Int
    public var player: PlayerState
    public var cats: [CatState]
    public var activeCatID: String
    public var activeCat: CatState? { cats.first { $0.id == activeCatID } }
    public var inventory: InventoryState
    public var home: HomeState
    public var meta: SaveMetadata
    public var settings: GameSettings
    public var tasks: GameTaskState
    public var community: CommunityState
    public var catPlay: CatPlayState

    public init(schemaVersion: Int = Self.currentSchemaVersion, player: PlayerState,
                cats: [CatState], inventory: InventoryState, home: HomeState,
                meta: SaveMetadata, settings: GameSettings = GameSettings(), activeCatID: String? = nil,
                tasks: GameTaskState? = nil, community: CommunityState = CommunityState(), catPlay: CatPlayState = CatPlayState()) {
        self.schemaVersion = schemaVersion
        self.player = player
        self.cats = cats
        self.activeCatID = activeCatID ?? cats.first?.id ?? ""
        self.inventory = inventory
        self.home = home
        self.meta = meta
        self.settings = settings
        self.tasks = tasks ?? GameTaskState(dailyDayKey: GameTaskState.dayKey(for: meta.lastSyncAt))
        self.community = community
        self.catPlay = catPlay
        self.community.events.advance(to: self.tasks.dailyDayKey)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, player, cats, activeCatID, inventory, home, meta, settings, tasks, community, catPlay
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard (1...Self.currentSchemaVersion).contains(version) else {
            throw SaveRepositoryError.unsupportedSchemaVersion(version)
        }
        // Older fields keep their defaults; the next durable save upgrades the header.
        schemaVersion = Self.currentSchemaVersion
        player = try values.decode(PlayerState.self, forKey: .player)
        var catValues = try values.nestedUnkeyedContainer(forKey: .cats)
        var decodedCats: [CatState] = []
        while !catValues.isAtEnd { decodedCats.append(try CatState(from: catValues.superDecoder(), schemaVersion: version)) }
        guard version < 5 || decodedCats.allSatisfy({ $0.healthState != nil }) else {
            throw SaveRepositoryError.invalidSnapshot
        }
        guard decodedCats.allSatisfy({ ($0.growthState?.isValid ?? (version < 9))
            && (!$0.isPregnant || $0.growthState?.sex != .male) }) else {
            throw SaveRepositoryError.invalidSnapshot
        }
        cats = decodedCats
        // Selection is a display preference; a stale ID must not roll back cats or purchases.
        let selected = try? values.decode(String.self, forKey: .activeCatID)
        activeCatID = selected.flatMap { id in decodedCats.first { $0.id == id }?.id } ?? decodedCats.first?.id ?? ""
        inventory = try InventoryState(from: values.superDecoder(forKey: .inventory), schemaVersion: version)
        home = try HomeState(from: values.superDecoder(forKey: .home), schemaVersion: version)
        let placedIDs = Set(home.furniture.map(\.itemID))
        if version < 15 {
            for index in inventory.furniture.indices where !placedIDs.contains(inventory.furniture[index].id) {
                inventory.furniture[index] = inventory.furniture[index].usingCurrentFootprint()
            }
        } else if inventory.furniture.contains(where: { $0.usesLegacyFootprint && !placedIDs.contains($0.id) }) {
            throw SaveRepositoryError.invalidSnapshot
        }
        // The original starter cushion is cropped off the full-height room.
        // Only migrate the complete untouched starter layout; a moved, stored
        // or newly placed item makes the player's arrangement authoritative.
        if version < 6, home.bowlPosition == NormalizedPoint(x: 0.76, y: 0.79) {
            var legacyPlacements = FurnitureCatalog.legacyPlacementsV6
            if let index = legacyPlacements.firstIndex(where: { $0.itemID == "floorCushion" }) {
                legacyPlacements[index].position.x = 0.12
                if home.furniture.sorted(by: { $0.itemID < $1.itemID })
                    == legacyPlacements.sorted(by: { $0.itemID < $1.itemID }),
                   let savedIndex = home.furniture.firstIndex(where: { $0.itemID == "floorCushion" }) {
                    home.furniture[savedIndex].position = FurnitureCatalog.legacyPlacementsV6[index].position
                }
            }
        }
        meta = try values.decode(SaveMetadata.self, forKey: .meta)
        settings = try values.decodeIfPresent(GameSettings.self, forKey: .settings) ?? GameSettings()
        // Only pre-task saves receive empty receipts; damaged new receipts must never grant rewards again.
        tasks = version < 3 && !values.contains(.tasks)
            ? GameTaskState(dailyDayKey: GameTaskState.dayKey(for: meta.lastSyncAt))
            : try GameTaskState(from: values.superDecoder(forKey: .tasks), schemaVersion: version)
        tasks.restoreFurniturePurchaseHistory(from: inventory.furniture)
        community = version < 7 && !values.contains(.community)
            ? CommunityState() : try CommunityState(from: values.superDecoder(forKey: .community), schemaVersion: version)
        if version < 11 { community.events.advance(to: tasks.dailyDayKey) }
        catPlay = version < 12 && !values.contains(.catPlay) ? CatPlayState() : try values.decode(CatPlayState.self, forKey: .catPlay)
        // Reflow only untouched starter rooms; in-use and player-authored places remain authoritative.
        if version < 13, home.bowlPosition == NormalizedPoint(x: 0.76, y: 0.79), home.upperBowlPosition == nil,
           home.furniture.sorted(by: { $0.itemID < $1.itemID })
            == FurnitureCatalog.legacyPlacementsV6.sorted(by: { $0.itemID < $1.itemID }),
           catPlay.activeSession == nil,
           !cats.contains(where: { cat in
               cat.activeRest != nil || cat.habits.cornerFurnitureID != nil
                   || cat.habits.lastRestObservation.map { $0.id != cat.habits.dismissedRestOfferID } == true
           }) {
            let starterKinds: [String: FurnitureKind] = [
                "cabinet": .cabinet, "catTree": .catTree, "catBed": .catBed,
                "wallFlower": .wallFlower, "wallCat": .wallCat, "plantLarge": .plant,
                "plantSmall": .plant, "floorCushion": .floorCushion, "flowerStool": .flowerStool
            ]
            if starterKinds.allSatisfy({ id, kind in
                inventory.furniture.filter { $0.id == id } == [FurnitureItem(id: id, kind: kind)]
            }) {
                let positions = Dictionary(uniqueKeysWithValues: FurnitureCatalog.frontPlacementsV13.map { ($0.itemID, $0.position) })
                for index in home.furniture.indices {
                    if let position = positions[home.furniture[index].itemID] { home.furniture[index].position = position }
                }
            }
        }
        if version < 14 {
            for index in cats.indices {
                cats[index].habits.seedRestLocations(home: home, inventory: inventory)
                cats[index].habits.legacyRestSessionID = cats[index].activeRest?.id
            }
        }
        guard community.isValid, inventory.validGifts,
              community.events.dayKey.map({ eventDay in tasks.dailyDayKey.map { eventDay <= $0 } ?? false }) ?? true,
              tasks.dailyDayKey != nil || (community.dailyVisitCount == 0 && community.dailyGiftCount == 0 && community.dailyExchangeCount == 0)
        else { throw SaveRepositoryError.invalidSnapshot }
    }

    public static func fresh(now: Date = Date()) -> GameSnapshot {
        var snapshot = GameSnapshot(player: PlayerState(staminaUpdatedAt: now),
                                    cats: [CatState(id: CatCatalog.initialCatID, name: "小橘", now: now)],
                                    inventory: InventoryState(), home: HomeState(),
                                    meta: SaveMetadata(createdAt: now, lastSyncAt: now))
        for index in snapshot.cats.indices {
            snapshot.cats[index].habits.seedRestLocations(home: snapshot.home, inventory: snapshot.inventory)
        }
        return snapshot
    }
}

public struct PlayerState: Codable, Equatable, Sendable {
    public var gold: Int
    public var stamina: Int
    public var mood: Int
    public var activeWork: ActiveWork?
    public var staminaUpdatedAt: Date
    public var completedWorkCount: Int
    public var level: Int
    public var exp: Int
    public var lastWorkResult: WorkResult?
    public var profile: PlayerProfile
    public var activeSleep: PlayerSleep?
    /// Seconds toward the next sleep recovery point, retained between sessions.
    public var sleepStaminaRemainder: TimeInterval
    public var sleepMoodRemainder: TimeInterval

    public init(gold: Int = 200, stamina: Int = 80, mood: Int = 80,
                activeWork: ActiveWork? = nil, staminaUpdatedAt: Date,
                completedWorkCount: Int = 0, activeSleep: PlayerSleep? = nil,
                sleepStaminaRemainder: TimeInterval = 0, sleepMoodRemainder: TimeInterval = 0,
                level: Int = 1, exp: Int = 0, lastWorkResult: WorkResult? = nil,
                profile: PlayerProfile = PlayerProfile()) {
        self.gold = gold
        self.stamina = stamina
        self.mood = mood
        self.activeWork = activeWork
        self.staminaUpdatedAt = staminaUpdatedAt
        self.completedWorkCount = completedWorkCount
        self.level = level
        self.exp = exp
        self.lastWorkResult = lastWorkResult
        self.profile = profile
        self.activeSleep = activeSleep
        self.sleepStaminaRemainder = sleepStaminaRemainder
        self.sleepMoodRemainder = sleepMoodRemainder
    }

    private enum CodingKeys: String, CodingKey {
        case gold, stamina, mood, activeWork, staminaUpdatedAt, completedWorkCount
        case activeSleep, sleepStaminaRemainder, sleepMoodRemainder
        case level, exp, lastWorkResult, profile
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gold = try values.decode(Int.self, forKey: .gold)
        stamina = try values.decode(Int.self, forKey: .stamina)
        mood = try values.decode(Int.self, forKey: .mood)
        activeWork = try values.decodeIfPresent(ActiveWork.self, forKey: .activeWork)
        staminaUpdatedAt = try values.decode(Date.self, forKey: .staminaUpdatedAt)
        completedWorkCount = try values.decode(Int.self, forKey: .completedWorkCount)
        level = try values.decodeIfPresent(Int.self, forKey: .level) ?? 1
        exp = try values.decodeIfPresent(Int.self, forKey: .exp) ?? 0
        lastWorkResult = try values.decodeIfPresent(WorkResult.self, forKey: .lastWorkResult)
        // Only an absent profile receives the starter gift. Explicit malformed
        // data fails validation instead of silently granting or erasing items.
        profile = values.contains(.profile)
            ? try values.decode(PlayerProfile.self, forKey: .profile) : PlayerProfile()
        activeSleep = try values.decodeIfPresent(PlayerSleep.self, forKey: .activeSleep)
        sleepStaminaRemainder = try values.decodeIfPresent(TimeInterval.self, forKey: .sleepStaminaRemainder) ?? 0
        sleepMoodRemainder = try values.decodeIfPresent(TimeInterval.self, forKey: .sleepMoodRemainder) ?? 0
    }
}

public struct ActiveWork: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var jobID: String
    public var startedAt: Date
    public var endsAt: Date
    public var goldReward: Int
    public var expReward: Int
    public var quote: WorkQuote?

    public init(id: String = UUID().uuidString, jobID: String = "job_flyer",
                startedAt: Date, endsAt: Date, goldReward: Int = 60, expReward: Int = 22,
                quote: WorkQuote? = nil) {
        self.id = id
        self.jobID = jobID
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.goldReward = goldReward
        self.expReward = expReward
        self.quote = quote
    }

    private enum CodingKeys: String, CodingKey {
        case id, jobID, startedAt, endsAt, goldReward, expReward, quote
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        jobID = try values.decode(String.self, forKey: .jobID)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        endsAt = try values.decode(Date.self, forKey: .endsAt)
        goldReward = try values.decode(Int.self, forKey: .goldReward)
        expReward = try values.decodeIfPresent(Int.self, forKey: .expReward)
            ?? WorkCatalog.job(id: jobID)?.expReward ?? 0
        quote = try values.decodeIfPresent(WorkQuote.self, forKey: .quote)
    }
}

public struct CatState: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var customName: String?
    public var appearance: CatAppearance
    public var satiety: Int
    public var cleanliness: Int
    public var mood: Int
    public var intimacy: Int
    public var energy: Int
    public var health: Int
    /// nil exists only while loading a pre-health save, until its first synchronization.
    public var healthState: CatHealthState?
    /// Only pre-growth schemas may omit this until the shared migration boundary.
    public var growthState: CatGrowthState?
    public var isPregnant: Bool
    public var decayTracker: CatDecayTracker
    public var activeRest: CatRest?
    /// Prevent a delayed duplicate arrival from replaying the last rest session.
    public var lastRestSessionID: String?
    public var habits: CatHabitState

    public init(id: String, name: String, satiety: Int = 35, cleanliness: Int = 75,
                mood: Int = 85, intimacy: Int = 12, energy: Int = 80,
                health: Int = 90, isPregnant: Bool = false, now: Date,
                activeRest: CatRest? = nil, lastRestSessionID: String? = nil,
                customName: String? = nil, appearance: CatAppearance = .orange,
                healthState: CatHealthState? = nil, growthState: CatGrowthState? = nil, habits: CatHabitState = CatHabitState()) {
        self.id = id
        self.name = name
        self.customName = customName
        self.appearance = appearance
        self.satiety = satiety
        self.cleanliness = cleanliness
        self.mood = mood
        self.intimacy = intimacy
        self.energy = energy
        self.health = health
        self.healthState = healthState ?? CatHealthState(now: now)
        self.growthState = growthState ?? .adopted(appearance: appearance, now: now)
        self.isPregnant = isPregnant
        self.decayTracker = CatDecayTracker(now: now)
        self.activeRest = activeRest
        self.lastRestSessionID = lastRestSessionID ?? activeRest?.id
        self.habits = habits
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, customName, appearance, satiety, cleanliness, mood, intimacy, energy, health
        case isPregnant, decayTracker, activeRest, lastRestSessionID, healthState, growthState, habits
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        // A malformed cosmetic override cannot roll back the cat's progress.
        customName = (try? values.decode(String.self, forKey: .customName)).flatMap(CatNameRules.normalized)
        appearance = values.contains(.appearance)
            ? try values.decode(CatAppearance.self, forKey: .appearance) : .orange
        satiety = try values.decode(Int.self, forKey: .satiety)
        cleanliness = try values.decode(Int.self, forKey: .cleanliness)
        mood = try values.decode(Int.self, forKey: .mood)
        intimacy = try values.decode(Int.self, forKey: .intimacy)
        energy = try values.decode(Int.self, forKey: .energy)
        health = try values.decode(Int.self, forKey: .health)
        healthState = values.contains(.healthState)
            ? try values.decode(CatHealthState.self, forKey: .healthState) : nil
        growthState = values.contains(.growthState)
            ? try values.decode(CatGrowthState.self, forKey: .growthState) : nil
        isPregnant = try values.decode(Bool.self, forKey: .isPregnant)
        decayTracker = try values.decode(CatDecayTracker.self, forKey: .decayTracker)
        activeRest = try values.decodeIfPresent(CatRest.self, forKey: .activeRest)
        lastRestSessionID = try values.decodeIfPresent(String.self, forKey: .lastRestSessionID)
        habits = schemaVersion < 12 && !values.contains(.habits) ? CatHabitState()
            : try CatHabitState(from: values.superDecoder(forKey: .habits), schemaVersion: schemaVersion)
    }
}

public struct CatDecayTracker: Codable, Equatable, Sendable {
    public var satiety: Date
    public var cleanliness: Date
    public var mood: Date
    public var energy: Date

    public init(now: Date) {
        satiety = now
        cleanliness = now
        mood = now
        energy = now
    }
}

public struct InventoryState: Codable, Equatable, Sendable {
    public var food: Int
    public var litter: Int
    public var premiumFood: Int
    public var premiumLitter: Int
    /// Remaining play uses. One purchased wand supplies six uses.
    public var toys: Int
    /// Every owned instance, including furniture currently placed in the room.
    public var furniture: [FurnitureItem]
    public var gifts: [String: Int]

    public init(food: Int = 3, litter: Int = 2, toys: Int = 0,
                furniture: [FurnitureItem] = FurnitureCatalog.defaultItems, gifts: [String: Int] = [:],
                premiumFood: Int = 0, premiumLitter: Int = 0) {
        self.food = food
        self.litter = litter
        self.premiumFood = premiumFood
        self.premiumLitter = premiumLitter
        self.toys = toys
        self.furniture = furniture
        self.gifts = gifts
    }

    public func giftCount(_ giftID: String) -> Int { gifts[giftID, default: 0] }

    var validGifts: Bool {
        gifts.count <= 64 && gifts.allSatisfy {
            !$0.key.isEmpty && $0.key.utf8.count <= 80 && (0...GameSnapshot.maximumStock).contains($0.value)
        }
    }

    private enum CodingKeys: String, CodingKey { case food, litter, toys, furniture, gifts, premiumFood, premiumLitter }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        food = try values.decode(Int.self, forKey: .food)
        litter = try values.decode(Int.self, forKey: .litter)
        premiumFood = schemaVersion < 8 && !values.contains(.premiumFood)
            ? 0 : try values.decode(Int.self, forKey: .premiumFood)
        premiumLitter = schemaVersion < 8 && !values.contains(.premiumLitter)
            ? 0 : try values.decode(Int.self, forKey: .premiumLitter)
        toys = try values.decode(Int.self, forKey: .toys)
        // Schema 1 saves predate movable furniture. Only an absent key migrates;
        // an explicit empty collection stays empty and malformed data still fails.
        if values.contains(.furniture) {
            var items = try values.nestedUnkeyedContainer(forKey: .furniture)
            furniture = []
            while !items.isAtEnd {
                furniture.append(try FurnitureItem(from: items.superDecoder(), schemaVersion: schemaVersion))
            }
        } else if schemaVersion < 15 {
            furniture = FurnitureCatalog.defaultItems
        } else { throw SaveRepositoryError.invalidSnapshot }
        gifts = schemaVersion < 7 && !values.contains(.gifts)
            ? [:] : try values.decode([String: Int].self, forKey: .gifts)
        guard validGifts else { throw SaveRepositoryError.invalidSnapshot }
    }
}

/// Top-left-origin coordinates in 0...1. The containing field defines the space:
/// bowlPosition is scene-relative; furniture positions use the source artwork.
public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct HomeState: Codable, Equatable, Sendable {
    /// nil uses the localized default title; custom names remain player text.
    public var name: String?
    /// Ground-floor bowl, kept under its original key for save migration.
    public var bowlPosition: NormalizedPoint
    public var upperBowlPosition: NormalizedPoint?
    public var comfortScore: Int
    public var furniture: [FurniturePlacement]
    public var roomLevel: Int

    public init(bowlPosition: NormalizedPoint = .init(x: 0.76, y: 0.79),
                comfortScore: Int = 30,
                furniture: [FurniturePlacement] = FurnitureCatalog.defaultPlacements,
                name: String? = nil, roomLevel: Int = 1,
                upperBowlPosition: NormalizedPoint? = nil) {
        self.name = name
        self.bowlPosition = bowlPosition
        self.comfortScore = comfortScore
        self.furniture = furniture
        self.roomLevel = roomLevel
        self.upperBowlPosition = upperBowlPosition
            ?? (HomeCatalog.level(roomLevel)?.floors.contains(.upper) == true ? Self.defaultBowlPosition : nil)
    }

    public static let defaultBowlPosition = NormalizedPoint(x: 0.76, y: 0.79)
    public var availableFloors: [HomeFloor] { HomeCatalog.level(roomLevel)?.floors ?? [] }
    public func placements(on floor: HomeFloor) -> [FurniturePlacement] { furniture.filter { $0.floor == floor } }
    public func bowlPosition(on floor: HomeFloor) -> NormalizedPoint? {
        guard availableFloors.contains(floor) else { return nil }
        return floor == .ground ? bowlPosition : upperBowlPosition
    }

    @discardableResult
    public mutating func setBowlPosition(_ position: NormalizedPoint, on floor: HomeFloor) -> Bool {
        guard availableFloors.contains(floor), GameSnapshot.isUnitPosition(position) else { return false }
        if floor == .ground { bowlPosition = position } else { upperBowlPosition = position }
        return true
    }

    var hasValidFloors: Bool {
        guard !availableFloors.isEmpty,
              furniture.allSatisfy({ availableFloors.contains($0.floor) }) else { return false }
        if availableFloors.contains(.upper) {
            return upperBowlPosition.map(GameSnapshot.isUnitPosition) ?? false
        }
        return upperBowlPosition == nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, bowlPosition, upperBowlPosition, comfortScore, furniture, roomLevel
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A missing or invalid display preference must not recover an older
        // backup and lose otherwise valid cats, supplies or room placements.
        name = (try? values.decode(String.self, forKey: .name)).flatMap(HomeNameRules.normalized)
        bowlPosition = try values.decode(NormalizedPoint.self, forKey: .bowlPosition)
        comfortScore = try values.decode(Int.self, forKey: .comfortScore)
        if values.contains(.furniture) {
            var placements = try values.nestedUnkeyedContainer(forKey: .furniture)
            furniture = []
            while !placements.isAtEnd {
                furniture.append(try FurniturePlacement(from: placements.superDecoder(), schemaVersion: schemaVersion))
            }
        } else if schemaVersion < 15 {
            furniture = schemaVersion < 13 ? FurnitureCatalog.legacyPlacementsV6 : FurnitureCatalog.defaultPlacements
        } else { throw SaveRepositoryError.invalidSnapshot }
        // Unlike cosmetic names, purchased room progress must not be silently
        // reset. Only an absent field belongs to the schema-1 migration.
        roomLevel = schemaVersion < 15 && !values.contains(.roomLevel)
            ? 1 : try values.decode(Int.self, forKey: .roomLevel)
        upperBowlPosition = try values.decodeIfPresent(NormalizedPoint.self, forKey: .upperBowlPosition)
        guard hasValidFloors,
              schemaVersion >= 10 || ((1...3).contains(roomLevel) && upperBowlPosition == nil)
        else { throw SaveRepositoryError.invalidSnapshot }
    }
}

public struct SaveMetadata: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var lastSyncAt: Date

    public init(createdAt: Date, lastSyncAt: Date) {
        self.createdAt = createdAt
        self.lastSyncAt = lastSyncAt
    }
}
