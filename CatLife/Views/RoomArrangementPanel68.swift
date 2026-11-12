import SwiftUI
import CatGameCore

@MainActor
struct ArrangementHeader68: View {
    let store: GameStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 5) { title; HStack { cancel; Spacer(minLength: 12); done }; status }
            } else {
                HStack(spacing: 10) {
                    cancel
                    VStack(spacing: 3) { title; status }.frame(maxWidth: .infinity)
                    done
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 8).background(RoomTheme.cream)
            .accessibilityElement(children: .contain).accessibilityIdentifier("arrangementHeader68")
    }
    private var status: some View {
        Label(GameStrings.text(store.hasUnsavedLayoutChanges ? "build68.dirty" : "build68.instructions"),
              systemImage: store.hasUnsavedLayoutChanges ? "circle.fill" : "hand.draw")
            .font(.caption2.weight(.semibold)).foregroundStyle(store.hasUnsavedLayoutChanges ? RoomTheme.coralDeep : RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
            .accessibilityIdentifier(store.hasUnsavedLayoutChanges ? "layoutUnsavedChanges" : "arrangementInstructions68")
    }
    private var title: some View {
        Text(GameStrings.format("build68.title", store.visibleHomeFloor == .ground ? "1F" : "2F"))
            .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }
    private var cancel: some View {
        Button { store.cancelDecorating(); store.activeSheet = nil } label: {
            Text(GameStrings.text("layout.cancel")).font(.subheadline.weight(.bold)).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).disabled(store.isSavingLayout).accessibilityIdentifier("layoutCancelButton")
    }
    private var done: some View {
        Button { store.finishDecorating() } label: {
            Text(GameStrings.text("layout.done")).font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                .frame(minWidth: 52, minHeight: 44).padding(.horizontal, 8).background(RoomTheme.mint, in: Capsule())
        }.buttonStyle(.plain)
            .disabled(store.isBusy || store.isResolvingLayout || store.placingFurnitureID != nil || store.arrangement68.pendingRequest != nil || store.arrangement68.hasInvalidPlacement)
            .accessibilityIdentifier("layoutDoneButton")
    }
}

@MainActor
struct ArrangementStageTools68: View {
    let store: GameStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 3) { HStack { capacity; Spacer(minLength: 8); undo }; snapping.toggleStyle(.switch) }
            } else {
                HStack(spacing: 8) { capacity; Spacer(minLength: 2); snapping.toggleStyle(.button); Spacer(minLength: 2); undo }
            }
        }.padding(.horizontal, 10).padding(.vertical, 2).background(RoomTheme.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(RoomTheme.ink).accessibilityElement(children: .contain)
            .accessibilityIdentifier("arrangementStageTools68")
    }
    private var capacity: some View {
        Text(GameStrings.format("build68.capacity", store.placedFurnitureCount, store.furnitureCapacity))
            .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("arrangementCapacity68")
    }
    private var undo: some View {
        Button { store.undoArrangement68() } label: {
            Label(GameStrings.text("build68.undo"), systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
            .disabled(!store.canEditArrangement68 || !store.arrangement68.canUndo)
            .accessibilityIdentifier("arrangementUndo68")
    }
    private var snapping: some View {
        Toggle(isOn: Binding(get: { store.arrangement68.snapEnabled }, set: { store.arrangement68.snapEnabled = $0 })) {
            Label(GameStrings.text("build68.snap"), systemImage: "square.grid.3x3")
                .font(.caption.weight(.bold)).fixedSize(horizontal: false, vertical: true)
        }.tint(RoomTheme.mint).frame(minHeight: 44)
            .disabled(!store.canEditArrangement68).accessibilityIdentifier("arrangementSnap68")
    }

}

@MainActor
struct RoomArrangementPanel: View {
    let store: GameStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var selected: FurnitureItem? { store.selectedFurniture }
    private var selectedName: String { selected.map(GameStrings.furnitureName) ?? GameStrings.text("layout.bowl") }
    private var collapsed: Bool { !store.isFurnitureTrayExpanded }
    private var currentIDs: Set<String> { Set(store.draftFurniture?.map(\.itemID) ?? []) }
    private var storedIDs: Set<String> { Set(store.storedFurniture.map(\.id)) }
    private var trayItems: [FurnitureItem] {
        (store.sceneSnapshot?.inventory.furniture ?? []).filter { item in
            guard currentIDs.contains(item.id) || storedIDs.contains(item.id) else { return false }
            switch store.arrangement68.filter {
            case .floor: return !FurnitureCatalog.metadata(for: item.kind).isWall
            case .wall: return FurnitureCatalog.metadata(for: item.kind).isWall
            case .bag: return storedIDs.contains(item.id)
            }
        }.sorted { a, b in
            if storedIDs.contains(a.id) != storedIDs.contains(b.id) { return storedIDs.contains(a.id) }
            return a.id < b.id
        }
    }
    var body: some View {
        VStack(spacing: 4) {
            Button { store.isFurnitureTrayExpanded.toggle() } label: {
                Label(GameStrings.text(collapsed ? "layout.showTray" : "layout.hideTray"), systemImage: collapsed ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("layoutTrayToggle")
                .accessibilityValue(collapsed ? "collapsed" : "expanded")
            if !collapsed {
                ScrollView {
                    if store.arrangementSelection68 { adjustment }
                    else { tray }
                }.scrollBounceBehavior(.basedOnSize)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : (store.arrangementSelection68 ? 154 : 208))
                    .accessibilityIdentifier("arrangementPanelScroll68")
                if store.arrangementSelection68 { confirmPlacement }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
        .background(RoomTheme.cream.opacity(0.98), in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .background { GeometryReader { geometry in
            Color.clear.preference(key: ArrangementPanelHeightKey.self, value: geometry.size.height)
        } }
        .accessibilityElement(children: .contain).accessibilityIdentifier("arrangementPanel68")
    }

    private var adjustment: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                GameIcon(asset: selected.map { item in FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                    placement: store.draftFurniture?.first { $0.itemID == item.id }) } ?? "bowl-empty", symbol: "sofa.fill", size: 42)
                    .padding(3).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 15)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedName).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("selectedFurnitureName").accessibilityValue(selectedName)
                    Text(dimensions).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.storeSelectedFurniture() } label: {
                    Image(systemName: "backpack.fill").font(.system(size: 19, weight: .bold)).frame(width: 44, height: 44)
                        .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
                    .disabled(!store.canStoreSelectedFurniture || !store.canEditArrangement68)
                    .accessibilityLabel(GameStrings.text("layout.storeFurniture")).accessibilityIdentifier("storeFurnitureButton")
            }
            if dynamicTypeSize.isAccessibilitySize {
                rotation
                nudgeCard
            } else {
                HStack(alignment: .top, spacing: 8) {
                    rotation.frame(maxWidth: .infinity)
                    nudgeCard.frame(width: 184)
                }
            }
            if let issue = store.selectedArrangementIssue68 {
                Text(store.arrangementIssueText68(issue)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("arrangementInvalidReason68")
            }
        }.padding(.bottom, 5)
    }
    private var confirmPlacement: some View {
        Button { store.confirmArrangementSelection68() } label: {
            Text(GameStrings.text(store.selectedArrangementIssue68 == nil ? "build68.placeHere" : "build68.invalid"))
                .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
        }.buttonStyle(MintButtonStyle()).disabled(!store.canEditArrangement68 || store.selectedArrangementIssue68 != nil)
            .accessibilityIdentifier("layoutConfirmPlacement68")
    }
    private var nudgeCard: some View {
        VStack(spacing: 3) {
            Text(GameStrings.text(store.arrangement68.snapEnabled ? "build68.nudgeHalf" : "build68.nudgeFine"))
                .font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    nudge("up", symbol: "arrow.up", dx: 0, dy: -1).frame(width: 44)
                    HStack(spacing: 0) {
                        nudge("left", symbol: "arrow.left", dx: -1, dy: 0)
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                        nudge("right", symbol: "arrow.right", dx: 1, dy: 0)
                    }
                    nudge("down", symbol: "arrow.down", dx: 0, dy: 1).frame(width: 44)
                }.frame(maxWidth: 176)
            } else {
                HStack(spacing: 0) {
                    nudge("left", symbol: "arrow.left", dx: -1, dy: 0)
                    nudge("up", symbol: "arrow.up", dx: 0, dy: -1)
                    nudge("down", symbol: "arrow.down", dx: 0, dy: 1)
                    nudge("right", symbol: "arrow.right", dx: 1, dy: 0)
                }
            }
        }.padding(4).frame(maxWidth: .infinity).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
    }
    private var dimensions: String {
        guard let selected else { return GameStrings.text("build68.bowlFixed") }
        let metadata = FurnitureCatalog.metadata(for: selected.kind)
        if metadata.isWall { return GameStrings.text("build68.wallPlacement") }
        let footprint = FurnitureCatalog.footprint(for: selected)
        return GameStrings.format("build68.dimensions", footprint.width, footprint.depth, metadata.height)
    }
    private var rotation: some View {
        VStack(spacing: 3) {
            if dynamicTypeSize.isAccessibilitySize {
                facingTitle
                HStack(spacing: 8) {
                    rotate(clockwise: false)
                    Spacer(minLength: 0)
                    facingDots
                    Spacer(minLength: 0)
                    rotate(clockwise: true)
                }
            } else {
                facingSummary
                HStack(spacing: 8) { rotate(clockwise: false); Spacer(minLength: 0); rotate(clockwise: true) }
            }
            if selected?.kind.supportsRotation != true {
                Text(GameStrings.text(selected == nil ? "layout.bowlCannotFlip" : "layout.wallCannotFlip"))
                    .font(.caption2).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(6).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
    }
    private var facingSummary: some View {
        VStack(spacing: 3) { facingTitle; facingDots }.frame(maxWidth: .infinity)
    }
    private var facingTitle: some View {
        Text(GameStrings.text("build68.facing.\(selected?.orientation.rawValue ?? "front")")
             + " · \((FurnitureOrientation.allCases.firstIndex(of: selected?.orientation ?? .front) ?? 0) + 1)/\(FurnitureOrientation.allCases.count)")
            .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("layoutOrientationHint")
    }
    private var facingDots: some View {
        HStack(spacing: 6) {
            ForEach(FurnitureOrientation.allCases, id: \.self) { orientation in
                Circle().fill(selected?.orientation == orientation ? RoomTheme.mint : RoomTheme.track).frame(width: 8, height: 8)
            }
        }.accessibilityHidden(true)
    }
    private func rotate(clockwise: Bool) -> some View {
        Button {
            if selected?.kind.supportsRotation == true { store.rotateSelectedFurniture68(clockwise: clockwise) }
            else { store.showFurnitureNotice(selected == nil ? "layout.bowlCannotFlip" : "layout.wallCannotFlip") }
        } label: {
            Image(systemName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise").font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected?.kind.supportsRotation == true ? RoomTheme.darkMint : RoomTheme.secondary.opacity(0.45))
            .disabled(!store.canEditArrangement68).accessibilityLabel(GameStrings.text(clockwise ? "build68.rotateRight" : "build68.rotateLeft"))
            .accessibilityIdentifier(clockwise ? "rotateFurnitureRight68" : "rotateFurnitureLeft68")
            .accessibilityValue(GameStrings.text("build68.facing.\(selected?.orientation.rawValue ?? "front")"))
    }
    private func nudge(_ name: String, symbol: String, dx: Int, dy: Int) -> some View {
        Button { store.nudgeSelectedFurniture68(dx: dx, dy: dy) } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).disabled(!store.canEditArrangement68)
            .accessibilityLabel(GameStrings.text("build68.nudge.\(name)"))
            .accessibilityIdentifier("nudgeFurniture68_\(name)")
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = store.storedFurniture.first(where: { $0.id == store.selectedStoredFurnitureID }) {
                Text(GameStrings.furnitureName(item)).font(.subheadline.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("selectedFurnitureName").accessibilityValue(GameStrings.furnitureName(item))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ArrangementFilter68.allCases, id: \.self) { filter in
                        Button { store.arrangement68.filter = filter } label: {
                            Text(GameStrings.text("build68.filter.\(filter.rawValue)"))
                                .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .foregroundStyle(store.arrangement68.filter == filter ? .white : RoomTheme.ink)
                                .background(store.arrangement68.filter == filter ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("arrangementFilter68_\(filter.rawValue)")
                            .accessibilityAddTraits(store.arrangement68.filter == filter ? .isSelected : [])
                    }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) { ForEach(trayItems) { item in trayItem(item) } }
                        .padding(.vertical, 3)
                }.accessibilityIdentifier("arrangementTray68")
                    .onChange(of: store.selectedStoredFurnitureID, initial: true) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
            }
            HStack(spacing: 12) {
                tool("layout.furnitureBag", id: "furnitureInventoryButton") { store.openFurnitureInventory() }
                tool("homeUpgrade.entry", id: "homeUpgradeButton") { store.openHomeUpgrade() }
                tool("tab.shop", id: "layoutShopButton") { store.activeSheet = .shop }
            }
        }
    }
    private func trayItem(_ item: FurnitureItem) -> some View {
        let stored = storedIDs.contains(item.id)
        let selectedInTray = store.selectedStoredFurnitureID == item.id
        let button = Button {
            if stored { store.placeFurniture(id: item.id) }
            else { store.focusArrangementFurniture68(id: item.id) }
        } label: {
            VStack(spacing: 5) {
                GameIcon(asset: FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                    placement: store.draftFurniture?.first { $0.itemID == item.id }), symbol: "sofa.fill", size: 42).accessibilityHidden(true)
                Text(GameStrings.furnitureName(item)).font(.caption2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text(stored ? GameStrings.format("build68.inBag", 1)
                     : GameStrings.format("build68.placedFloor", store.visibleHomeFloor == .ground ? "1F" : "2F"))
                    .font(.caption2.weight(.semibold)).foregroundStyle(stored ? RoomTheme.darkMint : RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(9).frame(width: dynamicTypeSize.isAccessibilitySize ? 148 : 94, alignment: .top)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(selectedInTray ? RoomTheme.darkMint : stored ? RoomTheme.mint : RoomTheme.track, lineWidth: selectedInTray ? 3 : 2))
        }.buttonStyle(.plain).id(item.id)
            .accessibilityIdentifier(stored ? "layoutStored_\(item.id)" : "layoutPlaced_\(item.id)")
            .accessibilityAddTraits(selectedInTray ? .isSelected : [])
            .disabled(!store.canEditArrangement68 || (stored && !store.canPlaceMoreFurniture))
        return Group {
            if stored {
                button.onDrag {
                    guard store.canEditArrangement68, store.canPlaceMoreFurniture else { return NSItemProvider() }
                    return NSItemProvider(object: item.id as NSString)
                }
            } else { button }
        }
    }
    private func tool(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(GameStrings.text(key)).font(.caption.weight(.bold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).disabled(!store.canEditArrangement68)
            .accessibilityIdentifier(id)
    }
}
