#if os(macOS)
import AppKit
import SwiftUI
import CatGameCore

@MainActor
struct MacBuildView: View {
    let store: GameStore
    let scene: RoomScene
    let preferences: MacPreferences
    let isActive: Bool
    var onDone: () -> Void
    var onRestRequest: ((String) -> Void)?
    var onContextAction: ((MacRoomContextAction) -> Void)?
    var onFixedStructure: ((MacRoomStructure) -> Void)?
    @State private var query = ""
    @State private var filter = "all"
    @State private var confirmsCancel = false
    @FocusState private var searchFocused: Bool

    private var placedIDs: Set<String> { Set(store.draftFurniture?.map(\.itemID) ?? []) }
    private var storedIDs: Set<String> { Set(store.storedFurniture.map(\.id)) }
    private var items: [FurnitureItem] {
        (store.sceneSnapshot?.inventory.furniture ?? []).filter { item in
            guard placedIDs.contains(item.id) || storedIDs.contains(item.id) else { return false }
            let wall = FurnitureCatalog.metadata(for: item.kind).isWall
            return (filter == "all" || filter == "bag" && storedIDs.contains(item.id) || filter == "wall" && wall || filter == "floor" && !wall
                    || filter == "outing" && item.kind.isOutingDecor)
                && (query.isEmpty || GameStrings.furnitureName(item).localizedCaseInsensitiveContains(query))
        }.sorted { a, b in
            if storedIDs.contains(a.id) != storedIDs.contains(b.id) { return storedIDs.contains(a.id) }
            return a.id < b.id
        }
    }
    private var selected: FurnitureItem? { store.selectedFurniture }
    private var selectedPosition: NormalizedPoint? {
        if let id = store.selectedFurnitureID { return store.draftFurniture?.first { $0.itemID == id }?.position }
        return store.arrangement68.bowlSelected ? store.draftBowlPosition : nil
    }
    /// Display-only grid cells of the wide room; saves keep their normalized coordinates.
    private var selectedCell: CGPoint? {
        guard let point = selectedPosition else { return nil }
        let grid = scene.arrangementGrid68
        // Furniture is normalized to the aspect-filled artwork; the bowl to the full scene size.
        let size = grid.transform.sceneSize
        let world = store.selectedFurnitureID == nil
            ? CGPoint(x: size.width * point.x, y: size.height * (1 - point.y)) : grid.transform.point(point)
        var cell = grid.gridPoint(world: world)
        // Wall pieces live on the back wall, so only their position along it is meaningful.
        if selectedIsWall, let model = MacRoomReservations.projection(transform: grid.transform), model.logicalBounds.width > 0 {
            cell = CGPoint(x: (world.x - model.logicalBounds.minX) / model.logicalBounds.width * MacRoomProjection.columns, y: 0)
        }
        guard cell.x.isFinite, cell.y.isFinite else { return nil }
        return CGPoint(x: min(MacRoomProjection.columns, max(0, cell.x)), y: min(MacRoomProjection.rows, max(0, cell.y)))
    }
    private var selectedIsWall: Bool { selected.map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false }
    private func cellValue(_ key: String, _ value: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(GameStrings.text(key)).foregroundStyle(RoomTheme.secondary)
            Text(String(format: "%.1f", value)).font(.system(size: 13.5, weight: .heavy, design: .rounded)).monospacedDigit()
        }.font(.system(size: 11.5, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 9))
    }
    private var canSave: Bool {
        store.canEditArrangement68 && !store.arrangement68.hasInvalidPlacement
    }
    var body: some View {
        VStack(spacing: 10) {
            toolbar
            HStack(spacing: 10) {
                catalog.frame(width: 248)
                stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: 236)
            }
        }
        .padding(12).foregroundStyle(RoomTheme.ink)
        .background(RoomTheme.cream)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .onChange(of: store.isDecorating) { _, editing in if !editing { onDone() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacSearchRequested"))) { _ in searchFocused = true }
        .alert(GameStrings.text("mac.build.discardTitle"), isPresented: $confirmsCancel) {
            Button(GameStrings.text("layout.cancel"), role: .cancel) {}
            Button(GameStrings.text("mac.build.discard"), role: .destructive) { discard() }
        } message: { Text(GameStrings.text("mac.build.discardBody")) }
        .accessibilityIdentifier("macBuildView")
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: 2))
            .compositingGroup()
    }
    private var catalog: some View {
        card {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Label(GameStrings.text("mac.build.furniture"), systemImage: "backpack.fill").font(.system(size: 14, weight: .heavy, design: .rounded))
                    Spacer(minLength: 4)
                    Text(GameStrings.format("build68.capacity", store.placedFurnitureCount, store.furnitureCapacity))
                        .font(.system(size: 10.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(RoomTheme.paleMint, in: Capsule())
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(RoomTheme.secondary)
                    TextField(GameStrings.text("mac.build.search"), text: $query).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityIdentifier("macBuildSearch")
                    Text(preferences.binding(for: .search).label).font(.caption2.monospaced()).foregroundStyle(RoomTheme.secondary)
                }.font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 7)
                    .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 10))
                filterChips
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(items) { item in catalogItem(item) }
                    }.padding(1)
                    if items.isEmpty { Text(GameStrings.text("mac.build.noResults")).font(.caption).foregroundStyle(RoomTheme.secondary).padding(.top, 24) }
                }.scrollIndicators(.never)
                Text(GameStrings.text("mac.build.dragHint")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(11)
        }
    }
    private var filterChips: some View {
        HStack(spacing: 2) {
            ForEach(["all", "floor", "wall", "bag", "outing"], id: \.self) { option in
                let isOn = filter == option
                Button { filter = option } label: {
                    Text(GameStrings.text("mac.build.filter." + option)).font(.system(size: 11.5, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(isOn ? .white : RoomTheme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(isOn ? RoomTheme.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }.padding(3).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain).accessibilityLabel(GameStrings.text("mac.build.filter"))
    }
    private func catalogItem(_ item: FurnitureItem) -> some View {
        let inBag = storedIDs.contains(item.id)
        let isSelected = store.selectedFurnitureID == item.id || store.selectedStoredFurnitureID == item.id
        return VStack(spacing: 2) {
            GameIcon(asset: FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                placement: store.draftFurniture?.first { $0.itemID == item.id }), symbol: "sofa.fill", size: 48)
                .frame(maxWidth: .infinity, minHeight: 54)
                .overlay(alignment: .topTrailing) {
                    if inBag {
                        Image(systemName: "backpack.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(3).background(RoomTheme.mint, in: Circle())
                    }
                }
            Text(GameStrings.furnitureName(item)).font(.system(size: 10.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            Text(GameStrings.text(inBag ? "mac.build.inBag" : "mac.build.placed") + (inBag ? "" : " · " + (store.visibleHomeFloor == .ground ? "1F" : "2F")))
                .font(.system(size: 9, weight: .bold)).foregroundStyle(inBag ? RoomTheme.darkMint : RoomTheme.secondary).lineLimit(1)
        }.padding(.horizontal, 4).padding(.vertical, 5).frame(maxWidth: .infinity)
            .background(isSelected ? RoomTheme.paleMint : inBag ? RoomTheme.paleMint.opacity(0.3) : RoomTheme.cream.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? RoomTheme.mint : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .help(GameStrings.furnitureName(item))
            .onTapGesture(count: 2) {
                if inBag { store.placeFurniture(id: item.id) }
                else { store.focusArrangementFurniture68(id: item.id) }
            }
            .onTapGesture {
                if inBag { store.selectStoredFurniture(id: item.id) }
                else { store.focusArrangementFurniture68(id: item.id) }
            }
            .onDrag { inBag && store.canEditArrangement68 ? NSItemProvider(object: item.id as NSString) : NSItemProvider() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(GameStrings.text(inBag ? "mac.build.placeHint" : "mac.build.focusHint"))
            .accessibilityAction {
                if inBag { store.placeFurniture(id: item.id) } else { store.focusArrangementFurniture68(id: item.id) }
            }
            .accessibilityIdentifier("macBuildItem_" + item.id)
    }
    private var stage: some View {
        // The toolbar sits above the stage now, so the room only keeps clear of the slim bottom bar.
        GeometryReader { geometry in
            MacRoomCanvas(store: store, scene: scene, isActive: isActive && !confirmsCancel && !store.isSavingLayout,
                frameLimit: preferences.frameLimit, wheelReversed: preferences.wheelReversed,
                contextMenus: preferences.contextMenus, hoverHints: preferences.hoverHints,
                isDaylight: !preferences.followDaylight || !MacTitleMetricsV2.isNight(at: store.now),
                usableRect: CGRect(x: 18, y: 16, width: max(1, geometry.size.width - 36), height: max(1, geometry.size.height - 74)),
                onRestRequest: onRestRequest, onContextAction: onContextAction, onFixedStructure: onFixedStructure)
        }
            .id(store.saveSceneGeneration.uuidString + ":build:" + store.visibleHomeFloor.rawValue)
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    Text(GameStrings.format("mac.build.stageHint", preferences.binding(for: .rotateRight).label, preferences.binding(for: .putAway).label))
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.leading, 6)
                    Spacer(minLength: 4)
                    viewControls
                }.padding(4).background(.regularMaterial, in: Capsule()).padding(10)
            }
            .background(RoomTheme.paleMint.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: 2).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
    }
    private var toolbar: some View {
        // Narrow windows or longer English labels fall back to the status on its own line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { historyControls; Spacer(minLength: 6); saveStatus; Spacer(minLength: 6); closingControls }
            VStack(spacing: 5) { HStack(spacing: 8) { historyControls; Spacer(minLength: 6); closingControls }; saveStatus }
        }.padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 2))
    }
    private var historyControls: some View {
        HStack(spacing: 6) {
            labelled(GameStrings.text("mac.build.v2.undo"), symbol: "arrow.uturn.backward", key: .undo) { store.undoArrangement68() }
                .disabled(!store.canEditArrangement68 || !store.arrangement68.canUndo).accessibilityIdentifier("macBuildUndo")
            tool("arrow.uturn.forward", .redo) { store.redoArrangement68() }
                .disabled(!store.canEditArrangement68 || !store.arrangement68.canRedo)
            labelled(GameStrings.text("build68.snap"), symbol: "square.grid.2x2.fill", key: .grid, active: store.arrangement68.snapEnabled) {
                store.arrangement68.snapEnabled.toggle()
            }.disabled(!store.canEditArrangement68).accessibilityIdentifier("macBuildGrid")
        }
    }
    private func labelled(_ title: String, symbol: String, key: MacCommand, active: Bool = false, prominent: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol); Text(title).lineLimit(1)
                Text(preferences.binding(for: key).label).font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(active || prominent ? RoomTheme.darkMint : RoomTheme.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            }.font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(active || prominent ? .white : RoomTheme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(active || prominent ? RoomTheme.mint : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).fixedSize()
    }
    private var saveStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(store.hasUnsavedLayoutChanges ? RoomTheme.coral : RoomTheme.mint).frame(width: 7, height: 7)
            Text(GameStrings.text(store.isSavingLayout ? "mac.build.saving" : store.hasUnsavedLayoutChanges ? "build68.dirty" : "mac.build.editing"))
                .lineLimit(1).minimumScaleFactor(0.8)
        }.font(.system(size: 11.5, weight: .bold)).foregroundStyle(store.hasUnsavedLayoutChanges ? RoomTheme.coralDeep : RoomTheme.secondary)
            .accessibilityElement(children: .combine)
    }
    private var closingControls: some View {
        HStack(spacing: 6) {
            labelled(GameStrings.text("layout.cancel"), symbol: "xmark", key: .escape) { requestCancel() }
                .disabled(store.isSavingLayout || store.isBusy).accessibilityIdentifier("macBuildCancel")
            labelled(GameStrings.text("layout.done"), symbol: "checkmark", key: .save, prominent: true) { store.finishDecorating() }
                .disabled(!canSave).opacity(canSave ? 1 : 0.55).accessibilityIdentifier("macBuildSave")
        }
    }
    private var viewControls: some View {
        HStack(spacing: 4) {
            Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24).contentShape(Rectangle()) }
                .disabled(!scene.canChangeRoomView || scene.roomViewAngle == .left)
            Text(GameStrings.text("roomView.angle." + (scene.roomViewAngle == .left ? "left" : scene.roomViewAngle == .right ? "right" : "front")))
                .font(.system(size: 11, weight: .bold)).frame(minWidth: 56)
            Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24).contentShape(Rectangle()) }
                .disabled(!scene.canChangeRoomView || scene.roomViewAngle == .right)
            Button { scene.showWholeRoom() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 24, height: 24).contentShape(Rectangle()) }
                .help(GameStrings.text("mac.build.wholeRoom")).accessibilityLabel(GameStrings.text("mac.build.wholeRoom"))
        }.font(.system(size: 11, weight: .bold)).buttonStyle(.plain).padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoomTheme.paper, in: Capsule())
    }
    private var inspector: some View {
        card {
            ScrollView { inspectorContent }.scrollIndicators(.never)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    @ViewBuilder private var inspectorContent: some View {
        if store.arrangementSelection68 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    GameIcon(asset: selected.map { item in FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                        placement: store.draftFurniture?.first { $0.itemID == item.id }) } ?? "bowl-empty", symbol: "sofa.fill", size: 62)
                        .frame(width: 76, height: 76).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.selectedFurnitureName).font(.system(size: 15, weight: .heavy, design: .rounded))
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Text(dimensions).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                orientationControls
                positionControls
                if let issue = store.selectedArrangementIssue68 {
                    Label(store.arrangementIssueText68(issue), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Button { store.storeSelectedFurniture() } label: {
                        Label(GameStrings.text("layout.storeFurniture"), systemImage: "backpack.fill").lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.regular).tint(RoomTheme.coralDeep)
                        .disabled(!store.canEditArrangement68 || !store.canStoreSelectedFurniture).accessibilityIdentifier("macBuildPutAway")
                    Button { store.confirmArrangementSelection68() } label: {
                        Text(GameStrings.text(store.selectedArrangementIssue68 == nil ? "build68.placeHere" : "build68.invalid"))
                            .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.regular).tint(RoomTheme.mint)
                        .disabled(!store.canEditArrangement68 || store.selectedArrangementIssue68 != nil).accessibilityIdentifier("macBuildConfirm")
                }.padding(.top, 2)
            }.padding(11)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(GameStrings.text("mac.build.pickFurniture"), systemImage: "hand.point.up.left.fill")
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(RoomTheme.ink)
                Text(GameStrings.text("mac.build.pickHint")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(GameStrings.text("mac.build.v2.placedHere"), systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).padding(.top, 6)
                VStack(spacing: 4) {
                    ForEach(placedOnFloor, id: \.id) { item in
                        Button { store.selectFurniture(id: item.id) } label: {
                            HStack(spacing: 8) {
                                GameIcon(asset: FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                                    placement: store.draftFurniture?.first { $0.itemID == item.id }), symbol: "cube.fill", size: 24)
                                    .frame(width: 30, height: 30).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 8))
                                Text(GameStrings.text(FurnitureCatalog.metadata(for: item.kind).nameKey)).font(.system(size: 12, weight: .bold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(GameStrings.text("build68.facing." + (store.draftFurnitureOrientations?[item.id] ?? item.orientation).rawValue))
                                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                            }.padding(5).background(RoomTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(!store.canEditArrangement68)
                    }
                }
            }.padding(11)
        }
    }
    private var placedOnFloor: [FurnitureItem] {
        let placements = store.draftFurniture ?? store.snapshot?.home.furniture ?? []
        let ids = placements.filter { $0.floor == store.visibleHomeFloor }.map(\.itemID)
        let items = store.snapshot?.inventory.furniture ?? []
        return ids.compactMap { id in items.first { $0.id == id } }
    }
    private var dimensions: String {
        guard let selected else { return GameStrings.text("build68.bowlFixed") }
        let metadata = FurnitureCatalog.metadata(for: selected.kind)
        if metadata.isWall { return GameStrings.text("build68.wallPlacement") }
        let footprint = FurnitureCatalog.footprint(for: selected)
        return GameStrings.format("build68.dimensions", footprint.width, footprint.depth, metadata.height)
    }
    private var orientationControls: some View {
        let rotates = selected?.kind.supportsRotation == true
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                tool("arrow.counterclockwise", .rotateLeft) { store.rotateSelectedFurniture68(clockwise: false) }
                VStack(spacing: 3) {
                    Text(GameStrings.text("mac.build.facing")).font(.system(size: 10, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    Text(GameStrings.text("build68.facing." + (selected?.orientation.rawValue ?? "front")))
                        .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(rotates ? RoomTheme.darkMint : RoomTheme.secondary)
                }.frame(maxWidth: .infinity)
                tool("arrow.clockwise", .rotateRight) { store.rotateSelectedFurniture68(clockwise: true) }
            }.disabled(!store.canEditArrangement68 || !rotates)
            if !rotates {
                Text(GameStrings.text(selected == nil ? "layout.bowlCannotFlip" : "layout.wallCannotFlip"))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            }
        }.padding(8).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 13))
    }
    private var positionControls: some View {
        VStack(spacing: 7) {
            HStack {
                Text(GameStrings.text("mac.build.position")); Spacer()
                Text(GameStrings.text(store.arrangement68.snapEnabled ? "build68.nudgeHalf" : "build68.nudgeFine"))
            }.font(.system(size: 10, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            if let cell = selectedCell {
                HStack(spacing: 6) {
                    cellValue("mac.build.v2.across", cell.x)
                    if !selectedIsWall { cellValue("mac.build.v2.depth", cell.y) }
                }
            }
            HStack(spacing: 6) {
                tool("arrow.left", .nudgeLeft) { store.nudgeSelectedFurniture68(dx: -1, dy: 0) }
                tool("arrow.up", .nudgeUp) { store.nudgeSelectedFurniture68(dx: 0, dy: -1) }
                tool("arrow.down", .nudgeDown) { store.nudgeSelectedFurniture68(dx: 0, dy: 1) }
                tool("arrow.right", .nudgeRight) { store.nudgeSelectedFurniture68(dx: 1, dy: 0) }
            }.disabled(!store.canEditArrangement68)
        }.padding(8).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 13))
    }
    private func tool(_ symbol: String, _ command: MacCommand, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .bold)).frame(width: 30, height: 28)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help(GameStrings.text(command.titleKey) + " · " + preferences.binding(for: command).label)
            .accessibilityLabel(GameStrings.text(command.titleKey)).accessibilityIdentifier("macBuild_" + command.rawValue)
    }
    private func turn(_ direction: Int) {
        scene.turnRoomView(by: direction)
        store.arrangement68.previewAngle = scene.roomViewAngle
    }
    private func requestCancel() {
        if store.hasUnsavedLayoutChanges { confirmsCancel = true } else { discard() }
    }
    private func discard() { store.cancelDecorating() }
}
#endif
