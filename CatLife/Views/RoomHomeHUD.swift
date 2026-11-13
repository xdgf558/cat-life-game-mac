import SwiftUI
import CatGameCore

@MainActor
struct RoomHomeHUD: View {
    let store: GameStore
    let catNeedPresentation: CatNeedPresentation
    @State private var showsResidents = false
    private var hasUpperFloor: Bool { store.snapshot?.home.availableFloors.count == 2 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                homePlaque
                resourceCapsule.frame(width: 176)
            }.frame(height: 44)
            if store.isDecorating {
                if store.hasUnsavedLayoutChanges {
                    Label(GameStrings.text("layout.unsaved"), systemImage: "pencil")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoomTheme.rewardPaper, in: Capsule())
                        .accessibilityIdentifier("layoutUnsavedChanges")
                }
            } else {
                HStack(spacing: 6) {
                    caringContext
                    if store.cat?.healthState?.illness != nil {
                        Button { store.openHospital(catID: store.cat?.id) } label: {
                            Image(systemName: "cross.case.fill").font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(RoomTheme.coralDeep).frame(width: 44, height: 44)
                                .background(RoomTheme.paleCoral, in: Circle()).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(store.isBusy)
                            .accessibilityLabel(GameStrings.text("hospital.healthAlert"))
                            .accessibilityIdentifier("homeCatIllnessButton")
                    }
                    if hasUpperFloor { floorSelector }
                    decorateButton
                }.frame(height: 44)
                if store.onboarding.isActive && !store.onboarding.isPresented {
                    GuideResumeBar(store: store).frame(minHeight: 44)
                }
                if store.sharedRoomHasLimitedSpace {
                    Label(GameStrings.text("room.sharedHomeNoSpace"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(RoomTheme.secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("sharedHomeSpaceBanner")
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { catNeedPresentation.headerFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in catNeedPresentation.headerFrame = frame }
            }.allowsHitTesting(false)
        }
        .onDisappear { catNeedPresentation.headerFrame = nil }
        .sheet(isPresented: $showsResidents) { SharedHomeDirectoryView(store: store) }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), let cat = store.cat {
                Text("").frame(width: 1, height: 1).allowsHitTesting(false)
                    .accessibilityElement().accessibilityLabel("Cat care state")
                    .accessibilityIdentifier("homeCareState63")
                    .accessibilityValue(careDiagnostics(cat))
            }
        }
        #endif
    }

    private var homePlaque: some View {
        HStack(spacing: 5) {
            Image(systemName: store.isDecorating ? "sofa.fill" : "pawprint.fill")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .accessibilityHidden(true)
            Text(store.isDecorating ? GameStrings.text("layout.edit") : store.homeDisplayName)
                .font(.system(size: 17, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !store.isDecorating {
                Text(GameStrings.format("home63.level", store.snapshot?.home.roomLevel ?? 1))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 3).background(RoomTheme.paper, in: Capsule())
                    .fixedSize().accessibilityHidden(true)
            }
        }
        .foregroundStyle(RoomTheme.ink).padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(RoomTheme.wood)
                .shadow(color: RoomTheme.secondary.opacity(0.35), radius: 0, y: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.secondary.opacity(0.4), lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.isDecorating ? GameStrings.text("layout.edit") : store.homeDisplayName)
        .accessibilityValue(GameStrings.format("home63.level", store.snapshot?.home.roomLevel ?? 1))
        .accessibilityIdentifier("homeNamePlaque")
    }

    private var resourceCapsule: some View {
        HStack(spacing: 7) {
            resource(symbol: "dollarsign.circle.fill", value: store.snapshot?.player.gold ?? 0,
                     key: "resource.gold", id: "goldCount", tint: RoomTheme.gold)
            Rectangle().fill(RoomTheme.wood.opacity(0.7)).frame(width: 1, height: 18).accessibilityHidden(true)
            resource(symbol: "bolt.fill", value: store.snapshot?.player.stamina ?? 0,
                     key: "resource.stamina", id: "staminaCount", tint: RoomTheme.mint, showsMaximum: true)
        }
        .font(.system(size: 15, weight: .heavy)).monospacedDigit()
        .padding(.horizontal, 10).frame(height: 44)
        .background { Capsule().fill(RoomTheme.paper).shadow(color: RoomTheme.ink.opacity(0.1), radius: 0, y: 3) }
        .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
        .accessibilityElement(children: .contain).accessibilityIdentifier("homeResourceCapsule")
    }

    private func resource(symbol: String, value: Int, key: String, id: String, tint: Color,
                          showsMaximum: Bool = false) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 15, weight: .heavy))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(value)").lineLimit(1).minimumScaleFactor(0.6)
                if showsMaximum { Text("/100").font(.system(size: 10, weight: .bold)).foregroundStyle(RoomTheme.secondary) }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text(key))
        .accessibilityValue("\(value)").accessibilityIdentifier(id)
    }

    private var caringContext: some View {
        Button { showsResidents = true; store.playNavigationSound() } label: {
            HStack(spacing: 6) {
                HStack(spacing: -10) {
                    ForEach(Array(caringCats.prefix(hasUpperFloor ? 2 : 3))) { cat in
                        GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 26)
                            .padding(2).background(RoomTheme.paper, in: Circle())
                            .overlay(Circle().strokeBorder(cat.id == store.cat?.id ? RoomTheme.mint : .white, lineWidth: 2))
                            .zIndex(cat.id == store.cat?.id ? 1 : 0)
                    }
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(GameStrings.format("room.caringFor", store.cat.map(GameStrings.catName) ?? ""))
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text(hasUpperFloor ? GameStrings.text("home63.switchShort")
                         : GameStrings.format("home63.switchSummary", store.snapshot?.cats.count ?? 0))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8).accessibilityIdentifier("homeCatSwitchHint")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 44)
            .background { Capsule().fill(RoomTheme.paper).shadow(color: RoomTheme.ink.opacity(0.1), radius: 0, y: 3) }
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain).disabled(store.isBusy).accessibilityIdentifier("homeMyCatsButton")
        .accessibilityLabel(GameStrings.format("room.caringFor", store.cat.map(GameStrings.catName) ?? "")
            + ", " + GameStrings.text("room.myCats"))
        .accessibilityValue(TownEventAccessibility.value(store.catStatus, diagnostic: store.cat?.id ?? ""))
        .accessibilityHint(GameStrings.text("room.switchHint"))
    }

    private var caringCats: [CatState] {
        guard let cat = store.cat else { return store.snapshot?.cats ?? [] }
        return [cat] + (store.snapshot?.cats ?? []).filter { $0.id != cat.id }
    }

    private var floorSelector: some View {
        HStack(spacing: 1) {
            ForEach(store.snapshot?.home.availableFloors ?? [], id: \.self) { floor in
                Button { Task { await store.changeHomeFloor(to: floor) } } label: {
                    Text(floor == .ground ? "1F" : "2F").font(.system(size: 12, weight: .heavy))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(store.visibleHomeFloor == floor ? .white : RoomTheme.ink)
                        .background(store.visibleHomeFloor == floor ? RoomTheme.mint : .clear, in: Circle())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(store.isBusy || store.isChangingHomeFloor)
                    .accessibilityLabel(GameStrings.text("homeFloor.\(floor.rawValue)"))
                    .accessibilityValue(TownEventAccessibility.value("", diagnostic: store.visibleHomeFloor == floor ? "selected" : "unselected"))
                    .accessibilityIdentifier("homeFloor_\(floor.rawValue)")
                    .accessibilityAddTraits(store.visibleHomeFloor == floor ? .isSelected : [])
            }
        }.padding(1).background(RoomTheme.paper, in: Capsule())
    }

    private var decorateButton: some View {
        Button { store.beginDecorating() } label: {
            HStack(spacing: 5) {
                Image(systemName: "sofa.fill").font(.system(size: 17, weight: .semibold))
                if !hasUpperFloor { Text(GameStrings.text("layout.edit")).font(.system(size: 12, weight: .heavy)).lineLimit(1) }
            }.padding(.horizontal, hasUpperFloor ? 0 : 12).frame(minWidth: 44, minHeight: 44)
                .background(RoomTheme.paper, in: Capsule()).overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(RoomTheme.ink).disabled(store.isBusy)
            .accessibilityIdentifier("homeDecorateButton").accessibilityLabel(GameStrings.text("layout.edit"))
    }

    #if DEBUG
    private func careDiagnostics(_ cat: CatState) -> String {
        var state: [String: Any] = ["id": cat.id, "name": GameStrings.catName(cat), "satiety": cat.satiety, "cleanliness": cat.cleanliness,
                                    "mood": cat.mood, "intimacy": cat.intimacy]
        if let frame = catNeedPresentation.catFrame {
            state["catFrame"] = ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
    #endif
}
