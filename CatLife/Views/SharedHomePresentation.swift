import SwiftUI
import CatGameCore

@MainActor
enum SharedHomePresentation {
    static func locationKey(catID: String, activeID: String, floor: HomeFloor, roomLevel: Int, visibleIDs: Set<String>?) -> String {
        if catID == activeID { return "room.location.companion.\(floor.rawValue)" }
        if visibleIDs?.contains(catID) == true { return "room.location.resident.\(floor.rawValue)" }
        return roomLevel >= RoomResidentCats.unlockLevel && visibleIDs != nil ? "room.location.noSpace" : "room.location.collection"
    }
}

@MainActor
struct RoomResidentPreviewCard: View {
    let store: GameStore
    let cat: CatState
    let close: () -> Void
    var openGrowth: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 36)
                    .frame(width: 44, height: 44)
                    .background(RoomTheme.wood.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: GameStrings.catName(cat)).font(.subheadline.weight(.heavy))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                    Text(GameStrings.text("hospital.coat.\(cat.appearance.rawValue)") + " · " + GameStrings.text("catGrowth.bond.\(CatBondStage.stage(for: cat.intimacy).rawValue)"))
                        .font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { profileButton; companionButton }
            } else {
                HStack(spacing: 8) { profileButton; companionButton }
            }
        }.padding(12).gameCard(cornerRadius: 23)
            .shadow(color: RoomTheme.ink.opacity(0.2), radius: 14, y: 6)
            .accessibilityElement(children: .contain).accessibilityIdentifier("roomResidentPreview")
            .accessibilityValue(TownEventAccessibility.value(GameStrings.catName(cat), diagnostic: cat.id))
            .accessibilityAction(.escape) { if !saving && !store.isBusy { close() } }
    }

    private var profileButton: some View {
        Button {
            if let openGrowth { openGrowth() }
            else { close(); store.inspectCat(catID: cat.id, showGrowth: true) }
        } label: {
            Label(GameStrings.text("home63.profileAction"), systemImage: "person.text.rectangle.fill")
                .font(.caption2.weight(.heavy)).lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }.buttonStyle(SoftButtonStyle()).disabled(saving || store.isBusy)
            .accessibilityLabel(GameStrings.format("room.inspectResident", GameStrings.catName(cat)))
            .accessibilityIdentifier("roomResidentGrowthButton")
    }

    private var companionButton: some View {
        Button { select() } label: {
            Text(GameStrings.text(cat.id == store.cat?.id ? "room.companionNow" : "room.setCompanion"))
                .font(.caption2.weight(.heavy)).lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }.buttonStyle(MintButtonStyle()).disabled(saving || store.isBusy || cat.id == store.cat?.id)
            .accessibilityIdentifier("roomResidentCompanionButton")
    }

    private func select() {
        guard !saving, !store.isBusy else { return }
        saving = true
        let generation = store.saveSceneGeneration
        Task {
            let saved = await store.selectCompanion(catID: cat.id)
            saving = false
            if saved, generation == store.saveSceneGeneration {
                store.showNotice(GameStrings.format("room.caringNow", GameStrings.catName(cat))); close()
            }
        }
    }
}

@MainActor
struct SharedHomeDirectoryView: View {
    let store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var saving = false
    private var unlocked: Bool { (store.snapshot?.home.roomLevel ?? 1) >= RoomResidentCats.unlockLevel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(GameStrings.text("room.myCats")).font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(RoomTheme.track, in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel(GameStrings.text("common.done")).accessibilityIdentifier("sharedHomeDirectoryClose")
                }
                Label(unlocked ? GameStrings.text("catDirectory.sharedHomeUnlocked")
                      : GameStrings.format("catDirectory.sharedHomeLocked", RoomResidentCats.unlockLevel),
                      systemImage: unlocked ? "house.fill" : "lock.fill")
                    .font(.caption.weight(.heavy)).foregroundStyle(unlocked ? RoomTheme.darkMint : RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(unlocked ? RoomTheme.mint.opacity(0.1) : RoomTheme.track, in: RoundedRectangle(cornerRadius: 16))
                ForEach(store.snapshot?.cats ?? []) { cat in
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 10) { identity(cat); companionButton(cat) }
                        } else {
                            HStack(spacing: 10) { identity(cat); companionButton(cat) }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 23)
                        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(cat.id == store.cat?.id ? RoomTheme.mint : .clear, lineWidth: 2.5))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("sharedHomeCat_\(cat.id)")
                }
            }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("sharedHomeDirectory")
            .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).presentationBackground(RoomTheme.cream)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large]
                : [.height(min(640, CGFloat(store.snapshot?.cats.count ?? 1) * 84 + 180)), .large])
            .presentationContentInteraction(.scrolls).presentationDragIndicator(.visible).interactiveDismissDisabled(saving)
    }
    private func identity(_ cat: CatState) -> some View {
        let key = SharedHomePresentation.locationKey(catID: cat.id, activeID: store.cat?.id ?? "", floor: store.visibleHomeFloor,
            roomLevel: store.snapshot?.home.roomLevel ?? 1, visibleIDs: store.visibleRoomCatIDs)
        return HStack(spacing: 10) {
            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 40)
                .frame(width: 48, height: 48).background(RoomTheme.wood.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: GameStrings.catName(cat)).font(.subheadline.weight(.heavy))
                Text(GameStrings.text(key)).font(.caption.weight(.bold)).foregroundStyle(key == "room.location.noSpace" ? RoomTheme.gold : RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func companionButton(_ cat: CatState) -> some View {
        if cat.id == store.cat?.id {
            Text(GameStrings.text("room.companionNow")).font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
                .padding(10).background(RoomTheme.mint.opacity(0.1), in: Capsule())
        } else {
            Button {
                guard !saving, !store.isBusy else { return }
                saving = true
                let generation = store.saveSceneGeneration
                Task {
                    let saved = await store.selectCompanion(catID: cat.id)
                    saving = false
                    if saved, generation == store.saveSceneGeneration {
                        store.showNotice(GameStrings.format("room.caringNow", GameStrings.catName(cat))); dismiss()
                    }
                }
            } label: {
                Text(GameStrings.text("room.setCompanion")).font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).frame(minHeight: 44).background(RoomTheme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(RoomTheme.mint.opacity(0.4), lineWidth: 2))
            }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).disabled(saving || store.isBusy)
                .accessibilityIdentifier("sharedHomeSelect_\(cat.id)")
        }
    }
}
