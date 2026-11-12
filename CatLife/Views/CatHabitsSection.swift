import SwiftUI
import CatGameCore

enum HabitRoomPromptLayout {
    static func frame(above anchor: CGRect, within bounds: CGRect, height: CGFloat) -> CGRect {
        let width = min(300, max(0, bounds.width))
        let height = min(max(0, height), max(0, bounds.height))
        let x = min(bounds.maxX - width, max(bounds.minX, anchor.midX - width / 2))
        let y = min(bounds.maxY - height, max(bounds.minY, anchor.minY - height - 10))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
struct HabitMemorySlot68 {
    let kind: CatMemoryKind
    let memory: CatMemory?
    var title: String { GameStrings.text(memory == nil ? "habit68.memory.empty" : kind.titleKey) }
    var accessibilityIdentifier: String { memory.map { "catMemory_\($0.id)" } ?? "habitMemoryEmpty_\(kind.rawValue)" }

    init(kind: CatMemoryKind, cat: CatState) {
        self.kind = kind
        memory = cat.habits.memories.first { $0.kind == kind }
    }

    static func symbol(for kind: CatMemoryKind) -> String {
        switch kind {
        case .firstResponse: "hand.wave.fill"
        case .favoriteRest: "moon.stars.fill"
        case .favoritePlay: "tennisball.fill"
        case .littleCorner: "flag.fill"
        case .settledAfterMove: "arrow.up.left.and.arrow.down.right"
        case .understandEachOther: "heart.fill"
        }
    }

    static func tint(for kind: CatMemoryKind) -> Color {
        switch kind {
        case .firstResponse: RoomTheme.gold
        case .favoriteRest: RoomTheme.lilac
        case .favoritePlay: RoomTheme.friendship
        case .littleCorner: RoomTheme.mint
        case .settledAfterMove: RoomTheme.sky
        case .understandEachOther: RoomTheme.friendshipDeep
        }
    }
}

@MainActor
struct CatHabitsSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: GameStore
    let cat: CatState
    @State private var choosing = false
    @State private var showingGuide = false
    @State private var expandedMemory: CatMemory?
    @State private var visitingCorner = false
    @State private var cornerVisitID: UUID?

    var body: some View {
        if let definition = CatHabitCatalog.definition(for: cat.id) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack { habitsTitle; Spacer(minLength: 8); slowly }
                    VStack(alignment: .leading, spacing: 5) { habitsTitle; slowly }
                }
                Label(GameStrings.text("catHabits.style.\(definition.style.rawValue)"), systemImage: "quote.opening")
                    .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 13))
                habitRow("catHabits.rest", value: cat.habits.restConfirmed
                         ? GameStrings.text("catHabits.restConfirmed.\(definition.rest.rawValue)") : GameStrings.text("catHabits.learning"),
                         count: cat.habits.restClueSessionIDs.count, confirmed: cat.habits.restConfirmed,
                         symbol: "moon.stars.fill", tint: RoomTheme.lilac, emptyKey: "habit68.clues.none.rest", id: "habitRestProgress")
                habitRow("catHabits.play", value: cat.habits.playConfirmed
                         ? GameStrings.text("catHabits.playConfirmed.\(definition.play.rawValue)") : GameStrings.text("catHabits.learning"),
                         count: cat.habits.playClueSessionIDs.count, confirmed: cat.habits.playConfirmed,
                         symbol: "tennisball.fill", tint: RoomTheme.friendship, emptyKey: "habit68.clues.none.play", id: "habitPlayProgress")
                cornerRow(definition)
                if let receipt = cat.habits.lastRestObservation, canChoose(receipt) {
                    Button { choose(receipt) } label: {
                        Label(GameStrings.text(cat.habits.cornerFurnitureID == nil ? "catHabits.chooseCorner" : "catHabits.changeCorner"), systemImage: "flag.fill")
                            .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                    }.buttonStyle(SoftButtonStyle()).disabled(choosing || store.isBusy)
                        .accessibilityIdentifier("habitChooseCorner")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 25)
            .accessibilityElement(children: .contain).accessibilityIdentifier("catHabitsSection")
            .onDisappear { cornerVisitID = nil }
            memories
            pinnedGuide
        }
    }

    private var habitsTitle: some View {
        Label(GameStrings.text("catHabits.title"), systemImage: "magnifyingglass")
            .font(.headline.weight(.heavy)).foregroundStyle(RoomTheme.ink).accessibilityAddTraits(.isHeader)
    }

    private var slowly: some View {
        Text(GameStrings.text("habit68.slowly")).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func habitRow(_ title: String, value: String, count: Int, confirmed: Bool,
                          symbol: String, tint: Color, emptyKey: String, id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 40, height: 44).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text(title)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(confirmed ? RoomTheme.ink : RoomTheme.secondary)
                Text(confirmed ? GameStrings.text("habit68.clues.confirmed")
                     : count == 0 ? GameStrings.text(emptyKey) : GameStrings.format("catHabits.clues", count))
                    .font(.caption2.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<CatHabitCatalog.cluesToConfirm, id: \.self) { index in
                    Circle().fill(index < count ? tint : .clear)
                        .overlay(Circle().strokeBorder(index < count ? tint : RoomTheme.track,
                            style: StrokeStyle(lineWidth: 2, dash: index < count ? [] : [4, 3])))
                        .frame(width: 14, height: 14)
                }
            }.accessibilityHidden(true)
        }
        .padding(10).background(confirmed ? tint.opacity(0.055) : .white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(confirmed ? tint.opacity(0.3) : RoomTheme.track.opacity(0.7), lineWidth: 2))
        .accessibilityElement(children: .combine).accessibilityIdentifier(id)
        .accessibilityValue(TownEventAccessibility.value(value, diagnostic: "\(count)/\(CatHabitCatalog.cluesToConfirm)"))
    }

    @ViewBuilder
    private func cornerRow(_ definition: CatHabitDefinition) -> some View {
        if let id = cat.habits.cornerFurnitureID,
           let item = store.snapshot?.inventory.furniture.first(where: { $0.id == id }),
           let placement = store.snapshot?.home.furniture.first(where: { $0.itemID == id }) {
            Button { visitCorner(id: id, placement: placement) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill").foregroundStyle(RoomTheme.friendship).accessibilityHidden(true)
                    Text(GameStrings.format("habit68.corner", GameStrings.furnitureName(item), GameStrings.text("homeFloor.\(placement.floor.rawValue)")))
                        .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Label(GameStrings.text("habit68.corner.visit"), systemImage: "chevron.right")
                        .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
                }.fixedSize(horizontal: false, vertical: true).padding(12).frame(minHeight: 44)
                    .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).disabled(visitingCorner || store.isBusy || store.isDecorating)
            .accessibilityIdentifier("habitCorner")
        } else if cat.habits.restConfirmed,
                  store.snapshot?.home.furniture.contains(where: { placement in
                      store.snapshot?.inventory.furniture.contains { $0.id == placement.itemID && $0.kind == definition.rest.furnitureKind } == true
                  }) != true {
            cornerMessage(GameStrings.text("catHabits.missing.\(definition.rest.rawValue)"), id: "habitCornerMissing")
        } else {
            cornerMessage(GameStrings.text("habit68.corner.empty"), id: "habitCornerEmpty")
        }
    }

    private func cornerMessage(_ text: String, id: String) -> some View {
        Label(text, systemImage: "flag.fill").font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.track.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier(id)
    }

    private var memories: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { memoriesTitle; Spacer(minLength: 8); memoriesSubtitle }
                VStack(alignment: .leading, spacing: 5) { memoriesTitle; memoriesSubtitle }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 12) {
                ForEach(CatMemoryKind.allCases, id: \.self) { kind in
                    memoryTile(HabitMemorySlot68(kind: kind, cat: cat))
                }
            }
            if cat.habits.memories.count < CatMemoryKind.allCases.count {
                Text(GameStrings.text("habit68.memory.new")).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 25)
        .accessibilityElement(children: .contain).accessibilityIdentifier("catMemoriesSection")
        .id("catMemoriesAnchor")
        .sheet(item: $expandedMemory) { memory in HabitMemoryDetail68(store: store, cat: cat, memory: memory) }
    }

    private var memoriesTitle: some View {
        Label(GameStrings.format("habit68.memories.count", cat.habits.memories.count, CatMemoryKind.allCases.count), systemImage: "photo.fill")
            .font(.headline.weight(.heavy)).accessibilityAddTraits(.isHeader)
    }

    private var memoriesSubtitle: some View {
        Text(GameStrings.text("habit68.memories.noReward")).font(.caption2.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func memoryTile(_ slot: HabitMemorySlot68) -> some View {
        if let memory = slot.memory {
            Button { expandedMemory = memory } label: {
                VStack(spacing: 7) {
                    Image(systemName: HabitMemorySlot68.symbol(for: slot.kind))
                        .font(.system(size: 27, weight: .semibold)).foregroundStyle(HabitMemorySlot68.tint(for: slot.kind))
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(HabitMemorySlot68.tint(for: slot.kind).opacity(0.19), in: RoundedRectangle(cornerRadius: 5))
                    Text(slot.title).font(.caption2.weight(.heavy)).foregroundStyle(RoomTheme.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .padding(6).padding(.bottom, 3).background(.white, in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: RoomTheme.ink.opacity(0.14), radius: 4, y: 3)
                .rotationEffect(.degrees(slot.kind == .firstResponse || slot.kind == .littleCorner ? -1.5 : 1))
            }
            .buttonStyle(.plain).accessibilityLabel(slot.title).accessibilityIdentifier(slot.accessibilityIdentifier)
        } else {
            VStack(spacing: 7) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 25)).foregroundStyle(RoomTheme.track)
                    .frame(maxWidth: .infinity, minHeight: 62).accessibilityHidden(true)
                Text(slot.title).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .padding(6).padding(.bottom, 3)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(RoomTheme.track, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .accessibilityElement(children: .combine).accessibilityIdentifier(slot.accessibilityIdentifier)
        }
    }

    private var pinnedGuideLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private var pinnedGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(GameStrings.text("habit67.pinTitle"), systemImage: "pin.fill")
                .font(.headline.weight(.heavy)).foregroundStyle(RoomTheme.ink).accessibilityAddTraits(.isHeader)
            pinnedGuideLayout {
                Image(systemName: HabitMemorySlot68.symbol(for: cat.habits.pinnedMemory ?? .settledAfterMove))
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(RoomTheme.sky).frame(width: 38, height: 44)
                    .background(RoomTheme.sky.opacity(0.15), in: RoundedRectangle(cornerRadius: 13)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    if let memory = cat.habits.pinnedMemory {
                        Text(GameStrings.text(CompanionshipPresentation.guideKey(for: memory)))
                            .font(.subheadline.weight(.heavy)).accessibilityIdentifier("habitPinnedGuide")
                            .accessibilityValue(TownEventAccessibility.value(GameStrings.text(CompanionshipPresentation.guideKey(for: memory)),
                                diagnostic: "\(memory.rawValue)|\(cat.habits.pinnedHintCollapsed ? "collapsed" : "expanded")"))
                        Text(GameStrings.text("habit68.guide.current")).font(.caption2.weight(.semibold))
                    } else {
                        Text(GameStrings.text("habit68.guide.none")).font(.subheadline.weight(.heavy))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { showingGuide = true } label: {
                    Label(GameStrings.text(cat.habits.pinnedMemory == nil ? "habit67.chooseGuide" : "habit67.changeGuide"), systemImage: "chevron.right")
                        .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(store.isBusy).accessibilityIdentifier("habitGuideMenu")
            }
            .fixedSize(horizontal: false, vertical: true).padding(12)
            .background(RoomTheme.sky.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RoomTheme.sky.opacity(0.25), lineWidth: 2))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 25)
        .sheet(isPresented: $showingGuide) { HabitGuidePicker68(store: store, cat: cat) }
    }

    private func visitCorner(id: String, placement: FurniturePlacement) {
        guard !visitingCorner, !store.isBusy, !store.isDecorating, !store.saveTransferInProgress else { return }
        let visitID = UUID()
        cornerVisitID = visitID
        visitingCorner = true
        let generation = store.saveSceneGeneration
        let sourceSheet = store.activeSheet
        let sourceSettings = store.isShowingSettings
        let sourceInspection = store.inspectedCatID
        let companionID = store.cat?.id
        Task {
            defer { visitingCorner = false }
            await store.changeHomeFloor(to: placement.floor)
            guard cornerVisitID == visitID, generation == store.saveSceneGeneration,
                  store.visibleHomeFloor == placement.floor, !store.isBusy, !store.saveTransferInProgress,
                  !store.isDecorating, store.activeSheet == sourceSheet, store.isShowingSettings == sourceSettings,
                  store.inspectedCatID == sourceInspection, store.cat?.id == companionID,
                  store.snapshot?.cats.first(where: { $0.id == cat.id })?.habits.cornerFurnitureID == id,
                  store.snapshot?.home.furniture.first(where: { $0.itemID == id }) == placement else { return }
            store.goToTaskDestination(.care)
            store.inspectedCatID = nil
        }
    }

    private func canChoose(_ receipt: CatRestObservationReceipt) -> Bool {
        cat.habits.cornerFurnitureID != receipt.furnitureID && store.snapshot?.home.furniture.contains(where: {
            $0.itemID == receipt.furnitureID && $0.floor == receipt.location.floor && $0.position == receipt.location.position
        }) == true
    }

    private func choose(_ receipt: CatRestObservationReceipt) {
        choosing = true
        Task { _ = await store.chooseHabitCorner(catID: cat.id, observationID: receipt.id); choosing = false }
    }
}

@MainActor
private struct HabitMemoryDetail68: View {
    let store: GameStore
    let cat: CatState
    let memory: CatMemory
    @Environment(\.dismiss) private var dismiss
    @State private var showingGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: HabitMemorySlot68.symbol(for: memory.kind)).font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(HabitMemorySlot68.tint(for: memory.kind)).frame(width: 96, height: 96)
                        .background(HabitMemorySlot68.tint(for: memory.kind).opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
                    Text(GameStrings.text(memory.kind.titleKey)).font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                    Text(CompanionshipPresentation.memoryBody(for: memory.kind, cat: cat))
                        .font(.body.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        .accessibilityIdentifier("habitMemoryBody_\(memory.kind.rawValue)")
                    Text(CatGrowthPresentation.date(memory.createdAt)).font(.caption).foregroundStyle(RoomTheme.secondary)
                    if memory.kind.isPinnable {
                        Button { showingGuide = true } label: {
                            Label(GameStrings.text("habit67.pin"), systemImage: "pin.fill").font(.subheadline.weight(.heavy))
                        }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy)
                            .accessibilityIdentifier("habitMemoryPin_\(memory.kind.rawValue)")
                    }
                }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(24)
            }
            .background(RoomTheme.cream)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(GameStrings.text("common.close")) { dismiss() } } }
        }
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).presentationBackground(RoomTheme.cream)
        .sheet(isPresented: $showingGuide) { HabitGuidePicker68(store: store, cat: cat, initialSelection: memory.kind) }
        .safeAreaInset(edge: .top, spacing: 0) { SaveStatusBanner(store: store) }
        .saveRecoveryAlert(store: store, isActive: !store.isPresentingHabitGuide)
        .onAppear { store.isPresentingHabitMemory = true }
        .onDisappear { store.isPresentingHabitMemory = false }
        .onChange(of: store.saveSceneGeneration) { _, _ in dismiss() }
    }
}

@MainActor
struct HabitCornerOfferView: View {
    let store: GameStore
    let catID: String
    let receipt: CatRestObservationReceipt
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == catID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flag.fill").font(.title2.weight(.semibold)).foregroundStyle(RoomTheme.friendship)
                    .frame(width: 44, height: 48).background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(GameStrings.text(cat?.habits.cornerFurnitureID == nil ? "catHabits.chooseCorner" : "catHabits.changeCorner"))
                        .font(.headline.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                    if !store.habitStudyMode, let cat,
                       let item = store.snapshot?.inventory.furniture.first(where: { $0.id == receipt.furnitureID }) {
                        Text(GameStrings.format("habit68.corner.woke", GameStrings.catName(cat), GameStrings.furnitureName(item)))
                            .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    }
                }
            }
            if let cat {
                Text(GameStrings.format("habit68.corner.choice", GameStrings.catName(cat)))
                    .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.ink).padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 8) {
                Button(GameStrings.text("catHabits.later")) { store.dismissHabitCorner(catID: catID, observationID: receipt.id) }
                    .buttonStyle(SaveTransferOutlineButtonStyle(tint: RoomTheme.ink, fill: .white))
                    .accessibilityIdentifier("habitCornerLater")
                Button { Task { _ = await store.chooseHabitCorner(catID: catID, observationID: receipt.id) } } label: {
                    Text(GameStrings.text("catHabits.keepCorner")).font(.caption.weight(.heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(FriendshipButtonStyle()).accessibilityIdentifier("habitCornerKeep")
            }.font(.caption.weight(.bold)).disabled(store.isBusy)
        }
        .fixedSize(horizontal: false, vertical: true).padding(14).gameCard(cornerRadius: 25)
        .accessibilityElement(children: .contain).accessibilityIdentifier("habitCornerOffer")
    }
}
