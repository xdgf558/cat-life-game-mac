import SwiftUI
import CatGameCore

@MainActor
struct TownView: View {
    @Bindable var store: GameStore
    @Binding var selectedPlace: TownPlace
    @Binding var layer: TownLayer
    @State private var mapVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var status: TownMapStatus { TownMapStatus(snapshot: store.snapshot) }
    private var reducedMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--town-reduce-motion") { return true }
        #endif
        return reduceMotion
    }
    private var animates: Bool { !reducedMotion && mapVisible && scenePhase == .active && !store.onboarding.isPresented }
    private func isNight(_ now: Date) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--town-night") { return true }
            if ProcessInfo.processInfo.arguments.contains("--town-day") { return false }
        }
        #endif
        return TownMapLayout.isNight(now)
    }

    var body: some View {
        Group {
            if store.isShowingTownBoard {
                TownNoticeBoardView(store: store) { store.isShowingTownBoard = false }
            } else if store.isShowingMarket {
                NavigationStack { ExchangeMarketView(store: store, onClose: { store.isShowingMarket = false }) }
            } else if store.isShowingNeighbors {
                CommunityView(store: store) { store.isShowingNeighbors = false }
            } else if let filter = store.catCollectionFilter {
                CatCollectionView(store: store, initialFilter: filter, embedded: true,
                                  initialAdoptionID: store.adoptionCatID, onClose: {
                    store.catCollectionFilter = nil; store.adoptionCatID = nil
                }).id(store.adoptionCatID ?? "collection")
            } else { map }
        }
        .saveRecoveryAlert(store: store, isActive: !store.onboarding.isPresented
                           && store.inspectedCatID == nil && !store.isPresentingExchange && store.supplyPicker == nil
                           && !store.isPresentingAdoptionConfirmation && !store.isPresentingCommunityGift
                           && !store.isPresentingHabitGuide && !store.isPresentingHabitMemory)
    }

    private var map: some View {
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            let night = isNight(clock.date)
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        header(now: clock.date, night: night, proxy: proxy)
                        ScrollView(.vertical) {
                            if dynamicTypeSize.isAccessibilitySize { accessiblePlaces(proxy: proxy) }
                            else {
                                TownMapCanvas(width: min(640, geometry.size.width), selected: selectedPlace,
                                              layer: layer, status: status, now: store.now, night: night,
                                              animates: animates) { choose($0, proxy: proxy) }
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("townMapScroll")
                        .overlay(alignment: .bottomTrailing) { locateButton(proxy: proxy).padding(12) }
                        .onAppear {
                            mapVisible = true
                            Task { @MainActor in
                                await Task.yield()
                                proxy.scrollTo(selectedPlace, anchor: .center)
                            }
                        }
                        .onDisappear { mapVisible = false }
                        .onChange(of: dynamicTypeSize) { _, _ in proxy.scrollTo(selectedPlace, anchor: .center) }
                        TownMapDetail(store: store, place: selectedPlace, status: status,
                                      primaryKey: primaryKey, primaryIdentifier: primaryIdentifier, enter: enterPlace)
                            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
                    }
                    .background(night ? Color(red: 0.36, green: 0.46, blue: 0.42) : TownPalette.grass)
                }
            }
        }
    }

    private func header(now: Date, night: Bool, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 7) {
                Text(GameStrings.text("tab.town")).font(.system(size: 21, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 13).frame(height: 42)
                    .background(RoomTheme.wood, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(TownPalette.woodEdge, lineWidth: 3))
                    .shadow(color: TownPalette.woodEdge, radius: 0, y: 3)
                    .accessibilityIdentifier("townMapTitle").accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    Image(systemName: night ? "moon.stars.fill" : "sun.horizon.fill").foregroundStyle(night ? RoomTheme.lilac : RoomTheme.gold)
                    Text(GameStrings.text(night ? "townMap.night" : "townMap.day"))
                    Text(now, format: .dateTime.hour().minute())
                }
                .font(.system(size: 11, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).frame(height: 34).background(RoomTheme.paper, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(GameStrings.text(night ? "townMap.night" : "townMap.day") + " " + now.formatted(date: .omitted, time: .shortened))
                .accessibilityIdentifier("townTimeOfDay").accessibilityValue(night ? "night" : "day")
                Spacer(minLength: 0)
                Button { openCollection() } label: {
                    Image(systemName: "book.closed.fill").font(.system(size: 17)).frame(width: 44, height: 44)
                        .foregroundStyle(RoomTheme.darkMint).background(RoomTheme.paper, in: Circle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("townCollectionButton")
                .accessibilityLabel(GameStrings.text("town.myCats"))
                .accessibilityValue(GameStrings.format("catDirectory.count", store.snapshot?.cats.count ?? 0))
                Button { store.openTownBoard() } label: {
                    Image(systemName: "bell.fill").font(.system(size: 19)).frame(width: 44, height: 44)
                        .foregroundStyle(RoomTheme.lilac).background(RoomTheme.paper, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(GameStrings.text("townEvents.title"))
                .accessibilityIdentifier("townCommunityPreviewButton")
                .disabled(store.isBusy)
            }
            HStack(spacing: 5) {
                ForEach(TownLayer.allCases) { item in
                    Button { store.playNavigationSound(); layer = item } label: {
                        Label(GameStrings.text(item.titleKey), systemImage: item.symbol)
                            .font(.system(size: 12, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 28)
                            .foregroundStyle(layer == item ? .white : RoomTheme.ink)
                            .background(layer == item ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                            .frame(height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("townLayer_\(item.rawValue)")
                        .accessibilityAddTraits(layer == item ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 6)
        .background(LinearGradient(colors: [Color(red: 0.80, green: 0.92, blue: 0.96), TownPalette.grass], startPoint: .top, endPoint: .bottom))
        .accessibilityElement(children: .contain).accessibilityIdentifier("townMapToolbar")
    }

    private func accessiblePlaces(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            ForEach(TownMapLayout.readingOrder) { place in
                Button { choose(place, proxy: proxy) } label: {
                    HStack(spacing: 10) {
                        GameIcon(asset: place.asset, symbol: place.symbol, size: 60, tint: place.tint)
                            .overlay(alignment: .topTrailing) {
                                if selectedPlace == place {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(RoomTheme.darkMint, RoomTheme.paper)
                                }
                            }.accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(GameStrings.text(place.titleKey)).font(.headline)
                            Text(status.badge(for: place, now: store.now) ?? GameStrings.text(place.statusKey(sickCount: status.sickCount)))
                                .font(.caption).foregroundStyle(RoomTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
                        .opacity(layer == .all || place.layer == layer || place.isEmpty ? 1 : 0.45)
                }.buttonStyle(.plain).id(place).accessibilityIdentifier(place.accessibilityIdentifier)
                    .accessibilityAddTraits(selectedPlace == place ? .isSelected : [])
            }
        }.padding(12).padding(.bottom, 60)
            .accessibilityElement(children: .contain).accessibilityIdentifier("townMapCanvas").accessibilityValue("static")
    }

    private func locateButton(proxy: ScrollViewProxy) -> some View {
        Button { layer = .all; choose(.home, proxy: proxy) } label: {
            Image(systemName: "location.viewfinder").font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white).frame(width: 46, height: 46).background(RoomTheme.mint, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3)).shadow(color: RoomTheme.darkMint.opacity(0.5), radius: 0, y: 3)
        }.buttonStyle(.plain).accessibilityLabel(GameStrings.text("townMap.locateHome"))
            .accessibilityIdentifier("townMapFocusHome")
    }
    private func choose(_ place: TownPlace, proxy: ScrollViewProxy) {
        store.playFeedback(.pin); selectedPlace = place
        Task { @MainActor in
            await Task.yield()
            guard mapVisible, selectedPlace == place else { return }
            if reducedMotion { proxy.scrollTo(place, anchor: .center) }
            else { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(place, anchor: .center) } }
        }
    }
    private var primaryKey: String {
        if selectedPlace == .adoption, status.availableAdoptions.isEmpty { return "town.viewCats" }
        return selectedPlace.actionKey
    }
    private var primaryIdentifier: String {
        switch selectedPlace {
        case .hospital: "townHospitalButton"
        case .adoption: status.availableAdoptions.isEmpty ? "townAdoptionCollectionButton" : "townMeetCatButton"
        default: "townEnter_\(selectedPlace.rawValue)"
        }
    }
    private func openCollection(filter: CatCollectionView.Filter = .all) {
        store.playNavigationSound(); store.openCatCollection(filter: filter)
    }
    private func enterPlace() {
        switch selectedPlace {
        case .plaza, .board: store.openTownBoard()
        case .street: store.playNavigationSound(); store.isShowingNeighbors = true
        case .hospital: store.openHospital()
        case .market: store.openExchangeMarket()
        case .adoption: openCollection(filter: status.availableAdoptions.isEmpty ? .owned : .unowned)
        case .home, .work, .shop:
            store.isShowingSettings = false; store.inspectedCatID = nil
            store.activeSheet = selectedPlace == .work ? .work : selectedPlace == .shop ? .shop : nil
        default: break
        }
    }
}
