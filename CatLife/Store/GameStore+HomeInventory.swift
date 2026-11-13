import CatGameCore

extension GameStore {
    var homeLayoutRules: HomeLayoutRules {
        #if os(macOS)
        .macDesktop
        #else
        .standard
        #endif
    }

    func totalFurnitureCapacity(for home: HomeLevel) -> Int { home.capacity(using: homeLayoutRules) }
    func floorFurnitureCapacity(for home: HomeLevel) -> Int { home.floorCapacity(using: homeLayoutRules) }
    func furnitureCapacity(on floor: HomeFloor) -> Int {
        HomeCatalog.level(snapshot?.home.roomLevel ?? 1)?.capacity(on: floor, rules: homeLayoutRules) ?? 0
    }

    /// Current-floor drafts override only their floor; items on the other floor stay placed.
    func furnitureFloor(for itemID: String) -> HomeFloor? {
        if sceneSnapshot?.home.furniture.contains(where: { $0.itemID == itemID }) == true {
            return visibleHomeFloor
        }
        return snapshot?.home.furniture.first { $0.itemID == itemID && $0.floor != visibleHomeFloor }?.floor
    }

    var totalPlacedFurnitureCount: Int {
        placedFurnitureCount + (snapshot?.home.furniture.filter { $0.floor != visibleHomeFloor }.count ?? 0)
    }

    func availableFurnitureSlots(on floor: HomeFloor) -> Int {
        guard let snapshot, let room = HomeCatalog.level(snapshot.home.roomLevel) else { return 0 }
        let placed = floor == visibleHomeFloor ? placedFurnitureCount : snapshot.home.placements(on: floor).count
        return max(0, min(room.capacity(on: floor, rules: homeLayoutRules) - placed,
                          totalFurnitureCapacity(for: room) - totalPlacedFurnitureCount))
    }

    var availableFurnitureFloor: HomeFloor? {
        if canPlaceMoreFurniture { return visibleHomeFloor }
        return snapshot?.home.availableFloors.first { availableFurnitureSlots(on: $0) > 0 }
    }

    var furniturePurchaseActionKey: String {
        if let floor = availableFurnitureFloor {
            return floor == visibleHomeFloor ? "shop.design.decorate" : "homeInventory.arrange.\(floor.rawValue)"
        }
        return canUpgradeHome ? "shop.design.upgrade" : "shop.design.makeRoom"
    }

    var furnitureCapacityNotice: String {
        if let floor = availableFurnitureFloor, floor != visibleHomeFloor {
            return GameStrings.format("homeInventory.space.\(floor.rawValue)", availableFurnitureSlots(on: floor))
        }
        if snapshot?.home.availableFloors.count == 2 {
            return GameStrings.text(canUpgradeHome ? "homeInventory.full.upgrade" : "homeInventory.full.store")
        }
        return canUpgradeHome ? GameStrings.text("homeUpgrade.capacityReached")
            : GameStrings.format("room.capacityReachedMax", furnitureCapacity)
    }

    @discardableResult
    func arrangeInventoryFurniture(id: String) async -> Bool {
        guard !isBusy, !isSavingLayout, !isResolvingLayout, !isChangingHomeFloor,
              !saveTransferInProgress,
              snapshot?.inventory.furniture.contains(where: { $0.id == id }) == true else { return false }
        let placedFloor = furnitureFloor(for: id)
        guard let target = placedFloor ?? availableFurnitureFloor else { return false }
        let generation = saveSceneGeneration
        let sourceSheet = activeSheet
        let sourceSettings = isShowingSettings
        let purchaseID = furniturePurchaseItemID
        if target != visibleHomeFloor {
            guard !isDecorating else { return false }
            await changeHomeFloor(to: target)
        }
        guard generation == saveSceneGeneration, target == visibleHomeFloor,
              !isBusy, !saveTransferInProgress, activeSheet == sourceSheet, isShowingSettings == sourceSettings,
              furniturePurchaseItemID == purchaseID,
              furnitureFloor(for: id) == placedFloor,
              placedFloor != nil || canPlaceMoreFurniture else { return false }
        isShowingSettings = false
        activeSheet = nil
        beginDecorating()
        guard isDecorating else { return false }
        if placedFloor == nil {
            selectStoredFurniture(id: id)
            return selectedStoredFurnitureID == id
        }
        selectFurniture(id: id)
        return selectedFurnitureID == id
    }
}
