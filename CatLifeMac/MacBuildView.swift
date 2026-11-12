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
            return (filter == "all" || filter == "bag" && storedIDs.contains(item.id) || filter == "wall" && wall || filter == "floor" && !wall)
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
    private var canSave: Bool {
        store.canEditArrangement68 && !store.arrangement68.hasInvalidPlacement
    }
    var body: some View {
        HStack(spacing: 14) {
            catalog.frame(width: 270)
            stage.frame(maxWidth: .infinity, maxHeight: .infinity)
            inspector.frame(width: 270)
        }
        .padding(16).foregroundStyle(RoomTheme.ink)
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
    private var catalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(GameStrings.text("mac.build.furniture"), systemImage: "backpack.fill").font(.headline)
                Spacer(minLength: 4)
                Text(GameStrings.format("build68.capacity", store.placedFurnitureCount, store.furnitureCapacity))
                    .font(.caption).foregroundStyle(RoomTheme.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(RoomTheme.secondary)
                TextField(GameStrings.text("mac.build.search"), text: $query).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityIdentifier("macBuildSearch")
                Text(preferences.binding(for: .search).label).font(.caption.monospaced()).foregroundStyle(RoomTheme.secondary)
            }.padding(10).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
            MacSegmented(selection: $filter, options: ["all", "floor", "wall", "bag"].map { ($0, GameStrings.text("mac.build.filter." + $0)) })
                .accessibilityLabel(GameStrings.text("mac.build.filter"))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(items) { item in catalogItem(item) }
                }.padding(2)
                if items.isEmpty { Text(GameStrings.text("mac.build.noResults")).foregroundStyle(RoomTheme.secondary).padding(.top, 30) }
            }
            Text(GameStrings.text("mac.build.dragHint")).font(.caption).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(13).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2))
    }
    private func catalogItem(_ item: FurnitureItem) -> some View {
        let inBag = storedIDs.contains(item.id)
        let isSelected = store.selectedFurnitureID == item.id || store.selectedStoredFurnitureID == item.id
        return VStack(spacing: 5) {
            GameIcon(asset: FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                placement: store.draftFurniture?.first { $0.itemID == item.id }), symbol: "sofa.fill", size: 84)
                .frame(maxWidth: .infinity).padding(.vertical, 4).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            Text(GameStrings.furnitureName(item)).font(.caption.weight(.heavy)).lineLimit(2).multilineTextAlignment(.center)
            Text(GameStrings.text(inBag ? "mac.build.inBag" : "mac.build.placed") + (inBag ? "" : " · " + (store.visibleHomeFloor == .ground ? "1F" : "2F")))
                .font(.system(size: 10, weight: .bold)).foregroundStyle(inBag ? RoomTheme.darkMint : RoomTheme.secondary)
        }.padding(6).frame(maxWidth: .infinity, minHeight: 140)
            .background(isSelected ? RoomTheme.paleMint : inBag ? RoomTheme.paleMint.opacity(0.25) : RoomTheme.paper,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? RoomTheme.mint : RoomTheme.track, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
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
        MacRoomCanvas(store: store, scene: scene, isActive: isActive && !confirmsCancel && !store.isSavingLayout,
            frameLimit: preferences.frameLimit, wheelReversed: preferences.wheelReversed,
            contextMenus: preferences.contextMenus, hoverHints: preferences.hoverHints,
            isDaylight: !preferences.followDaylight || !MacTitleMetricsV2.isNight(at: store.now),
            onRestRequest: onRestRequest, onContextAction: onContextAction, onFixedStructure: onFixedStructure)
            .id(store.saveSceneGeneration.uuidString + ":build:" + store.visibleHomeFloor.rawValue)
            .overlay(alignment: .top) { toolbar.padding(14) }
            .overlay(alignment: .bottom) {
                HStack(spacing: 10) {
                    Text(GameStrings.format("mac.build.stageHint", preferences.binding(for: .rotateRight).label, preferences.binding(for: .putAway).label))
                        .font(.caption).foregroundStyle(RoomTheme.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    viewControls
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).padding(12)
            }
            .background(RoomTheme.paleMint.opacity(0.35), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white, lineWidth: 3).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .accessibilityElement(children: .contain)
    }
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { historyControls; Spacer(minLength: 4); saveStatus; Spacer(minLength: 4); closingControls }
            VStack(spacing: 8) { HStack { historyControls; Spacer(minLength: 4); closingControls }; saveStatus }
        }
    }
    private var historyControls: some View {
        HStack(spacing: 8) {
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
            HStack(spacing: 6) {
                Image(systemName: symbol); Text(title).lineLimit(1)
                Text(preferences.binding(for: key).label).font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(active || prominent ? RoomTheme.darkMint : RoomTheme.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
            }.font(.system(size: 13.5, weight: .heavy, design: .rounded))
                .foregroundStyle(active || prominent ? .white : RoomTheme.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(active || prominent ? RoomTheme.mint : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white, lineWidth: 2))
                .compositingGroup().shadow(color: (active || prominent ? RoomTheme.darkMint : RoomTheme.ink.opacity(0.12)), radius: 0, y: 3)
        }.buttonStyle(.plain).fixedSize()
    }
    private var saveStatus: some View {
        Text(GameStrings.text(store.isSavingLayout ? "mac.build.saving" : store.hasUnsavedLayoutChanges ? "build68.dirty" : "mac.build.editing"))
            .font(.caption.weight(.bold)).foregroundStyle(store.hasUnsavedLayoutChanges ? RoomTheme.coralDeep : RoomTheme.secondary)
            .lineLimit(2).multilineTextAlignment(.center)
    }
    private var closingControls: some View {
        HStack(spacing: 8) {
            labelled(GameStrings.text("layout.cancel"), symbol: "xmark.square.fill", key: .escape) { requestCancel() }
                .disabled(store.isSavingLayout || store.isBusy).accessibilityIdentifier("macBuildCancel")
            labelled(GameStrings.text("layout.done"), symbol: "checkmark.square.fill", key: .save, prominent: true) { store.finishDecorating() }
                .disabled(!canSave).opacity(canSave ? 1 : 0.55).accessibilityIdentifier("macBuildSave")
        }
    }
    private var viewControls: some View {
        HStack(spacing: 7) {
            Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                .disabled(!scene.canChangeRoomView || scene.roomViewAngle == .left)
            Text(GameStrings.text("roomView.angle." + (scene.roomViewAngle == .left ? "left" : scene.roomViewAngle == .right ? "right" : "front"))).font(.caption.weight(.bold)).frame(minWidth: 66)
            Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                .disabled(!scene.canChangeRoomView || scene.roomViewAngle == .right)
            Button { scene.showWholeRoom() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28) }
                .help(GameStrings.text("mac.build.wholeRoom"))
        }.buttonStyle(.plain).padding(5).background(RoomTheme.paper, in: Capsule())
    }
    private var inspector: some View {
        ScrollView { inspectorContent }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2))
    }
    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.arrangementSelection68 {
                GameIcon(asset: selected.map { item in FurnitureArtwork68.assetName(for: item, angle: store.arrangement68.previewAngle,
                    placement: store.draftFurniture?.first { $0.itemID == item.id }) } ?? "bowl-empty", symbol: "sofa.fill", size: 190)
                    .frame(maxWidth: .infinity, minHeight: 220).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 20))
                Text(store.selectedFurnitureName).font(.title3.weight(.heavy))
                Text(dimensions).font(.caption).foregroundStyle(RoomTheme.secondary)
                orientationControls
                positionControls
                if let issue = store.selectedArrangementIssue68 {
                    Label(store.arrangementIssueText68(issue), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button { store.storeSelectedFurniture() } label: {
                    Label(GameStrings.text("layout.storeFurniture"), systemImage: "backpack.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large).tint(RoomTheme.coralDeep)
                    .disabled(!store.canEditArrangement68 || !store.canStoreSelectedFurniture).accessibilityIdentifier("macBuildPutAway")
                Button { store.confirmArrangementSelection68() } label: {
                    Text(GameStrings.text(store.selectedArrangementIssue68 == nil ? "build68.placeHere" : "build68.invalid")).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(RoomTheme.mint)
                    .disabled(!store.canEditArrangement68 || store.selectedArrangementIssue68 != nil).accessibilityIdentifier("macBuildConfirm")
            } else {
                Label(GameStrings.text("mac.build.pickFurniture"), systemImage: "hand.point.up.left.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(RoomTheme.ink)
                Text(GameStrings.text("mac.build.pickHint")).font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(GameStrings.text("mac.build.v2.placedHere"), systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).padding(.top, 10)
                ForEach(placedOnFloor, id: \.id) { item in
                    Button { store.selectFurniture(id: item.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cube.fill").foregroundStyle(RoomTheme.wood)
                            Text(GameStrings.text(FurnitureCatalog.metadata(for: item.kind).nameKey)).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(GameStrings.text("build68.facing." + (store.draftFurnitureOrientations?[item.id] ?? item.orientation).rawValue))
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        }.padding(.vertical, 7).padding(.horizontal, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!store.canEditArrangement68)
                }
            }
        }.padding(16).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2))
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
        VStack(spacing: 12) {
            HStack {
                Text(GameStrings.text("mac.build.facing")); Spacer()
                Text(GameStrings.text("build68.facing." + (selected?.orientation.rawValue ?? "front"))).foregroundStyle(RoomTheme.darkMint)
            }.font(.caption.weight(.bold))
            HStack {
                tool("arrow.counterclockwise", .rotateLeft) { store.rotateSelectedFurniture68(clockwise: false) }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(FurnitureOrientation.allCases, id: \.self) { direction in
                        Circle().fill(selected?.orientation == direction ? RoomTheme.mint : RoomTheme.track).frame(width: 9, height: 9)
                    }
                }.accessibilityHidden(true)
                Spacer()
                tool("arrow.clockwise", .rotateRight) { store.rotateSelectedFurniture68(clockwise: true) }
            }.disabled(!store.canEditArrangement68 || selected?.kind.supportsRotation != true)
            if selected?.kind.supportsRotation != true {
                Text(GameStrings.text(selected == nil ? "layout.bowlCannotFlip" : "layout.wallCannotFlip"))
                    .font(.caption2).foregroundStyle(RoomTheme.secondary)
            }
        }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
    }
    private var positionControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(GameStrings.text("mac.build.position")); Spacer()
                Text(GameStrings.text(store.arrangement68.snapEnabled ? "build68.nudgeHalf" : "build68.nudgeFine"))
            }.font(.caption.weight(.bold))
            if let point = selectedPosition {
                Text(String(format: "X %.2f · Y %.2f", point.x, point.y)).monospacedDigit().foregroundStyle(RoomTheme.secondary)
            }
            HStack(spacing: 8) {
                tool("arrow.left", .nudgeLeft) { store.nudgeSelectedFurniture68(dx: -1, dy: 0) }
                tool("arrow.up", .nudgeUp) { store.nudgeSelectedFurniture68(dx: 0, dy: -1) }
                tool("arrow.down", .nudgeDown) { store.nudgeSelectedFurniture68(dx: 0, dy: 1) }
                tool("arrow.right", .nudgeRight) { store.nudgeSelectedFurniture68(dx: 1, dy: 0) }
            }.disabled(!store.canEditArrangement68)
        }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
    }
    private func tool(_ symbol: String, _ command: MacCommand, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).frame(width: 34, height: 34)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 10))
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
